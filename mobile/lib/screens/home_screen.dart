import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api.dart';
import '../services/notifications.dart';
import '../services/push.dart';
import '../services/sync.dart';
import '../theme.dart';
import 'board_screen.dart';
import 'files_screen.dart';
import 'login_screen.dart';
import 'nabava_screen.dart';
import 'notifications_screen.dart';
import 'projects_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Main screen after login — web parity in five tabs:
/// Projekti (layered: projects → boards → kanban), Pretraga,
/// Datoteke (per project), Obavijesti with badge and Nabava
/// (global supplies To-Do aggregated over all boards).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, this.session, this.launchPayload});

  final Api api;
  final Session? session;
  final String? launchPayload; // notification tapped while app was closed

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Session? _session;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _projects = [];
  WebSocketChannel? _socket;
  int _socketRetry = 0;
  Timer? _reconnect;
  int _unread = 0;
  int _tab = 0; // 0 Projekti, 1 Pretraga, 2 Datoteke, 3 Obavijesti, 4 Nabava
  Timer? _unreadPoll;
  int _projectsTick = 0; // bumps when sync says projects changed

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 1.10.2: refresh on app resume
    _boot();
    Notifications.setTapHandler(_onNotificationTap);
    // 1.12.0: FCM tap handling — notification tapped while app was in
    // background (the cold-start path arrives via launchPayload, since the
    // background isolate posts through the same local-notification pipeline).
    PushNotifications.listenTaps((message) {
      final data = message.data;
      final boardId = int.tryParse(data['boardId'] ?? '');
      if (boardId != null) {
        _onNotificationTap('${data['boardId']}:${data['boardName'] ?? 'Ploča'}');
      } else {
        _onNotificationTap(null);
      }
    });
    if (widget.launchPayload != null) {
      // Cold start from a notification tap — open after boot.
      final payload = widget.launchPayload!;
      Future<void>.delayed(const Duration(milliseconds: 600), () => _onNotificationTap(payload));
    }
  }

  /// 1.12.0: initialize FCM (asks the Android 13+ permission once) and push
  /// the device token to the user's instance. Safe to call repeatedly.
  Future<void> _registerPush() async {
    try {
      await PushNotifications.init();
      await PushNotifications.registerWithBackend(widget.api);
      PushNotifications.listenForeground(widget.api);
    } catch (_) {
      // push is best-effort — ntfy/in-app notifications keep working
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

  /// 1.10.2: phone returns from background/sleep — reload the visible data
  /// immediately instead of waiting for the sync socket to notice.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reconnect the sync socket immediately (skip the up-to-5-min backoff)
      // and reload the visible data — the phone slept, so assume staleness.
      SyncBus.forApi(widget.api).poke();
      _refresh(silent: true);
      _refreshUnread();
      _registerPush(); // 1.12.0: re-register in case the FCM token rotated
    }
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
      // 1.10.2: the first projects fetch often races the phone waking its
      // network (empty list until a manual pull). Retry a few times before
      // giving up — only a total failure shows the retry screen.
      var loaded = false;
      for (var attempt = 0; attempt < 3 && !loaded; attempt++) {
        if (attempt > 0) await Future<void>.delayed(Duration(seconds: 2 * attempt));
        await _refresh(silent: true);
        loaded = _projects.isNotEmpty;
      }
      if (!loaded && _projects.isEmpty) {
        // Empty might be genuine (fresh server) — don't block the app on it;
        // the tab switch / tick / pull refreshes cover it from here on.
      }
      await _refreshUnread();
      _connectNotifications();
      _connectSync();
      await _maybeAskPermission();
      // 1.12.0: real device push (FCM). Best-effort — without a Firebase
      // config the app keeps the ntfy/in-app flow; with one, the token is
      // registered so the server can wake the phone even when the app is
      // killed. Re-registered on every resume in case it rotated while away.
      _registerPush();
      _unreadPoll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshUnread());
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// silent: no snackbar on failure — used for automatic refreshes (sync
  /// events, fallback tick, tab switch, app resume) so a transient error
  /// never spams the user; the next automatic attempt retries anyway.
  Future<void> _refresh({bool silent = false}) async {
    try {
      final projects = await widget.api.get('/api/projects') as List<dynamic>;
      setState(() => _projects =
          List<Map<String, dynamic>>.from(projects.map((p) => Map<String, dynamic>.from(p as Map))));
    } on AuthExpired {
      if (mounted) _forceLogin();
    } catch (e) {
      if (!silent && mounted) {
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
    if (socket == null) return; // no public ntfy on server — badge polling still works
    _socket = socket;
    socket.stream.listen(
      (data) {
        // ntfy envelope: JSON events. Only real messages ('event' absent or
        // 'message') become notifications; open/keepalive/error are ignored.
        String? title, body;
        try {
          final d = jsonDecode(data.toString());
          if (d is! Map) return; // plain keepalive text
          final event = d['event'] as String?;
          if (event != null && event != 'message') return;
          title = (d['title'] as String?) ?? 'SolRay';
          body = (d['message'] as String?) ?? '';
          if (event == null && body.isEmpty) return;
        } catch (_) {
          return; // keepalives etc.
        }
        _socketRetry = 0; // healthy again
        _refreshUnread();
        Notifications.show(title: title, body: body);
      },
      onError: (_) => _scheduleReconnect(),
      onDone: () => _scheduleReconnect(),
    );
  }

  /// Socket dropped (network change, server restart, sleep) — reconnect with
  /// a growing delay (5s → 5 min) so notifications keep flowing while open.
  void _scheduleReconnect() {
    _socketRetry++;
    final delaySec = (5 * (1 << (_socketRetry - 1))).clamp(5, 300);
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: delaySec), _connectNotifications);
  }

  /// Real-time sync: server pushes "something changed" events; the active
  /// tab reloads without any manual pull-to-refresh. Nabava tab reloads its
  /// own list; projects list refreshes on the projects layer. The sync bus
  /// also ticks every 20 s while its socket is down (slow-poll fallback).
  void _connectSync() {
    final bus = SyncBus.forApi(widget.api); // shared per-server singleton
    bus.listen('projects', (_) {
      if (!mounted) return;
      if (_tab == 0) _refresh(silent: true);
      if (_tab == 4) setState(() => _projectsTick++); // Nabava tab: reload via its own listener
    });
    bus.listen('nabava', (_) {
      if (!mounted || _tab != 4) return;
      setState(() => _projectsTick++); // rebuild → NabavaTab refetches in didUpdateWidget
    });
    // 1.10.2: listen to the 20 s fallback tick (fires while the sync socket
    // is down) — this is what was missing: with the socket asleep the
    // Projects tab never refreshed without a manual pull.
    bus.listen('tick', (_) {
      if (!mounted) return;
      if (_tab == 0) _refresh(silent: true);
      if (_tab == 4) setState(() => _projectsTick++); // Nabava refetches via its signal
    });
    // files events are handled inside FilesScreen (pushed route)
  }

  void _forceLogin() {
    PushNotifications.unregister(widget.api); // 1.12.0: remove push token
    Api.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LoginScreen(baseUrl: widget.api.baseUrl),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadPoll?.cancel();
    SyncBus.drop(widget.api.baseUrl); // leaving the app's main screen (logout/server change)
    _reconnect?.cancel();
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
    final todoName = (s.settings['default_todo_list'] as String?) ?? 'Nabava';
    final screens = [
      ProjectsScreen(api: widget.api, projects: _projects, appName: s.appName),
      SearchScreen(api: widget.api, onOpenNabava: () => setState(() => _tab = 4)),
      _FilesEntry(api: widget.api, projects: _projects),
      NotificationsScreen(api: widget.api, onOpened: _refreshUnread),
      NabavaTab(
        api: widget.api,
        onChanged: _refreshUnread,
        refreshSignal: _projectsTick,
      ),
    ];
    final titles = [s.appName, 'Pretraga', 'Datoteke', 'Obavijesti', todoName];

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
      // Nabava tab owns its RefreshIndicator (pull reloads its entries);
      // the others share the outer one.
      body: _tab == 4
          ? screens[_tab]
          : RefreshIndicator(
              onRefresh: _tab == 0 ? _refresh : _refreshUnread,
              child: screens[_tab],
            ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: SR.sidebar,
        indicatorColor: SR.accentDark,
        selectedIndex: _tab,
        // 1.10.2: opening a tab always shows fresh data — Projekti reloads
        // silently (fixes "stale after some time"), Nabava remounts and
        // loads itself.
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 0) _refresh(silent: true);
        },
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
          NavigationDestination(
            icon: const Icon(Icons.shopping_cart_outlined),
            label: todoName,
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
