import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/notifications.dart';
import 'services/push.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchPayload = await Notifications.init();
  // 1.12.0: FCM background handler — notifications arriving while the app is
  // killed/backgrounded are turned into system notifications in a separate
  // isolate. Registered before runApp, as Firebase requires. No-op (caught)
  // when the Firebase config (google-services.json) is absent.
  try {
    FirebaseMessaging.onBackgroundMessage(PushNotifications.firebaseMessagingBackgroundHandler);
  } catch (_) {
    // no Firebase config — the app stays on the ntfy/in-app flow
  }
  final url = await Api.storedUrl();
  final token = await Api.storedToken();
  runApp(SolRayApp(initialUrl: url, initialToken: token, launchPayload: launchPayload));
}

class SolRayApp extends StatelessWidget {
  const SolRayApp({super.key, this.initialUrl, this.initialToken, this.launchPayload});

  final String? initialUrl;
  final String? initialToken;
  final String? launchPayload;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SolRay',
      theme: SR.build(),
      home: Bootstrap(initialUrl: initialUrl, initialToken: initialToken, launchPayload: launchPayload),
    );
  }
}

/// Decides the first screen: saved session → home, saved server → login,
/// fresh install → onboarding ("enter your team's address").
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key, this.initialUrl, this.initialToken, this.launchPayload});

  final String? initialUrl;
  final String? initialToken;
  final String? launchPayload;

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  @override
  Widget build(BuildContext context) {
    if (widget.initialUrl == null) return const OnboardingScreen();
    if (widget.initialToken == null) {
      return LoginScreen(baseUrl: widget.initialUrl!);
    }
    final api = Api(widget.initialUrl!, token: widget.initialToken);
    return HomeScreen(api: api, launchPayload: widget.launchPayload);
  }
}
