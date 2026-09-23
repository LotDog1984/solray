import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'boards_screen.dart';

/// Projects layer (web parity): list, create, rename, delete.
/// Tap a project → its boards screen.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.api, this.projects, this.appName});

  final Api api;
  final List<Map<String, dynamic>>? projects; // preloaded (optional)
  final String? appName;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Map<String, dynamic>>? _projects;
  String? _error;

  @override
  void initState() {
    super.initState();
    _projects = widget.projects;
    if (_projects == null) _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.get('/api/projects') as List<dynamic>;
      if (!mounted) return;
      setState(() => _projects = List<Map<String, dynamic>>.from(data.map((p) => Map<String, dynamic>.from(p as Map))));
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  Future<void> _newProject() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Novi projekt'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Naziv projekta'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dodaj')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.post('/api/projects', {'name': ctrl.text.trim()});
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _editProject(Map<String, dynamic> p) async {
    final ctrl = TextEditingController(text: p['name'] as String? ?? '');
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Uredi projekt'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Obriši projekt', style: TextStyle(color: Color(0xFFDC2626))),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Spremi')),
        ],
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
            content: Text('Obrisati projekt "${p['name']}" sa svim pločama i taskovima?'),
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
        await widget.api.delete('/api/projects/${p['id']}');
      } else if (action == 'save') {
        await widget.api.patch('/api/projects/${p['id']}', {'name': ctrl.text.trim()});
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
    final projects = _projects;
    return Scaffold(
      backgroundColor: SR.bg,
      body: RefreshIndicator(
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
          else if (projects == null)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else ...[
            for (final p in projects)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined, color: SR.accent),
                  title: Text(p['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${(p['boards'] as List<dynamic>? ?? []).length} ploča',
                    style: const TextStyle(color: SR.muted, fontSize: 12),
                  ),
                  trailing: IconButton(
                    tooltip: 'Uredi',
                    icon: const Icon(Icons.edit_outlined, size: 20, color: SR.muted),
                    onPressed: () => _editProject(p),
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => BoardsScreen(
                        api: widget.api,
                        projectId: p['id'] as int,
                        projectName: p['name'] as String? ?? '',
                      ),
                    ));
                    await _load();
                  },
                ),
              ),
            if (projects.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nema projekata — dodajte prvi.', style: TextStyle(color: SR.muted)),
                ),
              ),
          ],
        ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: SR.accent,
        foregroundColor: Colors.white,
        onPressed: _newProject,
        icon: const Icon(Icons.add),
        label: const Text('Projekt'),
      ),
    );
  }
}
