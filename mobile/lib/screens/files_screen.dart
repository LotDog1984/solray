import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../theme.dart';

/// Datoteke for one project (web parity): upload, thumbnails, list/grid,
/// open & share. Auth token is embedded in thumb URLs like the web app.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, required this.api, required this.projectId, required this.projectName});

  final Api api;
  final int projectId;
  final String projectName;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  bool _grid = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final files = await widget.api.get('/api/projects/${widget.projectId}/files') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _files = List<Map<String, dynamic>>.from(files.map((f) => Map<String, dynamic>.from(f as Map)));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _toast(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  Future<void> _upload() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final file = res?.files.single;
    if (file == null || file.bytes == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.upload(widget.projectId, file.name, file.bytes!);
      await _load();
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isImage(Map<String, dynamic> f) => (f['content_type'] as String? ?? '').startsWith('image/');

  Future<void> _openFile(Map<String, dynamic> f) async {
    try {
      final bytes = await widget.api.download(f['id'] as int);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${f['id']}_${f['name'] as String? ?? 'file'}';
      await writeFileBytes(path, bytes);
      await OpenFilex.open(path);
    } catch (e) {
      _toast(e);
    }
  }

  Future<void> _shareFile(Map<String, dynamic> f) async {
    try {
      final bytes = await widget.api.download(f['id'] as int);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${f['id']}_${f['name'] as String? ?? 'file'}';
      await writeFileBytes(path, bytes);
      await Share.shareXFiles([XFile(path)]);
    } catch (e) {
      _toast(e);
    }
  }

  String _size(num bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} kB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SR.bg,
      appBar: AppBar(
        title: Text('Datoteke · ${widget.projectName}'),
        actions: [
          IconButton(
            tooltip: _grid ? 'Lista' : 'Mreža',
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view_outlined),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
                  else if (_files.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nema datoteka u ovom projektu.', style: TextStyle(color: SR.muted)),
                      ),
                    )
                  else if (_grid)
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.75,
                      children: [
                        for (final f in _files)
                          _GridCard(
                            file: f,
                            isImage: _isImage(f),
                            thumbUrl: widget.api.thumbUrl(f['id'] as int),
                            subtitle: _size(f['size'] as num? ?? 0),
                            onOpen: () => _openFile(f),
                            onShare: () => _shareFile(f),
                          ),
                      ],
                    )
                  else
                    for (final f in _files)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: _isImage(f)
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    widget.api.thumbUrl(f['id'] as int),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.insert_drive_file_outlined, color: SR.accent),
                                  ),
                                )
                              : const Icon(Icons.insert_drive_file_outlined, color: SR.accent),
                          title: Text(f['name'] as String? ?? '', overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${_size(f['size'] as num? ?? 0)} · ${f['uploaded_by'] as String? ?? ''}',
                            style: const TextStyle(color: SR.muted, fontSize: 12),
                          ),
                          onTap: () => _openFile(f),
                          trailing: IconButton(
                            icon: const Icon(Icons.share_outlined, size: 20, color: SR.muted),
                            onPressed: () => _shareFile(f),
                          ),
                        ),
                      ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: SR.accent,
        foregroundColor: Colors.white,
        onPressed: _busy ? null : _upload,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.upload_file),
        label: const Text('Učitaj'),
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  const _GridCard({
    required this.file,
    required this.isImage,
    required this.thumbUrl,
    required this.subtitle,
    required this.onOpen,
    required this.onShare,
  });

  final Map<String, dynamic> file;
  final bool isImage;
  final String thumbUrl;
  final String subtitle;
  final VoidCallback onOpen;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: SR.panelDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SR.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: isImage
                  ? ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      child: Image.network(
                        thumbUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.insert_drive_file_outlined, color: SR.accent, size: 36),
                      ),
                    )
                  : const Icon(Icons.insert_drive_file_outlined, color: SR.accent, size: 36),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file['name'] as String? ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  Text(subtitle, style: const TextStyle(color: SR.muted, fontSize: 10)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.share_outlined, size: 16, color: SR.muted),
                      onPressed: onShare,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Platform channel call — must run on the main isolate; bytes already in memory.
Future<void> writeFileBytes(String path, List<int> bytes) async {
  final file = File(path);
  await file.writeAsBytes(bytes);
}
