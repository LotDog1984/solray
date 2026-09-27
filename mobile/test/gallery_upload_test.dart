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

/// One-element in-memory JPEG standing in for a gallery photo.
Uint8List jpegBytes({int w = 320, int h = 240}) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h), quality: 90));

/// The file-part bytes of a multipart body (private helper duplicated from
/// files_screen_test.dart — library-private top-levels don't cross files).
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

Widget _screen(
  Api api, {
  Future<XFile?> Function()? galleryPicker,
}) =>
    FilesScreen(
      api: api,
      projectId: 7,
      projectName: 'Test',
      syncListener: (_, __) {},
      galleryPicker: galleryPicker,
    );

/// An in-memory XFile standing in for the gallery pick. NOTE: XFile.fromData
/// has no name (XFile.name derives from a path), so the flow correctly falls
/// back to the date default — real gallery picks DO carry names, covered by
/// the defaultPhotoName unit tests below.
XFile _photo(Uint8List bytes) =>
    XFile.fromData(bytes, mimeType: 'image/jpeg');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('defaultPhotoName (1.14.1)', () {
    test('keeps a meaningful gallery file name, forcing .jpg', () {
      expect(defaultPhotoName('uzu_luka_2026.jpeg'), 'uzu_luka_2026.jpg');
      expect(defaultPhotoName('vacation.PNG'), 'vacation.jpg');
      expect(defaultPhotoName('IMG_1234'), 'IMG_1234.jpg');
    });

    test('falls back to the today-date default for meaningless names', () {
      final now = DateTime.now();
      final expected = 'Slika ${now.day}.${now.month}.${now.year}.jpg';
      expect(defaultPhotoName('image.jpg'), expected);
      expect(defaultPhotoName(''), expected);
      expect(defaultPhotoName('   .jpg'), expected);
    });
  });

  testWidgets('1.14.1: three actions — Datoteka, Galerija, Slikaj', (tester) async {
    final api = _api((filename, type, bytes) {});
    await tester.pumpWidget(MaterialApp(home: _screen(api)));
    await tester.pumpAndSettle();

    expect(find.text('Datoteka'), findsOneWidget);
    expect(find.text('Galerija'), findsOneWidget);
    expect(find.text('Slikaj'), findsOneWidget);
  });

  testWidgets('gallery pick flows to the naming dialog and uploads as image/jpeg',
      (tester) async {
    Uint8List? uploaded;
    String? uploadedName;
    String? uploadedType;
    final api = _api((name, type, bytes) {
      uploaded = Uint8List.fromList(bytes);
      uploadedName = name;
      uploadedType = type;
    });

    await tester.pumpWidget(MaterialApp(
      home: _screen(api, galleryPicker: () async => _photo(jpegBytes())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Galerija'));
    await tester.pumpAndSettle();

    // Nameless in-memory pick → date default prefill (matches camera flow).
    final now = DateTime.now();
    expect(find.text('Naziv fotografije'), findsOneWidget);
    expect(find.text('Slika ${now.day}.${now.month}.${now.year}.jpg'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'uz luka');
    await tester.tap(find.text('Spremi'));
    await tester.pumpAndSettle();

    expect(uploadedName, 'uz luka.jpg');
    expect(uploadedType, contains('image/jpeg'));
    expect(uploaded, isNotNull);
  });

  testWidgets('cancelling the name dialog uploads nothing', (tester) async {
    var uploads = 0;
    final api = _api((name, type, bytes) => uploads++);

    await tester.pumpWidget(MaterialApp(
      home: _screen(api, galleryPicker: () async => _photo(jpegBytes())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Galerija'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Odustani'));
    await tester.pumpAndSettle();

    expect(uploads, 0);
  });

  testWidgets('backing out of the picker uploads nothing', (tester) async {
    var uploads = 0;
    final api = _api((name, type, bytes) => uploads++);

    await tester.pumpWidget(MaterialApp(
      home: _screen(api, galleryPicker: () async => null),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Galerija'));
    await tester.pumpAndSettle();

    expect(uploads, 0);
    expect(find.text('Naziv fotografije'), findsNothing);
  });
}
