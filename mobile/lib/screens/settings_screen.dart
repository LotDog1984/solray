import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../services/notifications.dart';
import '../services/push.dart';
import '../services/updater.dart';
import '../theme.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Postavke — everything the web app offers:
/// account (logout, change server), device notifications (system switch,
/// Google push test, in-app updates) and, for admins, the app settings:
/// name, default columns (editable chip list, 1.18.0), the Nabava To-Do list
/// name, the Nabava group and the user list.
///
/// 1.18.0: the old ntfy-topic editor is gone — Google push (FCM) and web push
/// cover both clients, so the topic field was noise. The stored topic keeps
/// working server-side; only the editor was removed.
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

  late final TextEditingController _appName =
      TextEditingController(text: widget.session.appName);
  late final TextEditingController _todoName = TextEditingController(
      text: (widget.session.settings['default_todo_list'] as String?) ?? 'Nabava');

  /// 1.17.0: „Nabava grupa" — the users who receive the „🔔 Pošalji obavijest"
  /// notify (web parity: Postavke → Nabava grupa). Loaded from settings and
  /// edited member-by-member, saving after every add/remove like the web does.
  late List<int> _nabavaGroup = [
    for (final id in (widget.session.settings['nabava_group'] as List<dynamic>? ?? []))
      (id as num).toInt(),
  ];
  bool _savingGroup = false;

  /// 1.18.0: the default columns are edited as a list of chips (one text field
  /// per column, add/remove buttons) — the old comma-separated field was the
  /// last "old school" part of Postavke.
  late final List<TextEditingController> _columnCtrls = [
    for (final c in (widget.session.settings['default_columns'] as List<dynamic>? ?? []))
      TextEditingController(text: c.toString()),
  ];

  bool _testingPush = false; // 1.12.2: Google push diagnostic
  String? _pushCheck;

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
    }).catchError((_) {
      // No package-info plugin (tests, unsupported platform): keep the
      // placeholder instead of surfacing an unhandled error.
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

  @override
  void dispose() {
    _appName.dispose();
    _todoName.dispose();
    for (final c in _columnCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- admin: default column chips (1.18.0) ----------------------------------

  void _addColumn() {
    if (_columnCtrls.length >= 20) {
      _toast(Exception('Najviše 20 kolona.'));
      return;
    }
    setState(() => _columnCtrls.add(TextEditingController()));
  }

  void _removeColumn(int index) {
    final gone = _columnCtrls[index];
    setState(() => _columnCtrls.removeAt(index));
    // Dispose after the frame that detaches the field (disposing earlier
    // would tear the controller out from under a still-mounted TextField).
    WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
  }

  /// The names actually saved: trimmed, blanks dropped (same rule as the API).
  List<String> get _columnNames => [
        for (final c in _columnCtrls)
          if (c.text.trim().isNotEmpty) c.text.trim(),
      ];

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

  /// 1.12.2: end-to-end Google push test — asks the server to send a real
  /// FCM message to THIS account's registered device and shows the exact
  /// result (not configured / not registered / sent / Google's error).
  /// 1.13.2: the button re-runs the FULL init (permission + token fetch +
  /// backend registration) instead of relying on a token fetched at app
  /// boot — a phone that missed its registration at boot heals here.
  Future<void> _testPush() async {
    setState(() {
      _testingPush = true;
      _pushCheck = null;
    });
    try {
      // Make sure registration is fresh before judging the pipeline.
      await PushNotifications.init();
      await PushNotifications.registerWithBackend(api);
      final d = await api.post('/api/me/push/test', {}) as Map<String, dynamic>;
      final reason = d['reason'] as String? ?? '';
      if (d['ok'] == true) {
        setState(() => _pushCheck = '✅ $reason');
      } else {
        setState(() => _pushCheck = '⚠️ $reason');
      }
    } catch (e) {
      setState(() => _pushCheck =
          '❌ Server nije odgovorio ($e). Stari backend bez 1.12.2 ili mreža?');
    } finally {
      if (mounted) setState(() => _testingPush = false);
    }
  }

  /// GitHub Releases check — the same channel CI publishes APKs to.
  Future<void> _checkForUpdates() async {
    setState(() {
      _updChecking = true;
      _updMessage = null;
      _updRelease = null;
    });
    String? lastError;
    final release = await Updater.latestRelease(lastError: (reason) => lastError = reason);
    if (!mounted) return;
    setState(() => _updChecking = false);
    if (release == null) {
      // 1.13.2: say WHY the check failed (rate limit / no network / no
      // release) instead of a bare "GitHub nedostupan".
      setState(() => _updMessage = lastError ?? 'Nije moguće provjeriti (GitHub nedostupan).');
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

  // ---- admin: app settings --------------------------------------------------

  Future<void> _saveAppSettings() async {
    if (_columnNames.isEmpty) {
      _toast(Exception('Potrebna je barem jedna kolona.'));
      return;
    }
    try {
      await api.put('/api/settings', {
        'app_name': _appName.text.trim(),
        'default_columns': _columnNames,
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

  // ---- admin: Nabava grupa (1.17.0, web parity) -------------------------------

  /// Members of the group, resolved to user records (unknown ids are dropped —
  /// the backend already filters deleted users out on save).
  List<Map<String, dynamic>> get _groupMembers => [
        for (final u in _users)
          if (_nabavaGroup.contains((u['id'] as num?)?.toInt())) u,
      ];

  Future<void> _addToNabavaGroup() async {
    final members = _nabavaGroup.toSet();
    final candidates = _users
        .where((u) => !members.contains((u['id'] as num?)?.toInt()))
        .toList();
    if (candidates.isEmpty) {
      _toast(Exception(_users.isEmpty
          ? 'Nema dostupnih korisnika — dodajte ih u odjeljku Korisnici.'
          : 'Svi su korisnici već u Nabava grupi.'));
      return;
    }
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Dodaj u Nabava grupu'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final u in candidates)
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1, color: SR.accent),
                  title: Text(u['display_name'] as String? ?? ''),
                  subtitle: Text('@${u['username']}',
                      style: const TextStyle(color: SR.muted, fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, (u['id'] as num).toInt()),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Odustani')),
        ],
      ),
    );
    if (picked == null) return;
    await _saveNabavaGroup([..._nabavaGroup, picked]);
  }

  Future<void> _removeFromNabavaGroup(int id) =>
      _saveNabavaGroup([for (final x in _nabavaGroup) if (x != id) x]);

  /// The web app PUTs the app name together with the group on every change
  /// (the field is required by the API), so mirror that with the SAVED app
  /// name — not with whatever is currently typed in the form above.
  Future<void> _saveNabavaGroup(List<int> ids) async {
    setState(() => _savingGroup = true);
    try {
      final settings = await api.put('/api/settings', {
        'app_name': widget.session.appName,
        'nabava_group': ids,
      }) as Map<String, dynamic>;
      final saved = [
        for (final id in (settings['nabava_group'] as List<dynamic>? ?? []))
          (id as num).toInt(),
      ];
      if (!mounted) return;
      setState(() => _nabavaGroup = saved);
      widget.onChanged();
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _savingGroup = false);
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
    // 1.17.0: the screen is pushed as a full route, so it needs its own
    // Scaffold — without one it rendered as a bare (background-less) list with
    // no title, no back button, and every SnackBar ("Postavke spremljene.")
    // landed on the Home screen's Scaffold *behind* this page, invisible.
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Postavke')),
      body: _body(),
    );
  }

  Widget _body() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Račun', icon: '👤'),
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

        _sectionTitle('Obavijesti na uređaju', icon: '🔔'),
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

        // 1.12.2: end-to-end Google push diagnostic — one tap, exact answer.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    onPressed: _testingPush ? null : _testPush,
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('Testiraj Google push'),
                  ),
                  if (_pushCheck != null) ...[
                    const SizedBox(height: 8),
                    Text(_pushCheck!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ),

        if (isAdmin) ...[
          _sectionTitle('Postavke aplikacije', icon: '⚙️'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _appName,
                    decoration: const InputDecoration(
                      labelText: 'Naziv aplikacije',
                      helperText: 'Prikazuje se na prijavi i u vrhu aplikacije.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _todoName,
                    decoration: const InputDecoration(
                      labelText: 'Naziv To-Do popisa za nabavu',
                      hintText: 'Nabava',
                      helperText: 'To-Do popis na svakoj ploči i gumb u donjoj traci.',
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 1.18.0: „Zadane kolone" as an editable chip list (was one
          // comma-separated field) — the same editor the web app now has.
          _sectionTitle('Zadane kolone novih ploča', icon: '▦'),
          Card(
            key: const ValueKey('columnEditorCard'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _columnCtrls.length >= 20 ? null : _addColumn,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Dodaj novu kolonu'),
                  ),
                  const SizedBox(height: 12),
                  if (_columnCtrls.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Još nema kolona — dodajte prvu.',
                        style: TextStyle(color: SR.muted, fontSize: 12),
                      ),
                    )
                  else
                    for (var i = 0; i < _columnCtrls.length; i++) _columnRow(i, _columnCtrls[i]),
                  Text(
                    'Najviše 20 kolona · naziv do 80 znakova · ${_columnCtrls.length} / 20',
                    style: const TextStyle(color: SR.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _saveAppSettings,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Spremi postavke'),
          ),

          // 1.17.0: „Nabava grupa" — recipients of the „Pošalji obavijest"
          // notify. Web parity: Postavke → Nabava grupa.
          _sectionTitle('Nabava grupa', icon: '🛒'),
          Card(
            key: const ValueKey('nabavaGroupCard'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Korisnici koji primaju obavijest „Dodane nove stvari za nabavu" kad netko klikne '
                    '„🔔 Pošalji obavijest" na Nabava popisu ili To-Do panelu ploče.',
                    style: TextStyle(color: SR.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  if (_groupMembers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Grupa je prazna — nitko neće primiti obavijest dok ne dodate korisnike.',
                        style: TextStyle(color: SR.muted, fontSize: 12),
                      ),
                    )
                  else
                    for (final u in _groupMembers)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.shopping_cart_outlined, color: SR.accent),
                        title: Text(u['display_name'] as String? ?? ''),
                        subtitle: Text(
                          '@${u['username']}${u['id'] == me['id'] ? ' · to ste vi' : ''}',
                          style: const TextStyle(color: SR.muted, fontSize: 12),
                        ),
                        trailing: IconButton(
                          tooltip: 'Ukloni iz grupe',
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Color(0xFFDC2626), size: 20),
                          onPressed: _savingGroup
                              ? null
                              : () => _removeFromNabavaGroup((u['id'] as num).toInt()),
                        ),
                      ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: (_savingGroup || _users.isEmpty) ? null : _addToNabavaGroup,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Dodaj u grupu'),
                  ),
                ],
              ),
            ),
          ),

          _sectionTitle('Korisnici', icon: '👥'),
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
        _sectionTitle('Ažuriranja', icon: '⬆️'),
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

  /// One editable column: index, name field, remove button (1.18.0).
  Widget _columnRow(int index, TextEditingController ctrl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 4, right: 2),
      decoration: BoxDecoration(
        color: SR.panelDeep,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SR.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: SR.muted, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Naziv kolone',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ukloni kolonu',
            icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFDC2626), size: 20),
            onPressed: _columnCtrls.length <= 1 ? null : () => _removeColumn(index),
          ),
        ],
      ),
    );
  }

  /// Section header: emoji badge + label (1.18.0 — matches the web grid).
  Widget _sectionTitle(String t, {String? icon}) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
            ],
            Text(
              t,
              style: const TextStyle(color: SR.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
          ],
        ),
      );
}
