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
  // 1.12.0: FCM background handler — data-only messages arriving while the
  // app is killed/backgrounded are turned into system notifications in a
  // separate isolate. 1.12.2: the backend's mention pushes carry a
  // notification block, so in background/terminated the OS integration
  // displays them itself and this handler is a fallback for data-only
  // fallback sends. Registered before runApp, as Firebase requires. No-op
  // (caught) when the Firebase config (google-services.json) is absent.
  try {
    FirebaseMessaging.onBackgroundMessage(PushNotifications.firebaseMessagingBackgroundHandler);
  } catch (_) {
    // no Firebase config — the app stays on the ntfy/in-app flow
  }
  final url = await Api.storedUrl();
  final token = await Api.storedToken();
  runApp(MyTeamApp(initialUrl: url, initialToken: token, launchPayload: launchPayload));
}

class MyTeamApp extends StatelessWidget {
  const MyTeamApp({super.key, this.initialUrl, this.initialToken, this.launchPayload});

  final String? initialUrl;
  final String? initialToken;
  final String? launchPayload;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Team',
      theme: SR.build(),
      // Nebula Glass: the aurora backdrop is painted once behind every screen
      // (scaffolds are transparent — see SR.build), so the whole app shares
      // one consistent "space" canvas.
      builder: (context, child) => SR.aurora(context, child),
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
