import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// System (device) notifications — the switch the user sees in Android's
/// app settings becomes active because the app declares POST_NOTIFICATIONS
/// and requests the runtime permission (Android 13+).
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static void Function(String? payload)? _onTap;

  static const _kEnabled = 'solray_notif_enabled';
  static const _kAsked = 'solray_notif_asked';
  static const _channelId = 'solray';
  static const _channelName = 'SolRay obavijesti';

  /// Initialize the plugin; returns the payload of a notification that
  /// launched the app (cold start), or null.
  static Future<String?> init() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      // iOS: permission is requested explicitly later (from settings/home).
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: darwinInit),
        onDidReceiveNotificationResponse: (resp) => _onTap?.call(resp.payload),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Tagovi i nove obavijesti iz SolRaya',
        importance: Importance.high,
      ));
      final launch = await _plugin.getNotificationAppLaunchDetails();
      return launch?.didNotificationLaunchApp ?? false ? launch?.notificationResponse?.payload : null;
    } catch (_) {
      return null; // tests/unsupported platforms — never crash the app
    }
  }

  /// Ask Android for the notification permission. Returns true when granted
  /// (or when the platform grants it by default, e.g. Android < 13).
  static Future<bool> requestPermission() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAsked, true);
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final androidGranted = await android?.requestNotificationsPermission();
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final iosGranted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
      return androidGranted ?? iosGranted ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Is the permission granted on this device?
  static Future<bool> isEnabled() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await android?.areNotificationsEnabled();
      return enabled ?? true; // iOS/unknown: assume enabled
    } catch (_) {
      return false;
    }
  }

  static Future<bool> userWants() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? true;
  }

  static Future<void> setUserWants(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
    if (!value) await _plugin.cancelAll();
  }

  static Future<bool> askedOnce() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAsked) ?? false;
  }

  /// Post a system notification (respects the in-app switch + permission).
  static Future<void> show({required String title, required String body, String? payload}) async {
    try {
      if (!await userWants() || !await isEnabled()) return;
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Tagovi i nove obavijesti iz SolRaya',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      );
      await _plugin.show(0, title, body, details, payload: payload);
    } catch (_) {
      // best-effort — the in-app badge still works
    }
  }

  static void setTapHandler(void Function(String? payload)? handler) => _onTap = handler;
}
