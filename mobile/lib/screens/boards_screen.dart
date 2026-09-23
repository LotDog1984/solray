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
      backgroundColor: SR.bg,
      appBar: AppBar(title: Text(widget.projectName)),
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
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(Icons.view_kanban_outlined, color: SR.accent),
                          title: Text(b['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                          trailing: IconButton(
                            tooltip: 'Uredi',
                            icon: const Icon(Icons.edit_outlined, size: 20, color: SR.muted),
                            onPressed: () => _editBoard(b),
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
                      ),
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
