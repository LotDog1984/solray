import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../api.dart';

/// Real-time sync with the server's WebSocket hub (`/api/ws?token=JWT`).
///
/// The backend broadcasts lightweight "something changed" events (NO data —
/// clients re-fetch via REST, permissions untouched):
///   {"type": "projects" | "board" | "files" | "nabava", "board_id": int?, ...}
///
/// Subscribers register per-scope callbacks (e.g. the open board id, the
/// global "always interested" scope). A dropped socket reconnects with
/// exponential backoff (5s → 5min, same strategy as the ntfy socket); while
/// disconnected, listeners also receive periodic tick()s so screens fall back
/// to a slow poll and never go stale.
class SyncBus {
  /// One shared bus per server (keyed by base URL) — screens subscribe via
  /// `SyncBus.forApi(widget.api)` without threading the bus through
  /// constructors, and all share a single WebSocket connection.
  static final Map<String, SyncBus> _instances = {};

  factory SyncBus.forApi(Api api) {
    return _instances.putIfAbsent(api.baseUrl, () => SyncBus._(api));
  }

  /// Dispose the shared bus for [baseUrl] (logout / server change) and remove
  /// it so the next session starts a fresh connection.
  static void drop(String baseUrl) {
    _instances.remove(baseUrl)?.dispose();
  }

  SyncBus._(this.api);

  final Api api;
  WebSocketChannel? _socket;
  Timer? _reconnect;
  Timer? _poll;
  int _retry = 0;
  bool _closed = false;

  final Map<String, void Function(SyncEvent)> _listeners = {};
  int _nextListener = 0;

  static const _pollInterval = Duration(seconds: 20);

  /// Subscribe to sync events. [scope] routes events: 'board:12' receives
  /// board events for board 12 AND global events ('projects', 'nabava',
  /// 'files'); '*' receives everything. Returns a cancel function.
  void Function() listen(String scope, void Function(SyncEvent e) fn) {
    final key = '$_nextListener';
    _nextListener++;
    _listeners[key] = (e) {
      if (scope == '*' || e.scope == '*' || scope == e.scope) fn(e);
    };
    _ensureConnected();
    return () => _listeners.remove(key);
  }

  /// Force a connect attempt now (e.g. app resumed from background).
  void poke() => _ensureConnected();

  void _ensureConnected() {
    if (_closed || _socket != null || api.token == null) {
      // Even without a socket, keep the fallback poll alive for listeners.
      _ensurePoll();
      return;
    }
    final base = api.baseUrl.replaceFirst(RegExp('^http'), 'ws');
    try {
      final ws = WebSocketChannel.connect(
        Uri.parse('$base/api/ws?token=${Uri.encodeComponent(api.token!)}'),
      );
      _socket = ws;
      // Errors before 'ready' also surface through stream; errors after a
      // healthy connection arrive here too (network drop, server restart).
      ws.stream.listen(
        (data) {
          _retry = 0; // healthy
          SyncEvent? e;
          try {
            final d = jsonDecode(data.toString());
            if (d is Map) {
              e = SyncEvent(
                type: (d['type'] as String?) ?? '',
                boardId: (d['board_id'] as num?)?.toInt(),
              );
            }
          } catch (_) {
            return; // non-JSON keepalive
          }
          if (e != null) _dispatch(e);
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
      );
    } catch (_) {
      _socket = null;
      _scheduleReconnect();
    }
    _ensurePoll();
  }

  void _ensurePoll() {
    if (_poll != null || _listeners.isEmpty) return;
    _poll = Timer.periodic(_pollInterval, (_) {
      if (_socket == null) _dispatch(const SyncEvent(type: 'tick', global: true));
    });
  }

  void _scheduleReconnect() {
    _socket = null;
    if (_closed) return;
    _retry++;
    final delaySec = (5 * (1 << (_retry - 1))).clamp(5, 300);
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: delaySec), _ensureConnected);
  }

  void _dispatch(SyncEvent e) {
    if (_listeners.isEmpty) return;
    for (final fn in List.of(_listeners.values)) {
      try {
        fn(e);
      } catch (_) {
        // a broken listener must not kill the others
      }
    }
  }

  void dispose() {
    _closed = true;
    _reconnect?.cancel();
    _poll?.cancel();
    _listeners.clear();
    _socket?.sink.close();
    _socket = null;
  }
}

/// One change notification from the server (or a local fallback tick).
class SyncEvent {
  const SyncEvent({required this.type, this.boardId, this.global = false});

  final String type; // projects | board | files | nabava | tick
  final int? boardId;
  final bool global; // tick events fan out to every listener

  /// Routing key listeners subscribe to: 'board:12', 'projects', 'nabava',
  /// 'files:3' (project 3), or 'tick'.
  String get scope {
    switch (type) {
      case 'board':
        return 'board:$boardId';
      case 'files':
        return 'files:$boardId'; // board_id carries the project id here
      default:
        return type; // projects | nabava | tick
    }
  }
}
