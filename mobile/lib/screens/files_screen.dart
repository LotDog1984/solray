import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../services/sync.dart';
import '../theme.dart';

/// Datoteke for one project (web parity): upload, thumbnails, list/grid,
/// open & share. Auth token is embedded in thumb URLs like the web app.
class FilesScreen extends StatefulWidget {
  const FilesScreen({
    super.key,
    required this.api,
    required this.projectId,
    required this.projectName,
    this.syncListener,
    this.cameraPicker,
    this.galleryPicker,
  });

  final Api api;
  final int projectId;
  final String projectName;

  /// Test hooks — null = production behavior (real SyncBus / ImagePicker).
  @visibleForTesting
  final void Function(String scope, void Function() onEvent)? syncListener;
  @visibleForTesting
  final Future<XFile?> Function()? cameraPicker;

  /// 1.14.1: upload an ALREADY TAKEN photo from the phone's gallery.
  @visibleForTesting
  final Future<XFile?> Function()? galleryPicker;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  bool _grid = false;
  String? _error;
  bool _busy = false;
  void Function()? _syncCancel;

  @override
  void initState() {
    super.initState();
    _load();
    // Real-time sync: someone uploaded from web/another device — reload
    // silently; slow-poll tick keeps the list fresh if the socket is down.
    // (Under `flutter test` the default is a no-op — no sockets/timers there;
    // pass syncListener explicitly to exercise sync-driven reloads.)
    final scope = 'files:${widget.projectId}';
    final custom = widget.syncListener ??
        (Platform.environment.containsKey('FLUTTER_TEST')
            ? (String _, void Function() __) {}
            : null);
    if (custom != null) {
      custom(scope, () {
        if (mounted) _load();
      });
      _syncCancel = () {}; // tests own the subscription lifecycle
    } else {
      _syncCancel = SyncBus.forApi(widget.api).listen(scope, (_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _syncCancel?.call();
    super.dispose();
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
    await _uploadBytes(file.name, file.bytes!);
  }

  /// 1.14.1: pick an existing photo from the gallery and upload it through
  /// the same compress → name → upload pipeline as a camera shot.
  @visibleForTesting
  Future<void> pickPhotoFromGallery() async {
    final XFile? picked;
    try {
      picked = widget.galleryPicker != null
          ? await widget.galleryPicker!()
          : await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 90,
            );
    } catch (e) {
      _toast(Exception(e.toString().replaceFirst('Exception: ', '')));
      return;
    }
    if (picked == null || !mounted) return; // user backed out of the picker
    await _processAndUploadShot(picked);
  }

  /// Take a photo with the camera and upload it through the same pipeline.
  @visibleForTesting
  Future<void> takePhotoFromCamera() async {
    final XFile? shot;
    try {
      shot = widget.cameraPicker != null
          ? await widget.cameraPicker!()
          : await ImagePicker().pickImage(
              source: ImageSource.camera,
              imageQuality: 90,
              preferredCameraDevice: CameraDevice.rear,
            );
    } catch (e) {
      _toast(Exception(e.toString().replaceFirst('Exception: ', '')));
      return;
    }
    if (shot == null || !mounted) return; // user backed out of the camera
    await _processAndUploadShot(shot);
  }

  /// Shared post-pick pipeline (camera AND gallery): downscale huge photos,
  /// ask for a name, upload as JPEG. Full-resolution shots are 3-8 MB —
  /// slow to upload and pointless for documentation photos. image_picker
  /// already re-encodes to JPEG (imageQuality: 90), so the second pass only
  /// runs for images larger than 1600px. Best-effort: on failure the
  /// original file is uploaded unchanged.
  Future<void> _processAndUploadShot(XFile shot) async {
    List<int>? compressed;
    String mimeType = shot.mimeType ?? 'image/jpeg';
    try {
      // decodeImageDimensions is pure Dart (package:image). Decoding inline is
      // fast (header parse + downscale-only decode of an already-JPEG shot).
      final dims = decodeImageDimensions(await shot.readAsBytes());
      if (dims != null && (dims.$1 > 1600 || dims.$2 > 1600)) {
        final longest = dims.$1 > dims.$2 ? dims.$1 : dims.$2;
        final factor = 1600 / longest;
        final small = await FlutterImageCompress.compressWithFile(
          shot.path,
          minWidth: (dims.$1 * factor).round(),
          minHeight: (dims.$2 * factor).round(),
          quality: 85,
          format: CompressFormat.jpeg,
        );
        if (small != null && small.isNotEmpty) {
          compressed = small;
          mimeType = 'image/jpeg';
        }
      }
    } catch (_) {
      // compression unavailable / failed — the original upload still works
    }
    // 1.16.0: the name dialog opens with a BLANK field — the old default
    // (date / original gallery name) had to be deleted by hand every single
    // time. An empty name still falls back to defaultPhotoName() below.
    final name = await _photoNameDialog();
    if (name == null || !mounted) return; // cancelled — the photo is discarded
    final trimmed = name.trim();
    final fileName = trimmed.isEmpty
        ? defaultPhotoName(shot.name)
        : (trimmed.toLowerCase().endsWith('.jpg') ? trimmed : '$trimmed.jpg');
    List<int> bytes;
    try {
      bytes = compressed ?? await shot.readAsBytes();
    } catch (e) {
      _toast(e);
      return;
    }
    await _uploadBytes(fileName, bytes, contentType: mimeType);
  }

  /// Dialog before the upload: the user names the photo so it is easy to
  /// find in the list later. 1.16.0: the field starts BLANK (no prefill to
  /// delete) — saving an empty name falls back to the automatic
  /// [defaultPhotoName]. Cancel throws the photo away.
  Future<String?> _photoNameDialog({String? prefill}) {
    final controller = TextEditingController(text: prefill ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Naziv fotografije'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Naziv slike',
            hintText: 'Prazno = automatski naziv',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Spremi')),
        ],
      ),
    );
  }

