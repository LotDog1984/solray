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
  });

  final Api api;
  final int projectId;
  final String projectName;

  /// Test hooks — null = production behavior (real SyncBus / ImagePicker).
  @visibleForTesting
  final void Function(String scope, void Function() onEvent)? syncListener;
  @visibleForTesting
  final Future<XFile?> Function()? cameraPicker;

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

  /// Take a photo with the camera, let the user name it, upload as JPEG.
  /// The name makes photos findable in the list — nobody should have to open
  /// pictures one by one to find the one they need.
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

    // Downscale to max ~1600px — full-resolution camera shots are 3-8 MB,
    // which is slow to upload and pointless for documentation photos.
    // image_picker already re-encodes to JPEG (imageQuality: 90), so the
    // second pass only runs for shots larger than 1600px. Best-effort: on
    // failure the original file is uploaded unchanged.
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
    }      final name = await _cameraNameDialog();
    if (name == null || !mounted) return; // cancelled — the photo is discarded
    final trimmed = name.trim();
    final fileName = trimmed.isEmpty
        ? 'Slika ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}.jpg'
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

  /// Dialog right after the shot: the user names the photo so it is easy to
  /// find in the list later. Cancel throws the photo away.
  Future<String?> _cameraNameDialog() {
    final controller = TextEditingController(
        text: 'Slika ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Naziv fotografije'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Naziv slike'),
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
                          trailing: IconButton(
                            icon: const Icon(Icons.share_outlined, size: 20, color: SR.muted),
                            onPressed: () => _shareFile(f),
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

/// (width, height) of an encoded image, or null when it cannot be decoded.
/// Top-level (pure Dart) so tests can call it directly.
const (int, int)? Function(Uint8List) decodeImageDimensions = _decodeImageDimensions;

(int, int)? _decodeImageDimensions(Uint8List bytes) {
  try {
    final im = img.decodeImage(bytes);
    if (im == null) return null;
    return (im.width, im.height);
  } catch (_) {
    return null;
  }
}
