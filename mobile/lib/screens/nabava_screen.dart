import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../theme.dart';
import 'board_screen.dart';

/// 1.10.0: plain-text order for the supplier — only OPEN (unchecked) Stavke,
/// so re-sending an order never repeats already-bought items. 1.10.1: just the
/// item text the user typed — no project/board suffix in the export. Public so
/// tests can exercise the format directly.
String buildNabavaOrderText(List<Map<String, dynamic>> entries) {
  final open = entries.where((e) => !(e['is_done'] as bool? ?? false)).toList();
  if (open.isEmpty) return '';
  return open.map((e) => '- ${e['title'] as String? ?? ''}').join('\n');
}

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
  String _listName = 'Nabava';

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
        _listName = d['name'] as String? ?? 'Nabava';
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

  /// 1.10.0: export the OPEN items — opens the native share sheet (pick
  /// Gmail/Outlook/... and the list lands in the mail body). Subject is
  /// prefilled; body carries only unchecked items.
  Future<void> _export() async {
    final text = buildNabavaOrderText(_entries);
    if (text.isEmpty) {
      _showError('Nema otvorenih (neoznačenih) stavki za slanje.');
      return;
    }
    final now = DateTime.now();
    final subject = '$_listName — ${now.day}.${now.month}.${now.year}.';
    await Share.share(text, subject: subject);
  }

  /// 1.10.0: housekeeping — delete every checked Stavka from ALL lists.
  Future<void> _clearChecked() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Izbriši Preuzete Stvari?'),
        content: const Text('Ovo briše SVE označene (nabavljene) stavke iz svih popisa. Radnja se ne može poništiti.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Izbriši')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.delete('/api/nabava/checked');
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

  /// 1.9.2: edit a Stavka's text after creation (typo, wrong quantity).
  /// Works for manual entries (global route) and board entries (board route).
  Future<void> _rename(Map<String, dynamic> e) async {
    final ctrl = TextEditingController(text: e['title'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Uredi stavku'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Naziv stavke'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Spremi')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final title = ctrl.text.trim();
    if (title.isEmpty) return;
    try {
      if (e['board_id'] != null) {
        await widget.api.patch('/api/boards/${e['board_id']}/todo/${e['id']}', {'title': title});
      } else {
        await widget.api.patch('/api/nabava/items/${e['id']}', {'title': title});
      }
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _entries.any((e) => !(e['is_done'] as bool? ?? false)) ? _export : null,
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: const Text('Pošalji e-mailom'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _entries.any((e) => e['is_done'] as bool? ?? false) ? _clearChecked : null,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Izbriši Preuzete Stvari', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final e in _entries)
            NabavaEntryCard(entry: e, onToggle: _toggle, onDelete: _delete, onOpen: _openBoard, onRename: _rename),
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
/// checkbox + tappable title (tap = edit) + origin chip ("📁 Projekt → Ploča")
/// or a muted "✍️ Ručno dodano" marker for manually added entries + edit/delete.
class NabavaEntryCard extends StatelessWidget {
  const NabavaEntryCard({
    super.key,
    required this.entry,
    required this.onToggle,
    required this.onDelete,
    required this.onOpen,
    required this.onRename,
  });

  final Map<String, dynamic> entry;
  final Future<void> Function(Map<String, dynamic>) onToggle;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final Future<void> Function(Map<String, dynamic>) onOpen;
  final Future<void> Function(Map<String, dynamic>) onRename;

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
        // 1.9.2: tapping the row opens the rename dialog (the origin chip
        // keeps its own tap = open board).
        onTap: () => onRename(entry),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Uredi',
              icon: const Icon(Icons.edit_outlined, color: Color(0xFF93C5FD), size: 20),
              onPressed: () => onRename(entry),
            ),
            IconButton(
              tooltip: 'Obriši',
              icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 20),
              onPressed: () => onDelete(entry),
            ),
          ],
        ),
      ),
    );
  }
}
