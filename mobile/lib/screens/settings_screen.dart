import 'dart:convert';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api.dart';
import '../services/notifications.dart';
import '../services/push.dart';
import '../services/updater.dart';
import '../theme.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Postavke — everything the web app offers:
/// account (logout, change server), notifications (ntfy topic + test),
/// admin (app name, default columns, users).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.session, required this.onChanged});

  final Session session;
  final VoidCallback onChanged; // re-fetch me/settings after edits

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Api api = widget.session.api;
  Map<String, dynamic> get me => widget.session.me;
  bool get isAdmin => me['is_admin'] as bool? ?? false;

  List<Map<String, dynamic>> _users = [];
  String? _error;
  bool _notifOn = false;
  bool _notifPerm = true;

  late final TextEditingController _topic =
      TextEditingController(text: me['ntfy_topic'] as String? ?? '');
  late final TextEditingController _appName =
      TextEditingController(text: widget.session.appName);
  late final TextEditingController _columns = TextEditingController(
      text: (widget.session.settings['default_columns'] as List<dynamic>? ?? [])
          .join(', '));
  late final TextEditingController _todoName = TextEditingController(
      text: (widget.session.settings['default_todo_list'] as String?) ?? 'Nabava');
  bool _checkingNtfy = false;
  String? _ntfyCheck;

  // ---- Ažuriranja (in-app updater) ------------------------------------------
  String _appVersion = '…';
  bool _updChecking = false;
  bool _updBusy = false;
  double _updProgress = 0;
  ReleaseInfo? _updRelease;
  String? _updMessage;

  @override
  void initState() {
    super.initState();
    if (isAdmin) _loadUsers();
    _loadNotifState();
    Updater.currentVersion().then((v) {
      if (mounted) setState(() => _appVersion = v);
    });
  }

  Future<void> _loadNotifState() async {
    final perm = await Notifications.isEnabled();
    final wants = await Notifications.userWants();
    if (mounted) {
      setState(() {
        _notifPerm = perm;
        _notifOn = perm && wants;
      });
    }
  }

  Future<void> _toggleNotif(bool v) async {
    if (v && !_notifPerm) {
      // Turning on without the Android permission → ask for it now.
      await Notifications.requestPermission();
      final nowEnabled = await Notifications.isEnabled();
      if (!nowEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Dozvola je odbijena — uključite je u sistemskim postavkama.')));
        }
        return; // switch stays off
      }
      await Notifications.setUserWants(true);
      if (mounted) {
        setState(() {
          _notifPerm = true;
          _notifOn = true;
        });
      }
      return;
    }
    await Notifications.setUserWants(v);
    if (mounted) setState(() => _notifOn = v);
  }

  Future<void> _loadUsers() async {
    try {
      final users = await api.get('/api/users') as List<dynamic>;
      if (mounted) {
        setState(() => _users = List<Map<String, dynamic>>.from(users.map((u) => Map<String, dynamic>.from(u as Map))));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _toast(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  // ---- notifications -------------------------------------------------------

  Future<void> _saveTopic() async {
    try {
      await api.patch('/api/me/ntfy', {'topic': _topic.text.trim()});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Topic spremljen.')));
      widget.onChanged();
    } catch (e) {
      _toast(e);
    }
  }

  /// Diagnose the SolRay→ntfy connection used for in-app notifications.
  Future<void> _checkNtfyConnection() async {
    final base = widget.session.ntfyBase;
    final topic = me['ntfy_topic'] as String? ?? '';
    setState(() {
      _checkingNtfy = true;
      _ntfyCheck = null;
    });
    if (base.isEmpty) {
      setState(() {
        _checkingNtfy = false;
        _ntfyCheck = '⚠️ Server nije postavio javnu ntfy adresu. Admin: dodajte NTFY_PUBLIC_URL u backend okruženje (compose) i pokrenite stack ponovno.';
      });
      return;
    }
    if (topic.isEmpty) {
      setState(() {
        _checkingNtfy = false;
        _ntfyCheck = '⚠️ Prvo spremite svoj ntfy topic.';
      });
      return;
    }
    WebSocketChannel? ch;
    try {
      final ws = base.replaceFirst(RegExp('^http'), 'ws');
      ch = WebSocketChannel.connect(Uri.parse('$ws/$topic/ws'));
      final msg = await ch.stream.first.timeout(const Duration(seconds: 8));
      final d = jsonDecode(msg.toString());
      if (d is Map && d['event'] == 'open') {
        _ntfyCheck = '✅ Povezano ($base) — obavijesti dolaze dok je aplikacija otvorena ili u pozadini.';
      } else {
        _ntfyCheck = '⚠️ Neočekivani odgovor od ntfy-a.';
      }
      await ch.sink.close();
    } catch (_) {
      _ntfyCheck = '❌ Nema veze s $base. Provjerite NTFY_PUBLIC_URL i proxy (WebSocket mora biti dozvoljen).';
      try {
        await ch?.sink.close();
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _checkingNtfy = false);
    }
  }

  /// GitHub Releases check — the same channel CI publishes APKs to.
  Future<void> _checkForUpdates() async {
    setState(() {
      _updChecking = true;
      _updMessage = null;
      _updRelease = null;
    });
    final release = await Updater.latestRelease();
    if (!mounted) return;
    setState(() => _updChecking = false);
    if (release == null) {
      setState(() => _updMessage = 'Nije moguće provjeriti (GitHub nedostupan).');
      return;
    }
    if (Updater.isNewer(release.version, _appVersion)) {
      setState(() {
        _updRelease = release;
        _updMessage = 'Dostupna je novija verzija: ${release.version}';
      });
    } else {
      setState(() => _updMessage = 'Imate najnoviju verziju ($_appVersion).');
    }
  }

  Future<void> _downloadAndInstall() async {
    final release = _updRelease;
    if (release == null) return;
    setState(() {
      _updBusy = true;
      _updProgress = 0;
      _updMessage = 'Preuzimanje ${release.version}…';
    });
    try {
      final path = await Updater.downloadApk(release, onProgress: (p) {
        if (mounted) setState(() => _updProgress = p);
      });
      if (!mounted) return;
      setState(() => _updMessage = 'Pokretanje instalacije…');
      final size = await File(path).length();
      if (size < 1024 * 1024) {
        throw Exception('Preuzeta datoteka je neispravana (${(size / 1024).round()} kB).');
      }
      await Updater.install(path);
      if (mounted) setState(() => _updBusy = false);
      // If we get here the installer UI opened but the user returned —
      // keep the app running; the install completes outside.
    } catch (e) {
      if (mounted) {
        setState(() {
          _updBusy = false;
          _updMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _testNtfy() async {
    try {
      final d = await api.post('/api/me/ntfy/test', {}) as Map<String, dynamic>;
      if (!mounted) return;
      final ok = d['ok'] as bool? ?? false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Testna obavijest poslana — provjerite telefon.' : (d['reason'] as String? ?? 'Neuspjelo')),
      ));
    } catch (e) {
      _toast(e);
    }
  }

  // ---- admin: app settings --------------------------------------------------

  Future<void> _saveAppSettings() async {
    try {
      final columns = [
        for (final c in _columns.text.split(','))
          if (c.trim().isNotEmpty) c.trim(),
      ];
      await api.put('/api/settings', {
        'app_name': _appName.text.trim(),
        'default_columns': columns,
        'default_todo_list': _todoName.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Postavke spremljene.')));
      widget.onChanged();
    } catch (e) {
      _toast(e);
    }
  }

  // ---- admin: users ----------------------------------------------------------

  Future<void> _newUser() async {
    final username = TextEditingController();
    final display = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Novi korisnik'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: username, decoration: const InputDecoration(labelText: 'Korisničko ime')),
            const SizedBox(height: 8),
            TextField(controller: display, decoration: const InputDecoration(labelText: 'Puno ime')),
            const SizedBox(height: 8),
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Lozinka')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dodaj')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await api.post('/api/users', {
        'username': username.text.trim(),
        'display_name': display.text.trim(),
        'password': password.text,
      });
      await _loadUsers();
    } catch (e) {
      _toast(e);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Potvrda'),
        content: Text('Obrisati korisnika "${u['username']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Obriši'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await api.delete('/api/users/${u['id']}');
      await _loadUsers();
    } catch (e) {
      _toast(e);
    }
  }

  // ---- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Račun'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person, color: SR.accent),
            title: Text(me['display_name'] as String? ?? ''),
            subtitle: Text(
              '@${me['username']}${isAdmin ? ' · administrator' : ''}',
              style: const TextStyle(color: SR.muted, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await PushNotifications.unregister(api); // 1.12.0
                  await Api.clearSession();
                  navigator.pushReplacement(MaterialPageRoute(
                      builder: (_) => LoginScreen(baseUrl: api.baseUrl)));
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Odjava'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await Api.forgetServer();
                  navigator.pushReplacement(
                      MaterialPageRoute(builder: (_) => const OnboardingScreen()));
                },
                icon: const Icon(Icons.dns_outlined, size: 18),
                label: const Text('Poslužitelj'),
              ),
            ),
          ],
        ),

        _sectionTitle('Obavijesti na uređaju'),
        Card(
          child: SwitchListTile(
            value: _notifOn,
            onChanged: _toggleNotif,
            activeColor: SR.accent,
            title: const Text('Sistemske obavijesti'),
            subtitle: Text(
              _notifOn
                  ? 'Push na zaključani ekran kad vas netko tagira'
                  : (_notifPerm ? 'Isključeno' : 'Dozvola nije dodijeljena — uključite prekidač za upit'),
              style: const TextStyle(color: SR.muted, fontSize: 12),
            ),
          ),
        ),
        if (!_notifPerm)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton.icon(
              onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.notification),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Otvori sistemske postavke'),
            ),
          ),

        _sectionTitle('Obavijesti (ntfy)'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _topic,
                  decoration: const InputDecoration(labelText: 'Vaš ntfy topic'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(onPressed: _saveTopic, child: const Text('Spremi topic')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(onPressed: _testNtfy, child: const Text('Testiraj')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _checkingNtfy ? null : _checkNtfyConnection,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Provjeri vezu'),
                ),
                if (_ntfyCheck != null) ...[
                  const SizedBox(height: 8),
                  Text(_ntfyCheck!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),

        if (isAdmin) ...[
          _sectionTitle('Postavke aplikacije'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _appName,
                    decoration: const InputDecoration(labelText: 'Naziv aplikacije'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _columns,
                    decoration: const InputDecoration(
                      labelText: 'Zadane kolone (odvojene zarezom)',
                      hintText: 'Backlog, U tijeku, Gotovo',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _todoName,
                    decoration: const InputDecoration(
                      labelText: 'Naziv To-Do popisa za nabavu',
                      hintText: 'Nabava',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(onPressed: _saveAppSettings, child: const Text('Spremi postavke')),
                ],
              ),
            ),
          ),

          _sectionTitle('Korisnici'),
          for (final u in _users)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  u['is_admin'] as bool? ?? false ? Icons.admin_panel_settings : Icons.person_outline,
                  color: SR.accent,
                ),
                title: Text(u['display_name'] as String? ?? ''),
                subtitle: Text('@${u['username']}', style: const TextStyle(color: SR.muted, fontSize: 12)),
                trailing: (u['id'] == me['id'])
                    ? null
                    : IconButton(
                        tooltip: 'Obriši',
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 20),
                        onPressed: () => _deleteUser(u),
                      ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _newUser,
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('Novi korisnik'),
          ),
        ],

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        _updatesSection(),
        const SizedBox(height: 24),
      ],
    );
  }

  /// In-app updates: check GitHub Releases, download and install the APK.
  Widget _updatesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Ažuriranja'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.system_update_alt, color: SR.accent),
                    const SizedBox(width: 12),
                    Text('Trenutna verzija: $_appVersion'),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: (_updChecking || _updBusy) ? null : _checkForUpdates,
                  icon: _updChecking
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  label: const Text('Provjeri ažuriranja'),
                ),
                if (_updRelease != null && !_updBusy) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _downloadAndInstall,
                    icon: const Icon(Icons.download),
                    label: Text('Preuzmi i instaliraj ${_updRelease!.version}'),
                  ),
                ],
                if (_updBusy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _updProgress > 0 ? _updProgress : null),
                  const SizedBox(height: 4),
                  Text(
                    _updProgress > 0
                        ? '${(_updProgress * 100).round()}%'
                        : 'Spajanje…',
                    style: const TextStyle(color: SR.muted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_updMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(_updMessage!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t, style: const TextStyle(color: SR.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      );
}
