import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api.dart';
import '../services/notifications.dart';
import '../theme.dart';
import 'board_screen.dart';
import 'files_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'projects_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Main screen after login — web parity in four tabs:
/// Projekti (layered: projects → boards → kanban), Pretraga,
/// Datoteke (per project) and Obavijesti with badge.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, this.session, this.launchPayload});

  final Api api;
  final Session? session;
  final String? launchPayload; // notification tapped while app was closed

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Session? _session;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _projects = [];
  WebSocketChannel? _socket;
  int _unread = 0;
  int _tab = 0; // 0 Projekti, 1 Pretraga, 2 Datoteke, 3 Obavijesti
  Timer? _unreadPoll;

  @override
  void initState() {
    super.initState();
    _boot();
    Notifications.setTapHandler(_onNotificationTap);
    if (widget.launchPayload != null) {
      // Cold start from a notification tap — open after boot.
      final payload = widget.launchPayload!;
      Future<void>.delayed(const Duration(milliseconds: 600), () => _onNotificationTap(payload));
    }
  }

  /// Ask for the Android notification permission shortly after first login
  /// (system dialog; can be re-enabled later in Postavke or system settings).
  Future<void> _maybeAskPermission() async {
    try {
      if (await Notifications.askedOnce()) return;
      final granted = await Notifications.requestPermission();
      if (!granted) {
        // Store the preference anyway; Postavke shows how to re-enable.
      }
    } catch (_) {
      // permission flow is best-effort
    }
  }

  void _onNotificationTap(String? payload) {
    // payload format "boardId:boardName" when available; otherwise open Obavijesti.
    if (payload != null && payload.contains(':')) {
      final idx = payload.indexOf(':');
      final id = int.tryParse(payload.substring(0, idx));
      final name = payload.substring(idx + 1);
      if (id != null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BoardScreen(api: widget.api, boardId: id, boardName: name, projects: _projects),
        ));
        return;
      }
    }
    if (mounted) setState(() => _tab = 3); // Obavijesti
  }

  Future<void> _boot() async {
    try {
      final session = widget.session ??
          Session(
            api: widget.api,
            me: await widget.api.get('/api/me') as Map<String, dynamic>,
            settings: await widget.api.settings(),
          );
      setState(() {
        _session = session;
        _loading = false;
      });
      await _refresh();
      await _refreshUnread();
      _connectNotifications();
      await _maybeAskPermission();
      _unreadPoll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshUnread());
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final projects = await widget.api.get('/api/projects') as List<dynamic>;
      setState(() => _projects =
          List<Map<String, dynamic>>.from(projects.map((p) => Map<String, dynamic>.from(p as Map))));
    } on AuthExpired {
      if (mounted) _forceLogin();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _refreshUnread() async {
    try {
      final d = await widget.api.get('/api/notifications/unread-count') as Map<String, dynamic>;
      if (mounted) setState(() => _unread = (d['count'] as num?)?.toInt() ?? 0);
    } catch (_) {
      // badge is best-effort; the socket + poll cover it
    }
  }

  void _connectNotifications() {
    final s = _session;
    if (s == null) return;
    final socket = s.api.notificationSocket(s.ntfyBase, s.topic);
    if (socket == null) return;
    _socket = socket;
    socket.stream.listen(
      (data) {
        // ntfy message envelope: JSON with title/message — post a system
        // notification and bump the badge. Keepalives are plain text.
        String? title, body;
        try {
          final d = jsonDecode(data as String);
          if (d is Map) {
            title = (d['title'] as String?) ?? 'SolRay';
            body = (d['message'] as String?) ?? '';
          }
        } catch (_) {
          return; // keepalives etc.
        }
        _refreshUnread();
        Notifications.show(title: title ?? 'SolRay', body: body ?? '');
      },
      onError: (_) {},
      onDone: () {},
    );
  }

  void _forceLogin() {
    Api.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LoginScreen(baseUrl: widget.api.baseUrl),
    ));
  }

  @override
  void dispose() {
    _unreadPoll?.cancel();
    _socket?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _boot, child: const Text('Pokušaj ponovno')),
              ],
            ),
          ),
        ),
      );
    }
    final s = _session!;
    final screens = [
      ProjectsScreen(api: widget.api, projects: _projects, appName: s.appName),
      SearchScreen(api: widget.api),
      _FilesEntry(api: widget.api, projects: _projects),
      NotificationsScreen(api: widget.api, onOpened: _refreshUnread),
    ];
    final titles = [s.appName, 'Pretraga', 'Datoteke', 'Obavijesti'];

    return Scaffold(
      backgroundColor: SR.bg,
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Postavke',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsScreen(session: s, onChanged: _boot),
              ));
              if (mounted) setState(() {}); // reflect edits (app name, topic)
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _tab == 0 ? _refresh : _refreshUnread,
        child: screens[_tab],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: SR.sidebar,
        indicatorColor: SR.accentDark,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Projekti'),
          const NavigationDestination(icon: Icon(Icons.search), label: 'Pretraga'),
          const NavigationDestination(icon: Icon(Icons.folder_zip_outlined), label: 'Datoteke'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text('$_unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            label: 'Obavijesti',
          ),
        ],
      ),
    );
  }
}

/// Files tab needs a project choice — show a picker over all projects.
class _FilesEntry extends StatelessWidget {
  const _FilesEntry({required this.api, required this.projects});

  final Api api;
  final List<Map<String, dynamic>> projects;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return const Center(child: Text('Nema projekata.', style: TextStyle(color: SR.muted)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Odaberite projekt za njegove datoteke:', style: TextStyle(color: SR.muted)),
        ),
        for (final p in projects)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.folder_outlined, color: SR.accent),
              title: Text(p['name'] as String? ?? ''),
              trailing: const Icon(Icons.chevron_right, color: SR.muted),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FilesScreen(
                  api: api,
                  projectId: p['id'] as int,
                  projectName: p['name'] as String? ?? '',
                ),
              )),
            ),
          ),
      ],
    );
  }
}
