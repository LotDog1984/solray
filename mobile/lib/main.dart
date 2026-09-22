import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final url = await Api.storedUrl();
  final token = await Api.storedToken();
  runApp(SolRayApp(initialUrl: url, initialToken: token));
}

class SolRayApp extends StatelessWidget {
  const SolRayApp({super.key, this.initialUrl, this.initialToken});

  final String? initialUrl;
  final String? initialToken;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SolRay',
      theme: SR.build(),
      home: Bootstrap(initialUrl: initialUrl, initialToken: initialToken),
    );
  }
}

/// Decides the first screen: saved session → home, saved server → login,
/// fresh install → onboarding ("enter your team's address").
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key, this.initialUrl, this.initialToken});

  final String? initialUrl;
  final String? initialToken;

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
    return HomeScreen(api: api);
  }
}
