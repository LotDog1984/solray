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
  Future<XFile?> Function()? galleryPicker,
}) =>
    FilesScreen(
      api: api,
      projectId: 7,
      projectName: 'Test',
      syncListener: syncListener,
      galleryPicker: galleryPicker,
    );

XFile _photo(Uint8List bytes, String name) {
  final file = XFile.fromData(bytes, name: name, mimeType: 'image/jpeg');
  return file;
}

void main() {
  testWidgets('gallery upload keeps the original file name and compresses nothing under 1600px',
      (tester) async {
    Uint8List? uploaded;
    String? uploadedName;
    String? uploadedType;
    final api = _api((name, type, bytes) {
      uploaded = bytes;
      uploadedName = name;
      uploadedType = type;
    });

    final screen = _screen(
      api,
      galleryPicker: () async => _photo(jpegBytes(), 'uzu_luka_2026.jpg'),
    );
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();

    await screen.pickPhotoFromGallery();
    await tester.pumpAndSettle();

    // The naming dialog opens pre-filled with the gallery file's own name.
    expect(find.text('Naziv fotografije'), findsOneWidget);
    expect(find.text('uzu_luka_2026.jpg'), findsOneWidget);
    expect(find.text('Spremi'), findsOneWidget);

    await tester.tap(find.text('Spremi'));
    await tester.pumpAndSettle();

    expect(uploadedName, 'uzu_luka_2026.jpg');
    expect(uploadedType, contains('image/jpeg'));
    expect(uploaded, isNotNull);
  });

  testWidgets('gallery upload of an unnamed photo falls back to today-date default',
      (tester) async {
    String? uploadedName;
    final api = _api((name, type, bytes) => uploadedName = name);

    final screen = _screen(
      api,
      galleryPicker: () async => _photo(jpegBytes(), 'image.jpg'),
    );
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();

    await screen.pickPhotoFromGallery();
    await tester.pumpAndSettle();

    // 'image' is recognized as a meaningless picker name → date default.
    final now = DateTime.now();
    expect(
      find.text('Slika ${now.day}.${now.month}.${now.year}.jpg'),
      findsOneWidget,
    );

    await tester.tap(find.text('Spremi'));
    await tester.pumpAndSettle();
    expect(uploadedName, 'Slika ${now.day}.${now.month}.${now.year}.jpg');
  });

  testWidgets('cancelling the gallery flow uploads nothing', (tester) async {
    var uploads = 0;
    final api = _api((name, type, bytes) => uploads++);

    final screen = _screen(
      api,
      galleryPicker: () async => _photo(jpegBytes(), 'vacation.jpg'),
    );
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();

    await screen.pickPhotoFromGallery();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Odustani'));
    await tester.pumpAndSettle();

    expect(uploads, 0);
  });

  testWidgets('backing out of the picker uploads nothing', (tester) async {
    var uploads = 0;
    final api = _api((name, type, bytes) => uploads++);

    final screen = _screen(api, galleryPicker: () async => null);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();

    await screen.pickPhotoFromGallery();
    await tester.pumpAndSettle();

    expect(uploads, 0);
    expect(find.text('Naziv fotografije'), findsNothing);
  });
}
