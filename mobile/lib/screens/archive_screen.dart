import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'boards_screen.dart';
import 'session_expired.dart';

/// Arhiva (1.20.0, web parity): archived projects — finished projects that
/// left the project page but kept everything. Tap a project to open its
/// boards (tasks and files work exactly like on the projects page);
/// „Vrati iz Arhive" puts it back under Projekti.
class ArchiveProjectsScreen extends StatefulWidget {
  const ArchiveProjectsScreen({super.key, required this.api});

  final Api api;

  @override
  State<ArchiveProjectsScreen> createState() => _ArchiveProjectsScreenState();
}

class _ArchiveProjectsScreenState extends State<ArchiveProjectsScreen> {
  List<Map<String, dynamic>>? _projects;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.get('/api/projects/archived') as List<dynamic>;
      if (!mounted) return;
      setState(() => _projects =
          List<Map<String, dynamic>>.from(data.map((p) => Map<String, dynamic>.from(p as Map))));
    } on AuthExpired {
      // 1.18.1: dead token → login screen instead of a retry that 401s forever.
      if (mounted) forceLoginScreen(context, widget.api);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _unarchive(Map<String, dynamic> project) async {
    try {
      await widget.api.post('/api/projects/${project['id']}/unarchive', <String, dynamic>{});
      if (!mounted) return;
      _showMessage('✓ Projekt "${project['name']}" vraćen iz Arhive');
      await _load();
    } on AuthExpired {
      if (mounted) forceLoginScreen(context, widget.api);
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _deleteProject(Map<String, dynamic> project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Trajno brisanje'),
        content: Text('Obrisati arhivirani projekt "${project['name']}" sa svim pločama i taskovima?'),
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
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.delete('/api/projects/${project['id']}');
      if (!mounted) return;
      _showMessage('✓ Projekt obrisan');
      await _load();
    } on AuthExpired {
      if (mounted) forceLoginScreen(context, widget.api);
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Arhiva'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Završeni projekti. Otvorite projekt za zadatke i datoteke — sve je tu sačuvano.',
                style: TextStyle(color: SR.muted, fontSize: 12),
              ),
            ),
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
                          colors: [Color(0x0FFFFFFF), Color(0x05FFFFFF)],
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
                                  archivedBoards: List<Map<String, dynamic>>.from(
                                      boards.map((b) => Map<String, dynamic>.from(b as Map))),
                                  archived: true,
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
                                      gradient: LinearGradient(
                                          colors: [SR.accent.withAlpha(70), SR.cyan.withAlpha(50)]),
                                      border: Border.all(color: SR.line),
                                    ),
                                    child: const Icon(Icons.archive_outlined, color: SR.cyan, size: 21),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p['name'] as String? ?? '',
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                        const SizedBox(height: 5),
                                        Text('$boardCount ploče  ·  $openCount/$taskCount zadataka  ·  $progress% gotovo',
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: SR.muted, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SRProgressRing(progress: taskCount == 0 ? 0 : completedCount / taskCount, label: '$progress%', size: 46),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _unarchive(p),
                                    icon: const Icon(Icons.unarchive_outlined, size: 18),
                                    label: const Text('Vrati iz Arhive'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Trajno obriši',
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFDC2626)),
                                  onPressed: () => _deleteProject(p),
                                ),
                              ],
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
                    child: Text('Arhiva je prazna — arhivirani projekti navode se ovdje.',
                        style: TextStyle(color: SR.muted)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