  Future<void> _uploadBytes(String fileName, List<int> bytes, {String? contentType}) async {
    setState(() => _busy = true);
    try {
      await widget.api.upload(widget.projectId, fileName, bytes, contentType: contentType ?? 'application/octet-stream');
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

  /// 1.17.0 (web parity): rename an uploaded file. PATCH /api/files/{id}
  /// changes only the display name — the stored bytes keep their path.
  Future<void> _renameFile(Map<String, dynamic> f) async {
    final ctrl = TextEditingController(text: f['name'] as String? ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SR.panel,
        title: const Text('Preimenuj datoteku'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Novi naziv datoteke'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Odustani')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Spremi'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await widget.api.patch('/api/files/${f['id']}', {'name': name});
      if (!mounted) return;
      await _load();
    } catch (e) {
      _toast(e);
    }
  }

  Future<void> _deleteFile(Map<String, dynamic> f) async {
    final name = f['name'] as String? ?? 'datoteku';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Brisanje datoteke'),
        content: Text('Trajno obrisati "$name"? Ova radnja se ne može poništiti.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Odustani'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Obriši'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.delete('/api/files/${f['id']}');
      if (!mounted) return;
      await _load();
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
      backgroundColor: Colors.transparent,
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
                            onRename: () => _renameFile(f),
                            onDelete: () => _deleteFile(f),
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
                                    // Server-generated thumbnail, sized for the row
                                    cacheWidth: 96,
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Preimenuj datoteku',
                                icon: const Icon(Icons.edit_outlined, size: 20, color: SR.muted),
                                onPressed: () => _renameFile(f),
                              ),
                              IconButton(
                                tooltip: 'Podijeli datoteku',
                                icon: const Icon(Icons.share_outlined, size: 20, color: SR.muted),
                                onPressed: () => _shareFile(f),
                              ),
                              IconButton(
                                tooltip: 'Obriši datoteku',
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                onPressed: () => _deleteFile(f),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'upload_file',
            backgroundColor: SR.panel,
            foregroundColor: Colors.white,
            onPressed: _busy ? null : _upload,
            icon: const Icon(Icons.upload_file),
            label: const Text('Datoteka'),
          ),
          const SizedBox(height: 12),
          // 1.14.1: upload an already-taken photo from the gallery.
          FloatingActionButton.extended(
            heroTag: 'upload_gallery',
            backgroundColor: SR.panel,
            foregroundColor: Colors.white,
            onPressed: _busy ? null : pickPhotoFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Galerija'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'take_photo',
            backgroundColor: SR.accent,
            foregroundColor: Colors.white,
            onPressed: _busy ? null : takePhotoFromCamera,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.photo_camera_outlined),
            label: const Text('Slikaj'),
          ),
        ],
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
    required this.onRename,
    required this.onDelete,
  });

  final Map<String, dynamic> file;
  final bool isImage;
  final String thumbUrl;
  final String subtitle;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onRename;
  final VoidCallback onDelete;

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
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: SR.panelDeep),
                          // Server-generated thumbnail (max 420px) — not the
                          // full original, which stalled on slow connections.
                          Image.network(
                            thumbUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.insert_drive_file_outlined, color: SR.accent, size: 36),
                          ),
                        ],
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
                  // Three actions in a ~110px card: zero padding + tight
                  // constraints keep the row inside the (narrow) grid tile.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Preimenuj datoteku',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        icon: const Icon(Icons.edit_outlined, size: 16, color: SR.muted),
                        onPressed: onRename,
                      ),
                      IconButton(
                        tooltip: 'Podijeli datoteku',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        icon: const Icon(Icons.share_outlined, size: 16, color: SR.muted),
                        onPressed: onShare,
                      ),
                      IconButton(
                        tooltip: 'Obriši datoteku',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                        onPressed: onDelete,
                      ),
                    ],
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

/// (width, height) of an encoded image, or null when it cannot be decoded.
/// Top-level (pure Dart) so tests can call it directly.
const (int, int)? Function(Uint8List) decodeImageDimensions = _decodeImageDimensions;

/// Fallback file name for a photo whose dialog field was left empty (1.16.0:
/// the dialog starts blank): keep the original gallery name (without
/// extension) when it is meaningful, otherwise today's date. Top-level (pure
/// Dart) so tests can call it directly.
String defaultPhotoName(String originalName) {
  final base = originalName.replaceAll(RegExp(r'\.[^.]+$'), '').trim();
  if (base.isNotEmpty && base.toLowerCase() != 'image') return '$base.jpg';
  return 'Slika ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}.jpg';
}

(int, int)? _decodeImageDimensions(Uint8List bytes) {
  try {
    final im = img.decodeImage(bytes);
    if (im == null) return null;
    return (im.width, im.height);
  } catch (_) {
    return null;
  }
}
