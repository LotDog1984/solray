import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:solray/api.dart';
import 'package:solray/screens/files_screen.dart';

/// One-element in-memory JPEG standing in for a camera shot.
Uint8List jpegBytes({int w = 320, int h = 240}) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h), quality: 90));

/// A tiny PNG used to exercise thumbnail rendering.
Uint8List pngBytes({int w = 6, int h = 4}) =>
    Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

/// The file-part bytes of a multipart body (plain MockClient rebuilds the
/// request, so with MockClient.streaming we keep the MultipartRequest for its
/// metadata and slice the bytes out of the raw body ourselves).
List<int> _partBytes(List<int> body, String contentType) {
  final boundary = RegExp(r'boundary=(.+)$').firstMatch(contentType)!.group(1)!;
  final s = latin1.decode(body); // byte-preserving for marker search
  final headerEnd = s.indexOf('\r\n\r\n') + 4;
  final end = s.indexOf('\r\n--$boundary', headerEnd);
  return body.sublist(headerEnd, end);
}

Api _api(void Function(String filename, String contentType, List<int> bytes) onUpload) {
  return Api('https://x.test', token: 't',
      client: MockClient.streaming((req, bodyStream) async {
    if (req.url.path == '/api/projects/7/files' && req.method == 'GET') {
      return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          headers: {'content-type': 'application/json'});
    }
    if (req.url.path == '/api/projects/7/files') {
      final mreq = req as http.MultipartRequest;
      final part = mreq.files.single;
      final bytes = _partBytes(
          await bodyStream.toBytes(), mreq.headers['content-type']!);
      onUpload(part.filename ?? 'file', part.contentType.toString(), bytes);
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"id": 42, "name": "${part.filename}"}')),
          200,
          headers: {'content-type': 'application/json'});
    }
    return http.StreamedResponse(
        Stream.value(utf8.encode('{"detail": "not found"}')), 404);
  }));
}

FilesScreen _screen(
  Api api, {
  void Function(String scope, void Function() onEvent)? syncListener,
  Future<XFile?> Function()? cameraPicker,
}) =>
    FilesScreen(
      api: api,
      projectId: 7,
      projectName: 'Test',
      syncListener: syncListener,
      cameraPicker: cameraPicker,
    );

/// An in-memory XFile standing in for the camera result.
XFile shot() =>
    XFile.fromData(jpegBytes(), mimeType: 'image/jpeg', name: 'shot.jpg');

