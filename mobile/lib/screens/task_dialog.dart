import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// Create / edit a task — same fields as the web app modal: title,
/// description, assignee, column and a full checklist editor.
Future<void> showTaskDialog(
  BuildContext context, {
  required Api api,
  required List<ColumnRef> columns,
  required int initialColumnId,
  Map<String, dynamic>? task,
  required Future<void> Function() onSaved,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SR.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _TaskForm(
      api: api,
      columns: columns,
      initialColumnId: initialColumnId,
      task: task,
    ),
  );
  if (saved == true) await onSaved();
}

class ColumnRef {
  ColumnRef({required this.id, required this.name, this.position = 0});
  final int id;
  final String name;
  final int position;

  factory ColumnRef.from(Map<String, dynamic> j) => ColumnRef(
      id: j['id'] as int, name: j['name'] as String? ?? '', position: (j['position'] as num?)?.toInt() ?? 0);
}

class _ItemDraft {
  _ItemDraft({this.id, required this.title, this.done = false});
  final int? id;
  String title;
  bool done;
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({
    required this.api,
    required this.columns,
    required this.initialColumnId,
    this.task,
  });

  final Api api;
  final List<ColumnRef> columns;
  final int initialColumnId;
  final Map<String, dynamic>? task;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  late final TextEditingController _title =
      TextEditingController(text: widget.task?['title'] as String? ?? '');
  late final TextEditingController _desc =
      TextEditingController(text: widget.task?['description'] as String? ?? '');
  late int _columnId;
  int? _assigneeId;
  late final List<_ItemDraft> _items = [
    for (final raw in (widget.task?['items'] as List<dynamic>? ?? []))
      _ItemDraft(
        id: raw['id'] as int?,
        title: raw['title'] as String? ?? '',
        done: raw['is_done'] as bool? ?? false,
      ),
  ];
  List<Map<String, dynamic>> _users = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _columnId = widget.initialColumnId;
    _assigneeId = widget.task?['assignee_id'] as int?;
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await widget.api.get('/api/users') as List<dynamic>;
      if (mounted) {
        setState(
            () => _users = List<Map<String, dynamic>>.from(users.map((u) => Map<String, dynamic>.from(u as Map))));
      }
    } catch (_) {
      // assignee picker stays empty — non-fatal
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final existing = widget.task;
    final itemsJson = [
      for (final i in _items.where((i) => i.title.trim().isNotEmpty))
        {'id': i.id, 'title': i.title.trim(), 'is_done': i.done},
    ];
    try {
      if (existing == null) {
        await widget.api.post('/api/tasks', {
          'column_id': _columnId,
          'title': _title.text.trim(),
          'description': _desc.text,
          'assignee_id': _assigneeId,
          'items': itemsJson,
        });
      } else {
        await widget.api.patch('/api/tasks/${existing['id']}', {
          'column_id': _columnId,
          'title': _title.text.trim(),
          'description': _desc.text,
          'assignee_id': _assigneeId,
          'items': itemsJson,
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.task == null ? 'Novi task' : 'Uredi task',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop(false)),
                  ],
                ),
              ),
              const Divider(color: SR.line, height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _title,
                      autofocus: widget.task == null,
                      decoration: const InputDecoration(labelText: 'Naslov'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _desc,
                      decoration: const InputDecoration(labelText: 'Opis', hintText: '@netko za oznaku...'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _columnId,
                      decoration: const InputDecoration(labelText: 'Kolona'),
                      items: [
                        for (final c in widget.columns)
                          DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(color: SR.text))),
                      ],
                      onChanged: (v) => setState(() => _columnId = v ?? _columnId),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      value: _assigneeId,
                      decoration: const InputDecoration(labelText: 'Izvršitelj'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—', style: TextStyle(color: SR.text))),
                        for (final u in _users)
                          DropdownMenuItem(
                              value: u['id'] as int,
                              child: Text(u['display_name'] as String? ?? '', style: const TextStyle(color: SR.text))),
                      ],
                      onChanged: (v) => setState(() => _assigneeId = v),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Text('Popis zadataka', style: TextStyle(fontWeight: FontWeight.w600))),
                        IconButton(
                          tooltip: 'Dodaj stavku',
                          icon: const Icon(Icons.add, color: SR.accent),
                          onPressed: () => setState(() => _items.add(_ItemDraft(title: ''))),
                        ),
                      ],
                    ),
                    for (var i = 0; i < _items.length; i++)
                      Row(
                        key: ValueKey('item-$i-${_items[i].id}'),
                        children: [
                          Checkbox(
                            value: _items[i].done,
                            activeColor: SR.done,
                            onChanged: (v) => setState(() => _items[i].done = v ?? false),
                          ),
                          Expanded(
                            child: TextFormField(
                              initialValue: _items[i].title,
                              decoration: const InputDecoration(hintText: 'Stavka...'),
                              onChanged: (t) => _items[i].title = t,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: SR.muted),
                            onPressed: () => setState(() => _items.removeAt(i)),
                          ),
                        ],
                      ),
                    if (widget.task != null && (widget.task!['items'] as List<dynamic>? ?? []).isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Kad su sve stavke označene, task se automatski završava.',
                            style: TextStyle(color: SR.muted, fontSize: 12)),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Spremi'),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
