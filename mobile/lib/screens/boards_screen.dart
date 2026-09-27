import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'board_screen.dart';

/// Boards layer for one project (web parity): list, create, rename, delete,
/// move a board to another project.
class BoardsScreen extends StatefulWidget {
  const BoardsScreen({
    super.key,
    required this.api,
    required this.projectId,
    required this.projectName,
  });

  final Api api;
  final int projectId;
  final String projectName;

  @override
  State<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends State<BoardsScreen> {
  List<Map<String, dynamic>> _boards = [];
  List<Map<String, dynamic>> _allProjects = [];
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
      final projects = await widget.api.get('/api/projects') as List<dynamic>;
      final all = List<Map<String, dynamic>>.from(projects.map((p) => Map<String, dynamic>.from(p as Map)));
      final mine = all.firstWhere(
        (p) => p['id'] == widget.projectId,
        orElse: () => {'id': widget.projectId, 'name': widget.projectName, 'boards': []},
      );
      if (!mounted) return;
      setState(() {
        _allProjects = all;
        _boards = List<Map<String, dynamic>>.from((mine['boards'] as List<dynamic>? ?? [])
            .map((b) => Map<String, dynamic>.from(b as Map)));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  Future<void> _newBoard() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Nova ploča'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Naziv ploče'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dodaj')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.post('/api/boards', {'name': ctrl.text.trim(), 'project_id': widget.projectId});
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _editBoard(Map<String, dynamic> b) async {
    final ctrl = TextEditingController(text: b['name'] as String? ?? '');
    int? projectId = b['project_id'] as int?;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: SR.panel,
          title: const Text('Uredi ploču'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ctrl, autofocus: true),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: projectId,
                decoration: const InputDecoration(labelText: 'Projekt'),
                items: [
                  for (final p in _allProjects)
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
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Odustani')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Spremi')),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'delete') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: SR.panel,
            title: const Text('Potvrda'),
            content: Text('Obrisati ploču "${b['name']}" sa svim kolonama i taskovima?'),
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
        if (confirmed != true) return;
        await widget.api.delete('/api/boards/${b['id']}');
      } else if (action == 'save') {
        await widget.api.patch('/api/boards/${b['id']}', {'name': ctrl.text.trim(), 'project_id': projectId});
      } else {
        return;
      }
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.projectName),
        bottom: _boards.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, right: 16, bottom: 10),
                  child: Row(
                    children: [
                      Expanded(child: Text('${_boards.length} ploče', style: const TextStyle(color: SR.muted, fontSize: 11))),
                      Text('${_boards.fold<int>(0, (sum, board) => sum + ((board['open_task_count'] as num?)?.toInt() ?? (board['task_count'] as num?)?.toInt() ?? 0))} otvoreno',
                          style: const TextStyle(color: SR.muted, fontSize: 11)),
                    ],
                  ),
                ),
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Center(
                      child: Column(
                        children: [
                          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                          OutlinedButton(onPressed: _load, child: const Text('Pokušaj ponovno')),
                        ],
                      ),
                    )
                  else ...[
                    for (final b in _boards)
                      Builder(builder: (context) {
                        final total = (b['task_count'] as num?)?.toInt() ?? 0;
                        final open = (b['open_task_count'] as num?)?.toInt() ?? total;
                        final completed = (b['completed_task_count'] as num?)?.toInt() ?? (total - open).clamp(0, total);
                        final progress = total == 0 ? 0 : ((completed / total) * 100).round();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          clipBehavior: Clip.antiAlias,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0x1FFFFFFF), Color(0x0AFFFFFF)],
                              ),
                            ),
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.fromLTRB(14, 5, 8, 2),
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: LinearGradient(colors: [SR.accent.withAlpha(70), SR.cyan.withAlpha(50)]),
                                      border: Border.all(color: SR.line),
                                    ),
                                    child: const Icon(Icons.view_kanban_outlined, color: SR.cyan, size: 21),
                                  ),
                                  title: Text(b['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text('$open otvoreno  ·  $total zadataka',
                                        style: const TextStyle(color: SR.muted, fontSize: 11)),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SRProgressRing(progress: total == 0 ? 0 : completed / total, label: '$progress%', size: 42),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        tooltip: 'Uredi',
                                        icon: const Icon(Icons.more_horiz, size: 21, color: SR.muted),
                                        onPressed: () => _editBoard(b),
                                      ),
                                    ],
                                  ),
                                  onTap: () async {
                                    await Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => BoardScreen(
                                        api: widget.api,
                                        boardId: b['id'] as int,
                                        boardName: b['name'] as String? ?? '',
                                        projects: _allProjects,
                                      ),
                                    ));
                                    await _load();
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: total == 0 ? 0 : completed / total,
                                      minHeight: 4,
                                      backgroundColor: SR.line,
                                      valueColor: const AlwaysStoppedAnimation<Color>(SR.cyan),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    if (_boards.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nema ploča — dodajte prvu.', style: TextStyle(color: SR.muted)),
                        ),
                      ),
                  ],
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: SR.accent,
        foregroundColor: Colors.white,
        onPressed: _newBoard,
        icon: const Icon(Icons.add),
        label: const Text('Ploča'),
      ),
    );
  }
}
