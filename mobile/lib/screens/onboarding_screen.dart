import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'login_screen.dart';

/// First-run screen: enter the team's server address. Nothing is baked into
/// the app — every instance works (tim-a.mediahost.stream, LAN IP, ...).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = TextEditingController(text: 'https://');
  bool _checking = false;
  String? _error;

  Future<void> _connect() async {
    var raw = _ctrl.text.trim();
    if (raw.isEmpty) return;
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) raw = 'https://$raw';
    final url = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;

    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final probe = Api(url);
      final settings = await probe.settings();
      if (!mounted) return;
      final appName = (settings['app_name'] as String?) ?? 'My Team';
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LoginScreen(baseUrl: url, appName: appName),
      ));
    } catch (e) {
      setState(() {
        _checking = false;
        _error = 'Ne mogu se povezati: $e';
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
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: const LinearGradient(colors: [SR.accent, SR.cyan]),
                    boxShadow: const [BoxShadow(color: Color(0x668B7BFF), blurRadius: 28, offset: Offset(0, 12))],
                  ),
                  child: const Icon(Icons.view_kanban_outlined, color: Color(0xFF0B0D1C), size: 40),
                ),
              ),
              const SizedBox(height: 12),
              const Text('My Team', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Unesite adresu vašeg My Team poslužitelja',
                  textAlign: TextAlign.center, style: TextStyle(color: SR.muted)),
              const SizedBox(height: 28),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Adresa poslužitelja', hintText: 'https://tim-primjer.hr'),
                onSubmitted: (_) => _connect(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _checking ? null : _connect,
                child: _checking
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Poveži se'),
              ),
              const Spacer(),
              const Text('Aplikacija radi s bilo kojom My Team instancom — adresu unosite samo jednom.',
                  textAlign: TextAlign.center, style: TextStyle(color: SR.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