/// The row/card Image wraps its NetworkImage in a ResizeImage (cacheWidth) —
/// unwrap to assert on the URL.
bool pointsAtThumb(Image image) {
  final provider = image.image;
  final net = provider is NetworkImage
      ? provider
      : provider is ResizeImage
          ? provider.imageProvider as NetworkImage
          : null;
  return net?.url.contains('/api/files/42/thumb?token=t') ?? false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1.11.0: two buttons — Slikaj (camera) and Datoteka (upload); camera cancel uploads nothing', (tester) async {
    Uint8List? uploaded;
    final api = _api((filename, type, bytes) {
      uploaded = Uint8List.fromList(bytes);
    });

    await tester.pumpWidget(MaterialApp(
        home: _screen(api, cameraPicker: () async => null))); // user cancels
    await tester.pumpAndSettle();

    expect(find.text('Slikaj'), findsOneWidget);
    expect(find.text('Datoteka'), findsOneWidget);

    await tester.tap(find.text('Slikaj'));
    await tester.pumpAndSettle();

    // Cancelled at the camera: no naming dialog, nothing uploaded.
    expect(find.text('Naziv fotografije'), findsNothing);
    expect(uploaded, isNull);
  });

  testWidgets('1.11.0: photo flow — capture, name it, upload with image/jpeg', (tester) async {
    Uint8List? captured;
    String? capturedName;
    String? capturedType;
    final api = _api((filename, type, bytes) {
      captured = Uint8List.fromList(bytes);
      capturedName = filename;
      capturedType = type;
    });

    await tester.pumpWidget(MaterialApp(
        home: _screen(api, cameraPicker: () async => shot())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Slikaj'));
    await tester.pump(); // flow suspends on the naming dialog
    await tester.pumpAndSettle(); // dialog animation

    expect(find.text('Naziv fotografije'), findsOneWidget);
    expect(find.text('Odustani'), findsOneWidget);
    expect(find.text('Spremi'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Faza 3 — kupaona');
    await tester.tap(find.text('Spremi'));
    await tester.pumpAndSettle();

    expect(capturedName, 'Faza 3 — kupaona.jpg');
    expect(capturedType, 'image/jpeg');
    expect(captured, isNotNull);
    expect(captured!.length, greaterThan(0));
  });

  testWidgets('1.11.0: keeping the suggested name still uploads a .jpg', (tester) async {
    String? capturedName;
    final api = _api((filename, type, bytes) {
      capturedName = filename;
    });

    await tester.pumpWidget(MaterialApp(
        home: _screen(api, cameraPicker: () async => shot())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Slikaj'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spremi')); // keep the suggested name
    await tester.pumpAndSettle();

    expect(capturedName, startsWith('Slika '));
    expect(capturedName, endsWith('.jpg'));
  });

  testWidgets('1.11.0: cancelling the naming dialog uploads nothing', (tester) async {
    Uint8List? captured;
    final api = _api((filename, type, bytes) {
      captured = Uint8List.fromList(bytes);
    });

    await tester.pumpWidget(MaterialApp(
        home: _screen(api, cameraPicker: () async => shot())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Slikaj'));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Odustani'));
    await tester.pumpAndSettle();

    expect(captured, isNull);
    expect(find.text('Naziv fotografije'), findsNothing);
  });

  testWidgets('1.11.0: image list rows and grid cards load the thumbnail endpoint with the token', (tester) async {
    final stateful = MockClient((req) async {
      if (req.url.path == '/api/projects/7/files') {
        return http.Response(
            '[{"id": 42, "name": "Faza 3.jpg", "size": 12345, '
            '"content_type": "image/jpeg", "uploaded_by": "Branko", '
            '"created_at": "2026-09-25T10:00:00Z"}]',
            200);
      }
      return http.Response('{"detail": "nf"}', 404);
    });
    final api = Api('https://x.test', token: 't', client: stateful);

    await tester.pumpWidget(MaterialApp(home: _screen(api)));
    await tester.pumpAndSettle();

    expect(find.text('Faza 3.jpg'), findsOneWidget);
    // Row thumbnail points at the server-side thumb endpoint (token auth).
    expect(
        find.byWidgetPredicate((w) => w is Image && pointsAtThumb(w)),
        findsOneWidget);

    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Faza 3.jpg'), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) => w is Image && pointsAtThumb(w)),
        findsOneWidget);
  });

  testWidgets('1.13.1: deleting files requires confirmation in list and grid views', (tester) async {
    var remaining = <Map<String, dynamic>>[
      {
        'id': 42,
        'name': 'Faza 3.jpg',
        'size': 12345,
        'content_type': 'image/jpeg',
        'uploaded_by': 'Branko',
        'created_at': '2026-09-25T10:00:00Z',
      },
      {
        'id': 43,
        'name': 'Plan.pdf',
        'size': 2048,
        'content_type': 'application/pdf',
        'uploaded_by': 'Branko',
        'created_at': '2026-09-25T10:00:00Z',
      },
    ];
    final deletedIds = <int>[];
    final client = MockClient((req) async {
      if (req.url.path == '/api/projects/7/files' && req.method == 'GET') {
        return http.Response(jsonEncode(remaining), 200);
      }
      if (req.method == 'DELETE' && req.url.path.startsWith('/api/files/')) {
        final id = int.parse(req.url.path.split('/').last);
        deletedIds.add(id);
        remaining.removeWhere((file) => file['id'] == id);
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{"detail":"not found"}', 404);
    });
    final api = Api('https://x.test', token: 't', client: client);

    await tester.pumpWidget(MaterialApp(home: _screen(api)));
    await tester.pumpAndSettle();

    // Cancelling leaves the upload untouched.
    await tester.tap(find.byTooltip('Obriši datoteku').first);
    await tester.pumpAndSettle();
    expect(find.text('Faza 3.jpg'), findsOneWidget);
    await tester.tap(find.text('Odustani'));
    await tester.pumpAndSettle();
    expect(deletedIds, isEmpty);

    // Confirm a list-view deletion.
    await tester.tap(find.byTooltip('Obriši datoteku').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obriši').last);
    await tester.pumpAndSettle();
    expect(deletedIds, [42]);
    expect(find.text('Faza 3.jpg'), findsNothing);
    expect(find.text('Plan.pdf'), findsOneWidget);

    // The grid view exposes the same confirmed delete action.
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Obriši datoteku'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obriši').last);
    await tester.pumpAndSettle();
    expect(deletedIds, [42, 43]);
    expect(find.text('Plan.pdf'), findsNothing);
  });

  testWidgets('1.17.0: renaming a file PATCHes /api/files/{id} from list and grid', (tester) async {
    var files = <Map<String, dynamic>>[
      {
        'id': 42,
        'name': 'Slika 2.10.2026.jpg',
        'size': 12345,
        'content_type': 'image/jpeg',
        'uploaded_by': 'Branko',
        'created_at': '2026-10-02T12:00:00Z',
      },
    ];
    final patched = <String, dynamic>{};
    final client = MockClient((req) async {
      if (req.url.path == '/api/projects/7/files' && req.method == 'GET') {
        return http.Response(jsonEncode(files), 200);
      }
      if (req.method == 'PATCH' && req.url.path.startsWith('/api/files/')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        patched[req.url.path] = body['name'];
        files = [
          for (final f in files)
            if (f['id'] == int.parse(req.url.path.split('/').last))
              {...f, 'name': body['name']}
            else
              f,
        ];
        return http.Response(jsonEncode({'id': 42, 'name': body['name']}), 200);
      }
      return http.Response('{"detail":"not found"}', 404);
    });
    final api = Api('https://x.test', token: 't', client: client);

    await tester.pumpWidget(MaterialApp(home: _screen(api)));
    await tester.pumpAndSettle();

    // The dialog opens pre-filled with the current name.
    await tester.tap(find.byTooltip('Preimenuj datoteku').first);
    await tester.pumpAndSettle();
    expect(find.text('Novi naziv datoteke'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Slika 2.10.2026.jpg');

    // Cancel (blank name) sends nothing.
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Spremi'));
    await tester.pumpAndSettle();
    expect(patched, isEmpty);

    await tester.tap(find.byTooltip('Preimenuj datoteku').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fasada gotova.jpg');
    await tester.tap(find.text('Spremi'));
    await tester.pumpAndSettle();

    expect(patched, {'/api/files/42': 'Fasada gotova.jpg'});
    expect(find.text('Fasada gotova.jpg'), findsOneWidget);
    expect(find.text('Slika 2.10.2026.jpg'), findsNothing);

    // The grid view exposes the same rename action.
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Preimenuj datoteku'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fasada 2.jpg');
    await tester.tap(find.text('Spremi'));
    await tester.pumpAndSettle();

    expect(patched['/api/files/42'], 'Fasada 2.jpg');
    expect(find.text('Fasada 2.jpg'), findsOneWidget);
  });

  test('1.11.0: decodeImageDimensions returns image size', () {
    final dims = decodeImageDimensions(jpegBytes(w: 320, h: 240));
    expect(dims?.$1, 320);
    expect(dims?.$2, 240);
  });

  test('1.11.0: decodeImageDimensions returns null for garbage', () {
    expect(decodeImageDimensions(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });

  test('1.11.0: decodeImageDimensions handles large images (dims reported)', () {
    final dims = decodeImageDimensions(jpegBytes(w: 3200, h: 2400));
    expect(dims?.$1, 3200);
    expect(dims?.$2, 2400);
  });
}
