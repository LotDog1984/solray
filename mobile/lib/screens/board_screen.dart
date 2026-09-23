import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'search_screen.dart';
import 'task_dialog.dart';

/// One board — horizontal kanban with the full feature set of the web app:
/// create/edit/delete tasks (with checklist), add/rename/delete columns,
/// move tasks between columns, board rename/delete, search.
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.api,
    required this.boardId,
    required this.boardName,
    this.projects = const [],
  });

  final Api api;
  final int boardId;
  final String boardName;
  final List<Map<String, dynamic>> projects; // for board move/delete dialogs

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
      if (mounted) _popExpired();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _popExpired() {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesija je istekla — prijavite se ponovno.')));
  }

  List<ColumnRef> get _columnRefs => [
        for (final c in (_board?['columns'] as List<dynamic>? ?? []))
          ColumnRef.from(Map<String, dynamic>.from(c as Map)),
      ];

  Future<bool> _confirm(String message) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Potvrda'),
        content: Text(message),
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
    return res == true;
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  // ---- board actions -------------------------------------------------------

  Future<void> _editBoard() async {
    final nameCtrl = TextEditingController(text: widget.boardName);
    int? projectId = _board?['project_id'] as int?;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: SR.panel,
          title: const Text('Uredi ploču'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Naziv ploče')),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: projectId,
                decoration: const InputDecoration(labelText: 'Projekt'),
                items: [
                  for (final p in widget.projects)
                    DropdownMenuItem(
                        value: p['id'] as int,
                        child: Text(p['name'] as String? ?? '', style: const TextStyle(color: SR.text))),
                ],
                onChanged: (v) => setDialog(() => projectId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Obriši ploču', style: TextStyle(color: Color(0xFFDC2626))),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Spremi')),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'delete') {
      if (!await _confirm('Obrisati ploču "${widget.boardName}" sa svim kolonama i taskovima?')) return;
      try {
        await widget.api.delete('/api/boards/${widget.boardId}');
        if (!mounted) return;
        Navigator.of(context).pop(); // back to boards list
      } catch (e) {
        _showError(e);
      }
      return;
    }
    if (action != 'save') return;
    try {
      await widget.api.patch('/api/boards/${widget.boardId}',
          {'name': nameCtrl.text.trim(), 'project_id': projectId});
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  // ---- column actions ------------------------------------------------------

  Future<void> _addColumn() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Nova kolona'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Naziv kolone'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dodaj')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final cols = _columnRefs;
      await widget.api.post('/api/columns', {
        'board_id': widget.boardId,
        'name': ctrl.text.trim(),
        'position': cols.length,
      });
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _renameColumn(Map<String, dynamic> col) async {
    final ctrl = TextEditingController(text: col['name'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Preimenuj kolonu'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Spremi')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.patch('/api/columns/${col['id']}', {'name': ctrl.text.trim()});
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _deleteColumn(Map<String, dynamic> col) async {
    if (!await _confirm('Obrisati kolonu "${col['name']}" sa svim taskovima?')) return;
    try {
      await widget.api.delete('/api/columns/${col['id']}');
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  // ---- task actions --------------------------------------------------------

  Future<void> _newTask(Map<String, dynamic> col) async {
    await showTaskDialog(
      context,
      api: widget.api,
      columns: _columnRefs,
      initialColumnId: col['id'] as int,
      onSaved: _load,
    );
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    await showTaskDialog(
      context,
      api: widget.api,
      columns: _columnRefs,
      initialColumnId: _columnIdOfTask(task),
      task: task,
      onSaved: _load,
    );
  }

  int _columnIdOfTask(Map<String, dynamic> task) {
    // Fallback only — the dialog also offers an explicit column picker.
    final cols = _columnRefs;
    return cols.isNotEmpty ? cols.first.id : 0;
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    if (!await _confirm('Obrisati task "${task['title']}"?')) return;
    try {
      await widget.api.delete('/api/tasks/${task['id']}');
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _moveTask(Map<String, dynamic> task) async {
    final cols = _columnRefs;
    if (cols.length < 2) return;
    final target = await showDialog<ColumnRef>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: SR.panel,
        title: const Text('Premjesti task u...'),
        children: [
          for (final c in cols)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Text(c.name, style: const TextStyle(color: SR.text)),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    try {
      await widget.api.patch('/api/tasks/${task['id']}/move', {'column_id': target.id, 'position': 0});
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _toggleComplete(Map<String, dynamic> task) async {
    try {
      await widget.api.patch('/api/tasks/${task['id']}/completed', {});
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _toggleItem(Map<String, dynamic> task, Map<String, dynamic> item) async {
    final next = !(item['is_done'] as bool? ?? false);
    try {
      await widget.api.patch('/api/tasks/${task['id']}/items/${item['id']}',
          {'title': item['title'], 'is_done': next});
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final columns = (_board?['columns'] as List<dynamic>? ?? []);
    return Scaffold(
      appBar: AppBar(
        title: Text(_board?['name'] as String? ?? widget.boardName),
        actions: [
          IconButton(
            tooltip: 'Pretraži',
            icon: const Icon(Icons.search),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final r = await showSearch<Map<String, dynamic>?>(context: context, delegate: BoardSearchDelegate(api: widget.api));
              if (r == null || r['board_id'] == null) return;
              final boardId = r['board_id'] as int;
              if (boardId == widget.boardId) {
                await _load();
                return;
              }
              if (!mounted) return;
              await navigator.push(MaterialPageRoute(
                builder: (_) => BoardScreen(
                  api: widget.api,
                  boardId: boardId,
                  boardName: r['board_name'] as String? ?? 'Ploča',
                  projects: widget.projects,
                ),
              ));
              await _load();
            },
          ),
          IconButton(onPressed: _addColumn, icon: const Icon(Icons.view_column_outlined), tooltip: 'Nova kolona'),
          IconButton(onPressed: _editBoard, icon: const Icon(Icons.edit_outlined), tooltip: 'Uredi ploču'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: SR.muted)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Pokušaj ponovno')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final col in columns)
                        _ColumnView(
                          name: col['name'] as String? ?? '',
                          raw: Map<String, dynamic>.from(col as Map),
                          tasks: List<Map<String, dynamic>>.from(
                              (col['tasks'] as List<dynamic>? ?? []).map((t) => Map<String, dynamic>.from(t as Map))),
                          onNewTask: _newTask,
                          onEditTask: _editTask,
                          onDeleteTask: _deleteTask,
                          onMoveTask: _moveTask,
                          onToggleComplete: _toggleComplete,
                          onToggleItem: _toggleItem,
                          onRenameColumn: _renameColumn,
                          onDeleteColumn: _deleteColumn,
                        ),
                      if (columns.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('Nema kolona — dodajte prvu (ikonica kolona gore).',
                                style: TextStyle(color: SR.muted)),
                          ),
                        ),
                    ],
                  ),
                ),
      floatingActionButton: columns.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: SR.accent,
              foregroundColor: Colors.white,
              onPressed: () => _newTask(Map<String, dynamic>.from(columns.first as Map)),
              icon: const Icon(Icons.add),
              label: const Text('Task'),
            ),
    );
  }
}

class _ColumnView extends StatelessWidget {
  const _ColumnView({
    required this.name,
    required this.raw,
    required this.tasks,
    required this.onNewTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onMoveTask,
    required this.onToggleComplete,
    required this.onToggleItem,
    required this.onRenameColumn,
    required this.onDeleteColumn,
  });

  final String name;
  final Map<String, dynamic> raw;
  final List<Map<String, dynamic>> tasks;
  final Future<void> Function(Map<String, dynamic>) onNewTask;
  final Future<void> Function(Map<String, dynamic>) onEditTask;
  final Future<void> Function(Map<String, dynamic>) onDeleteTask;
  final Future<void> Function(Map<String, dynamic>) onMoveTask;
  final Future<void> Function(Map<String, dynamic>) onToggleComplete;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>) onToggleItem;
  final Future<void> Function(Map<String, dynamic>) onRenameColumn;
  final Future<void> Function(Map<String, dynamic>) onDeleteColumn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 290,
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
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => onRenameColumn(raw),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Preimenuj kolonu',
                icon: const Icon(Icons.edit_outlined, size: 16, color: SR.muted),
                onPressed: () => onRenameColumn(raw),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Obriši kolonu',
                icon: const Icon(Icons.delete_outline, size: 16, color: SR.muted),
                onPressed: () => onDeleteColumn(raw),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              children: [
                for (final t in tasks)
                  _TaskCard(
                    task: t,
                    onEdit: () => onEditTask(t),
                    onDelete: () => onDeleteTask(t),
                    onMove: () => onMoveTask(t),
                    onToggleComplete: () => onToggleComplete(t),
                    onToggleItem: (item) => onToggleItem(t, item),
                  ),
                if (tasks.isEmpty)
                  const Text('—', textAlign: TextAlign.center, style: TextStyle(color: SR.muted)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => onNewTask(raw),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Novi task', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onMove,
    required this.onToggleComplete,
    required this.onToggleItem,
  });

  final Map<String, dynamic> task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onToggleComplete;
  final void Function(Map<String, dynamic>) onToggleItem;

  @override
  Widget build(BuildContext context) {
    final completed = task['completed'] as bool? ?? false;
    final mentioned = task['mentions_me'] as bool? ?? false;
    final hasItems = (task['items'] as List<dynamic>? ?? []).isNotEmpty;
    final items = List<Map<String, dynamic>>.from(
        (task['items'] as List<dynamic>? ?? []).map((i) => Map<String, dynamic>.from(i as Map)));
    final doneCount = items.where((i) => i['is_done'] as bool? ?? false).length;

    Color? cardColor;
    if (completed) {
      cardColor = const Color(0x1F22C55E); // green tint
    } else if (mentioned) {
      cardColor = const Color(0x1FF59E0B); // orange tint = tagged me
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor ?? SR.panelDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: completed ? SR.done : (mentioned ? SR.mention : SR.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onEdit,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Checkbox(
                      value: completed,
                      // Tasks with a checklist complete only when every item is ticked
                      // (same rule as the web app).
                      onChanged: hasItems ? null : (_) => onToggleComplete(),
                      activeColor: SR.done,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        task['title'] as String? ?? '',
                        style: TextStyle(
                          decoration: completed ? TextDecoration.lineThrough : null,
                          color: completed ? SR.done : SR.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconColor: SR.muted,
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'move') onMove();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Uredi')),
                      PopupMenuItem(value: 'move', child: Text('Premjesti')),
                      PopupMenuItem(value: 'delete', child: Text('Obriši')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if ((task['description'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Text(task['description'] as String, style: const TextStyle(color: SR.muted, fontSize: 12)),
            ),
          if ((task['assignee'] as String?) != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Text('👤 ${task['assignee']}', style: const TextStyle(color: SR.muted, fontSize: 12)),
            ),
          if (items.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
              child: Text(
                completed ? '✓ $doneCount/${items.length} stavki' : '$doneCount/${items.length} stavki',
                style: TextStyle(color: completed ? SR.done : SR.accent, fontSize: 12),
              ),
            ),
            for (final item in items)
              InkWell(
                onTap: () => onToggleItem(item),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
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
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
