import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// One board — horizontal kanban like the web app. Read-mostly with the
/// essential actions: tick checklist items, complete/reopen, drag is not
/// needed on mobile (column move via card menu kept simple: complete only).
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.api, required this.boardId, required this.boardName});

  final Api api;
  final int boardId;
  final String boardName;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  Map<String, dynamic>? _board;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final b = await widget.api.get('/api/boards/${widget.boardId}') as Map<String, dynamic>;
      setState(() {
        _board = b;
        _loading = false;
      });
    } on AuthExpired {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sesija je istekla — prijavite se ponovno.')));
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _toggleItem(Map<String, dynamic> task, Map<String, dynamic> item) async {
    final next = !(item['is_done'] as bool? ?? false);
    await widget.api.patch('/api/tasks/${task['id']}/items/${item['id']}',
        {'title': item['title'], 'is_done': next});
    await _load();
  }

  Future<void> _toggleComplete(Map<String, dynamic> task) async {
    try {
      await widget.api.patch('/api/tasks/${task['id']}/completed', {});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = (_board?['columns'] as List<dynamic>? ?? []);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.boardName),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final col in columns)
                        _ColumnView(
                          name: col['name'] as String? ?? '',
                          tasks: List<Map<String, dynamic>>.from(
                              (col['tasks'] as List<dynamic>? ?? []).map((t) => Map<String, dynamic>.from(t as Map))),
                          onToggleItem: _toggleItem,
                          onToggleComplete: _toggleComplete,
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _ColumnView extends StatelessWidget {
  const _ColumnView({
    required this.name,
    required this.tasks,
    required this.onToggleItem,
    required this.onToggleComplete,
  });

  final String name;
  final List<Map<String, dynamic>> tasks;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>) onToggleItem;
  final Future<void> Function(Map<String, dynamic>) onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final open = tasks.where((t) => !(t['completed'] as bool? ?? false)).toList();
    final done = tasks.where((t) => t['completed'] as bool? ?? false).toList();
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SR.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SR.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (final t in open) _TaskCard(task: t, onToggleItem: onToggleItem, onToggleComplete: onToggleComplete),
                for (final t in done) _TaskCard(task: t, onToggleItem: onToggleItem, onToggleComplete: onToggleComplete),
                if (tasks.isEmpty) const Text('—', textAlign: TextAlign.center, style: TextStyle(color: SR.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onToggleItem, required this.onToggleComplete});

  final Map<String, dynamic> task;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>) onToggleItem;
  final Future<void> Function(Map<String, dynamic>) onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final completed = task['completed'] as bool? ?? false;
    final mentioned = task['mentions_me'] as bool? ?? false;
    final items = List<Map<String, dynamic>>.from((task['items'] as List<dynamic>? ?? []).map((i) => Map<String, dynamic>.from(i as Map)));
    final doneCount = items.where((i) => i['is_done'] as bool? ?? false).length;

    Color? cardColor;
    if (completed) {
      cardColor = const Color(0x1F22C55E); // green tint
    } else if (mentioned) {
      cardColor = const Color(0x1FF59E0B); // orange tint = tagged me
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardColor ?? SR.panelDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: completed ? SR.done : (mentioned ? SR.mention : SR.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: completed,
                onChanged: items.isEmpty ? (_) => onToggleComplete(task) : null, // all-checked rule
                activeColor: SR.done,
              ),
              Expanded(
                child: Text(
                  task['title'] as String? ?? '',
                  style: TextStyle(
                    decoration: completed ? TextDecoration.lineThrough : null,
                    color: completed ? SR.done : SR.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if ((task['description'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(task['description'] as String, style: const TextStyle(color: SR.muted, fontSize: 12)),
            ),
          if ((task['assignee'] as String?) != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text('👤 ${task['assignee']}', style: const TextStyle(color: SR.muted, fontSize: 12)),
            ),
          if (items.isNotEmpty) ...[
            Text('$doneCount/${items.length} stavki',
                style: TextStyle(color: completed ? SR.done : SR.accent, fontSize: 12)),
            for (final item in items)
              InkWell(
                onTap: () => onToggleItem(task, item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        (item['is_done'] as bool? ?? false) ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 18,
                        color: (item['is_done'] as bool? ?? false) ? SR.done : SR.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['title'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: (item['is_done'] as bool? ?? false) ? SR.done : SR.text,
                            decoration: (item['is_done'] as bool? ?? false) ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
