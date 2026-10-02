import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.baseUrl, this.appName, this.client});

  final String baseUrl;
  final String? appName;

  /// Injectable HTTP client for tests (production leaves it null).
  final http.Client? client;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _display = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  /// 1.17.0 (web parity): a brand-new instance has no users at all and the web
  /// app offers first-admin registration — the phone now does the same.
  bool _registrationOpen = false;
  bool _registerMode = false;

  @override
  void initState() {
    super.initState();
    Api(widget.baseUrl, client: widget.client).registrationOpen().then((open) {
      if (mounted && open) setState(() => _registrationOpen = true);
    });
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = Api(widget.baseUrl, client: widget.client);
    try {
      if (_registerMode) {
        await api.register(
          username: _username.text.trim().toLowerCase(),
          displayName: _display.text.trim(),
          password: _password.text,
        );
      } else {
        await api.login(_username.text.trim(), _password.text);
      }
      final me = await api.get('/api/me') as Map<String, dynamic>;
      final settings = await api.settings();
      await Api.saveSession(widget.baseUrl, api.token!);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => HomeScreen(
          api: api,
          session: Session(api: api, me: me, settings: settings),
        ),
      ));
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(widget.appName ?? 'My Team',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(widget.baseUrl, textAlign: TextAlign.center, style: const TextStyle(color: SR.muted, fontSize: 12)),
              const SizedBox(height: 28),
              TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Korisničko ime'),
                textInputAction: TextInputAction.next,
              ),
              if (_registerMode) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _display,
                  decoration: const InputDecoration(labelText: 'Puno ime'),
                  textInputAction: TextInputAction.next,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Lozinka'),
                obscureText: true,
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_registerMode ? 'Registriraj se i uđi' : 'Prijava'),
              ),
              if (_registrationOpen)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _registerMode = !_registerMode;
                            _error = null;
                          }),
                  child: Text(
                    _registerMode
                        ? 'Natrag na prijavu'
                        : 'Nova instanca? Registriraj administratora',
                    style: const TextStyle(color: SR.muted),
                  ),
                ),
              TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await Api.forgetServer();
                  // Back to onboarding — the app rebuilds from scratch.
                  navigator.pushReplacement(
                      MaterialPageRoute(builder: (_) => const OnboardingScreen()));
                },
                child: const Text('Promijeni poslužitelj', style: TextStyle(color: SR.muted)),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
