import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api.dart';
import '../theme.dart';
import 'board_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';

/// Main screen after login: layered navigation like the web app —
/// projects (sidebar layer) → boards → kanban. Bottom tab: Obavijesti.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, this.session});

  final Api api;
  final Session? session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Session? _session;
  bool _loading = true;
  String? _error;
  List<dynamic> _projects = [];
  WebSocketChannel? _socket;
  int _unread = 0;
  int _tab = 0; // 0 = Projekti, 1 = Obavijesti
  Timer? _unreadPoll;

  @override
  void initState() {
    super.initState();
    _boot();
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
      setState(() => _projects = projects);
    } on AuthExpired {
      if (mounted) _forceLogin();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
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
        // ntfy publishes message envelopes as JSON — any event bumps the badge
        // and refreshes; the board screen refreshes itself when resumed.
        try {
          jsonDecode(data as String);
        } catch (_) {
          return; // keepalives etc.
        }
        _refreshUnread();
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

  Future<void> _openBoard(Map<String, dynamic> board) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BoardScreen(api: widget.api, boardId: board['id'] as int, boardName: board['name'] as String),
    ));
    await _refreshUnread();
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
      _ProjectsTab(
        projects: _projects,
        appName: s.appName,
        username: (s.me['display_name'] as String?) ?? '',
        onOpenBoard: _openBoard,
        onRefresh: _refresh,
      ),
      NotificationsScreen(api: widget.api, onOpened: _refreshUnread),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? s.appName : 'Obavijesti'),
        actions: [
          IconButton(
            tooltip: 'Odjava',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await Api.clearSession();
              navigator.pushReplacement(MaterialPageRoute(
                builder: (_) => LoginScreen(baseUrl: widget.api.baseUrl),
              ));
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

class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab({
    required this.projects,
    required this.appName,
    required this.username,
    required this.onOpenBoard,
    required this.onRefresh,
  });

  final List<dynamic> projects;
  final String appName;
  final String username;
  final void Function(Map<String, dynamic>) onOpenBoard;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (username.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Prijavljen: $username', style: const TextStyle(color: SR.muted)),
          ),
        for (final p in projects)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              title: Text(p['name'] as String? ?? ''),
              iconColor: SR.accent,
              collapsedIconColor: SR.accent,
              children: [
                for (final b in (p['boards'] as List<dynamic>? ?? []))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.view_kanban_outlined, color: SR.accent),
                    title: Text(b['name'] as String? ?? ''),
                    onTap: () => onOpenBoard(Map<String, dynamic>.from(b as Map)),
                  ),
                if ((p['boards'] as List<dynamic>? ?? []).isEmpty)
                  const Text('Nema ploča', style: TextStyle(color: SR.muted)),
              ],
            ),
          ),
        if (projects.isEmpty) const Center(child: Text('Nema projekata.', style: TextStyle(color: SR.muted))),
      ],
    );
  }
}
