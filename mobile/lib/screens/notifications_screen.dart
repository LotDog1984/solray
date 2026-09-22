import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'board_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.api, this.onOpened});

  final Api api;
  final Future<void> Function()? onOpened;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.api.get('/api/notifications') as List<dynamic>;
      setState(() => _items = items);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _markRead(int id) async {
    await widget.api.patch('/api/notifications/$id/read', {});
    await _load();
    await widget.onOpened?.call();
  }

  Future<void> _markAll() async {
    await widget.api.patch('/api/notifications/read-all', {});
    await _load();
    await widget.onOpened?.call();
  }

  Future<void> _open(Map<String, dynamic> n) async {
    final boardId = n['board_id'];
    if (n['is_read'] != true && n['id'] != null) await _markRead(n['id'] as int);
    if (boardId is int && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BoardScreen(api: widget.api, boardId: boardId, boardName: 'Ploča'),
      ));
      await _load();
      await widget.onOpened?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    final unread = items.where((n) => n['is_read'] != true).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (unread > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton(
              onPressed: _markAll,
              child: Text('Označi sve kao pročitano ($unread)'),
            ),
          ),
        for (final raw in items)
          Builder(builder: (context) {
            final n = Map<String, dynamic>.from(raw as Map);
            final isUnread = n['is_read'] != true;
            final tappable = n['board_id'] != null;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SR.panelDeep,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isUnread ? SR.accent : SR.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: tappable ? () => _open(n) : null,
                    child: Text(n['message'] as String? ?? '',
                        style: TextStyle(fontWeight: isUnread ? FontWeight.w700 : FontWeight.w400)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(child: Text(_date(n['created_at']), style: const TextStyle(color: SR.muted, fontSize: 12))),
                      if (isUnread)
                        TextButton(onPressed: () => _markRead(n['id'] as int), child: const Text('Pročitano')),
                    ],
                  ),
                ],
              ),
            );
          }),
        if (items.isEmpty) const Center(child: Text('Nema obavijesti.', style: TextStyle(color: SR.muted))),
      ],
    );
  }

  String _date(dynamic iso) {
    try {
      final d = DateTime.parse(iso as String).toLocal();
      return '${d.day}.${d.month}.${d.year}. ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
