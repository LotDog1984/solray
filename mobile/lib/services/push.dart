import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api.dart';
import 'notifications.dart';

/// 1.12.0 — real Google push (FCM): messages arrive even when the app is
/// killed, and the same rows/pipeline drive APNs later for iOS (the backend
/// decides per device-platform).
///
/// Architecture: the SolRay backend sends DATA-ONLY FCM messages
/// (`data: {title, body, boardId?, boardName?}`); this app converts them into
/// local system notifications via flutter_local_notifications and deep-links
/// to the board on tap. Data-only keeps Android showing exactly one
/// notification (ours) with full control over sound/vibration/channels.
///
/// The Firebase project is user-supplied (google-services.json is NOT
/// committed) — every call here is wrapped so a missing config means the app
/// simply keeps the ntfy/in-app flow instead of crashing.
class PushNotifications {
  static String? _currentToken;
  static bool _initialized = false;
  static bool _listening = false;

  /// True when a Firebase token exists on this device (registered or not).
  static bool get hasToken => _currentToken != null;

  /// Initialize Firebase + request the token. Returns the FCM token or null
  /// (no config / permission denied / plugin unavailable — all non-fatal).
  static Future<String?> init() async {
    if (_initialized) return _currentToken;
    try {
      await Firebase.initializeApp();
      _initialized = true;
    } catch (_) {
      return null; // no Firebase config (google-services.json) — stay on ntfy
    }
    try {
      // Ask for the POST_NOTIFICATIONS runtime permission (Android 13+).
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      _currentToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
    return _currentToken;
  }

  /// Push the FCM token to the user's own SolRay instance. 1.12.1: retries a
  /// few times (boot races a waking phone network — the old fire-and-forget
  /// single attempt left the device unregistered for hours); re-reads the
  /// token after each wait so a rotation during retry isn't lost.
  static Future<void> registerWithBackend(Api api) async {
    if (_currentToken == null) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
        try {
          _currentToken = await FirebaseMessaging.instance.getToken();
        } catch (_) {}
        if (_currentToken == null) return;
      }
      try {
        final res = await api.post(
            '/api/me/push-token', {'token': _currentToken, 'platform': 'android'});
        final echoed = res['token'] as String?;
        if (echoed != null && echoed != _currentToken) {
          _currentToken = echoed; // rotated between request and response
        }
        return;
      } catch (_) {
        // transient network/auth error — retry, then stay silent (the next
        // app resume retries again)
      }
    }
  }

  /// Server changed or user logged out — remove the token from the old
  /// instance and forget it locally.
  static Future<void> unregister(Api api) async {
    final token = _currentToken;
    if (token == null) return;
    try {
      await api.post('/api/me/push-token/remove', {'token': token});
    } catch (_) {/* best-effort */}
  }

  /// Called by the FCM token listener whenever Google rotates the token.
  static Future<void> onTokenRefresh(String token, Api? api) async {
    _currentToken = token;
    if (api != null) await registerWithBackend(api);
  }

  /// Show the local system notification for an FCM data message.
  static Future<void> showFromData(Map<String, dynamic> data) async {
    final body = data['body'] as String? ?? '';
    if (body.isEmpty) return;
    final boardId = data['boardId'];
    final boardName = data['boardName'] as String? ?? '';
    final payload = boardId != null ? '$boardId:$boardName' : null;
    await Notifications.show(
        title: data['title'] as String? ?? 'SolRay', body: body, payload: payload);
  }

  /// Wire up the background handler. Must be a top-level function (isolate
  /// entry point). The handler runs in a separate isolate where the app's
  /// singletons don't exist — it just posts the system notification.
  @pragma('vm:entry-point')
  static Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      return; // no Firebase config — nothing to show
    }
    await showFromData(message.data);
  }

  /// Foreground stream + token rotation. Safe to call repeatedly (e.g. every
  /// app resume) — listeners attach only once.
  static void listenForeground(Api api) {
    if (!_initialized || _listening) return;
    _listening = true;
    FirebaseMessaging.onMessage.listen((message) {
      // 1.12.2: ALWAYS post the local notification in the foreground. FCM
      // *data* messages are never auto-displayed by the OS integration —
      // even when the payload carries a notification block — so the 1.12.1
      // skip produced total silence while the app was open. Foreground is
      // the only place we control display; background/terminated delivery
      // is displayed by the OS integration itself.
      showFromData(message.data);
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      onTokenRefresh(token, api);
    });
  }

  /// The message that launched the app (cold start from a notification tap),
  /// or null. Note: with data-only messages Android delivers them through the
  /// background handler even on cold start, so this rarely fires — kept for
  /// completeness (e.g. display messages if the backend ever sends them).
  static Future<RemoteMessage?> getInitialMessage() async {
    if (!_initialized) return null;
    try {
      return await FirebaseMessaging.instance.getInitialMessage();
    } catch (_) {
      return null;
    }
  }

  /// Tap on a notification while the app was in the background.
  static void listenTaps(void Function(RemoteMessage message) onTap) {
    if (!_initialized) return;
    FirebaseMessaging.onMessageOpenedApp.listen(onTap);
  }

  @visibleForTesting
  static String? get debugToken => _currentToken;
}
