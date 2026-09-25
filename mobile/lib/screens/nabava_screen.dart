import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'board_screen.dart';

/// Global "Nabava" tab — one-stop shopping list aggregating the supplies
/// To-Do entries of ALL boards. Every entry shows the project + board it
/// came from (tap it to open that board), matching the web app's view.
/// Like [NotificationsScreen], this is a TAB BODY: no Scaffold/AppBar —
/// HomeScreen owns those.
class NabavaTab extends StatefulWidget {
  const NabavaTab({super.key, required this.api, this.onChanged, this.refreshSignal = 0});

  final Api api;
  final VoidCallback? onChanged;

  /// Bumped by HomeScreen whenever a sync event says Nabava data changed —
  /// the tab reloads without any manual refresh ([didUpdateWidget]).
  final int refreshSignal;

  @override
  State<NabavaTab> createState() => _NabavaTabState();
}

class _NabavaTabState extends State<NabavaTab> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void didUpdateWidget(NabavaTab old) {
    super.didUpdateWidget(old);
    if (widget.refreshSignal != old.refreshSignal) _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.get('/api/nabava') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _entries = List<Map<String, dynamic>>.from(
            (d['entries'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
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

  Future<void> _toggle(Map<String, dynamic> e) async {
    final next = !(e['is_done'] as bool? ?? false);
    try {
      await widget.api.patch('/api/boards/${e['board_id']}/todo/${e['id']}',
          {'title': e['title'], 'is_done': next});
      await _load();
      widget.onChanged?.call();
    } catch (err) {
      _showError(err);
    }
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    try {
      await widget.api.delete('/api/boards/${e['board_id']}/todo/${e['id']}');
      await _load();
      widget.onChanged?.call();
    } catch (err) {
      _showError(err);
    }
  }

  Future<void> _addManual() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Nova stavka (ručno)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'npr. Vijci 6x60 (fali 50 kom)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dodaj')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final title = ctrl.text.trim();
    if (title.isEmpty) return;
    try {
      await widget.api.post('/api/nabava/items', {'title': title});
      await _load();
      widget.onChanged?.call();
    } catch (err) {
      _showError(err);
    }
  }

  Future<void> _openBoard(Map<String, dynamic> e) async {
    final boardId = e['board_id'] as int?;
    if (boardId == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BoardScreen(
        api: widget.api,
        boardId: boardId,
        boardName: e['board_name'] as String? ?? 'Ploča',
      ),
    ));
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final open = _entries.where((e) => !(e['is_done'] as bool? ?? false)).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _error != null
                ? _error!
                : open > 0
                    ? '$open za nabaviti'
                    : 'Sve nabavljeno 🎉',
            style: TextStyle(color: _error != null ? Colors.redAccent : SR.muted, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Zajednički popis svih stavki za nabavu iz svih ploča. Svaka stavka nosi projekt i ploču u kojoj je nastala — dodajete ih u To-Do popisu na ploči ili ručno ovdje.',
            style: TextStyle(color: SR.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addManual,
            icon: const Icon(Icons.add),
            label: const Text('Dodaj stavku ručno'),
          ),
          const SizedBox(height: 12),
          for (final e in _entries)
            NabavaEntryCard(entry: e, onToggle: _toggle, onDelete: _delete, onOpen: _openBoard),
          if (_entries.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nema stavki za nabavu. Dodajte ih u To-Do popisu na bilo kojoj ploči ili ručno ovdje.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SR.muted),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Center(child: OutlinedButton(onPressed: _load, child: const Text('Pokušaj ponovno'))),
          ],
        ],
      ),
    );
  }
}

/// One aggregated Nabava row (public so tests can exercise it directly):
/// checkbox + title + tappable origin chip ("📁 Projekt → Ploča") or a muted
/// "✍️ Ručno dodano" marker for manually added entries + delete.
class NabavaEntryCard extends StatelessWidget {
  const NabavaEntryCard({
    super.key,
    required this.entry,
    required this.onToggle,
    required this.onDelete,
    required this.onOpen,
  });

  final Map<String, dynamic> entry;
  final Future<void> Function(Map<String, dynamic>) onToggle;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final Future<void> Function(Map<String, dynamic>) onOpen;

  @override
  Widget build(BuildContext context) {
    final done = entry['is_done'] as bool? ?? false;
    final project = entry['project_name'] as String? ?? '';
    final board = entry['board_name'] as String? ?? '';
    // 1.9.0: entries added manually in this list have no board — show a
    // muted "✍️ Ručno dodano" marker instead of the tappable origin chip.
    final manual = entry['board_id'] == null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: done ? const Color(0x2422C55E) : SR.panelDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: done ? SR.done : SR.line),
      ),
      child: ListTile(
        leading: Checkbox(
          value: done,
          onChanged: (_) => onToggle(entry),
          activeColor: SR.done,
        ),
        title: Text(
          entry['title'] as String? ?? '',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: done ? SR.done : SR.text,
            decoration: done ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: manual
              ? const Text(
                  '✍️ Ručno dodano',
                  style: TextStyle(color: SR.muted, fontSize: 12),
                )
              : InkWell(
                  onTap: () => onOpen(entry),
                  child: Text(
                    '📁 ${project.isNotEmpty ? '$project → ' : ''}$board',
                    style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 12),
                  ),
                ),
        ),
        trailing: IconButton(
          tooltip: 'Obriši',
          icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 20),
          onPressed: () => onDelete(entry),
        ),
      ),
    );
  }
}
