import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'board_screen.dart';

/// Full-screen search over projects, boards, tasks and Nabava entries (web
/// app parity). Tap a task → opens its board; a board Nabava hit opens its
/// board; a manual Nabava hit jumps to the Nabava tab. Shared /api/search.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.api, this.onOpenNabava});

  final Api api;

  /// 1.9.3: called when the user taps a manually added Nabava hit —
  /// HomeScreen switches to the Nabava tab.
  final VoidCallback? onOpenNabava;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  String? _error;

  Future<void> _run(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final d = await widget.api.get('/api/search', query: {'q': q.trim()}) as Map<String, dynamic>;
      setState(() {
        _results = List<Map<String, dynamic>>.from((d['results'] as List<dynamic>).map((r) => Map<String, dynamic>.from(r as Map)));
        _error = null;
        _searching = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _searching = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> r) async {
    final type = r['type'] as String? ?? '';
    if (type == 'nabava') {
      // 1.9.3: board-origin Stavka → its board; manual one → Nabava tab.
      if (r['board_id'] != null) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BoardScreen(
            api: widget.api,
            boardId: r['board_id'] as int,
            boardName: r['board_name'] as String? ?? 'Ploča',
          ),
        ));
      } else {
        widget.onOpenNabava?.call();
      }
      return;
    }
    if (type != 'task' || r['board_id'] == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BoardScreen(
        api: widget.api,
        boardId: r['board_id'] as int,
        boardName: r['board_name'] as String? ?? 'Ploča',
      ),
    ));
  }

  IconData _icon(String type) => switch (type) {
        'project' => Icons.folder_outlined,
        'board' => Icons.view_kanban_outlined,
        'nabava' => Icons.shopping_cart_outlined,
        _ => Icons.check_circle_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SR.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Pretraži projekte, ploče, taskove, nabavu...',
            border: InputBorder.none,
          ),
          onChanged: _run,
        ),
        actions: [
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          for (final r in _results)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(_icon(r['type'] as String? ?? ''), color: SR.accent),
                title: Text(r['label'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['detail'] as String? ?? '', style: const TextStyle(color: SR.muted, fontSize: 12)),
                    if ((r['snippet'] as String? ?? '').isNotEmpty)
                      Text(r['snippet'] as String, style: const TextStyle(color: SR.muted, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
                onTap: () => _open(r),
              ),
            ),
          if (_results.isEmpty && _ctrl.text.trim().length >= 2 && !_searching && _error == null)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Nema rezultata.', style: TextStyle(color: SR.muted)))),
        ],
      ),
    );
  }
}

/// SearchDelegate variant used from inside the board screen toolbar.
class BoardSearchDelegate extends SearchDelegate<Map<String, dynamic>?> {
  BoardSearchDelegate({required this.api});

  final Api api;

  @override
  String get searchFieldLabel => 'Pretraži sve...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(backgroundColor: SR.sidebar),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: SR.muted),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) =>
      BackButton(onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _build(context);

  @override
  Widget buildSuggestions(BuildContext context) => _build(context);

  Widget _build(BuildContext context) {
    if (query.trim().length < 2) {
      return const Center(child: Text('Upišite barem 2 znaka.', style: TextStyle(color: SR.muted)));
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: () async {
        final d = await api.get('/api/search', query: {'q': query.trim()});
        return d as Map<String, dynamic>;
      }(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('${snap.error}'.replaceFirst('Exception: ', ''), style: const TextStyle(color: Colors.redAccent)));
        }
        final results = List<Map<String, dynamic>>.from(
            (snap.data!['results'] as List<dynamic>).map((r) => Map<String, dynamic>.from(r as Map)));
        if (results.isEmpty) {
          return const Center(child: Text('Nema rezultata.', style: TextStyle(color: SR.muted)));
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final r in results)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    r['type'] == 'project'
                        ? Icons.folder_outlined
                        : r['type'] == 'board'
                            ? Icons.view_kanban_outlined
                            : r['type'] == 'nabava'
                                ? Icons.shopping_cart_outlined
                                : Icons.check_circle_outline,
                    color: SR.accent,
                  ),
                  title: Text(r['label'] as String? ?? ''),
                  subtitle: Text(r['detail'] as String? ?? '', style: const TextStyle(color: SR.muted, fontSize: 12)),
                  onTap: () {
                    if (r['board_id'] != null) close(context, r);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
