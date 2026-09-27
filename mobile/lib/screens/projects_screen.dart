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

  @override
  void didUpdateWidget(covariant ProjectsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.projects, oldWidget.projects) && widget.projects != null) {
      _projects = widget.projects;
    }
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
      backgroundColor: Colors.transparent,
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
              Builder(builder: (context) {
                final boards = p['boards'] as List<dynamic>? ?? [];
                final boardCount = (p['board_count'] as num?)?.toInt() ?? boards.length;
                final taskCount = (p['task_count'] as num?)?.toInt() ?? boards.fold<int>(
                    0, (sum, raw) => sum + ((raw['task_count'] as num?)?.toInt() ?? 0));
                final openCount = (p['open_task_count'] as num?)?.toInt() ?? boards.fold<int>(
                    0, (sum, raw) => sum + ((raw['open_task_count'] as num?)?.toInt() ??
                        ((raw['task_count'] as num?)?.toInt() ?? 0)));
                final completedCount = (p['completed_task_count'] as num?)?.toInt() ?? (taskCount - openCount).clamp(0, taskCount);
                final progress = taskCount == 0 ? 0 : ((completedCount / taskCount) * 100).round();
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
                        InkWell(
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
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    gradient: LinearGradient(colors: [SR.accent.withAlpha(70), SR.cyan.withAlpha(50)]),
                                    border: Border.all(color: SR.line),
                                  ),
                                  child: const Icon(Icons.folder_outlined, color: SR.cyan, size: 21),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                      const SizedBox(height: 5),
                                      Text('$boardCount ploče  ·  $openCount otvoreno',
                                          style: const TextStyle(color: SR.muted, fontSize: 11)),
                                      const SizedBox(height: 3),
                                      Text('$taskCount zadataka ukupno',
                                          style: const TextStyle(color: SR.muted2, fontSize: 10)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SRProgressRing(progress: taskCount == 0 ? 0 : completedCount / taskCount, label: '$progress%', size: 46),
                                IconButton(
                                  tooltip: 'Uredi',
                                  icon: const Icon(Icons.more_horiz, size: 21, color: SR.muted),
                                  onPressed: () => _editProject(p),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: taskCount == 0 ? 0 : completedCount / taskCount,
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
