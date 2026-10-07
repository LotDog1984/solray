import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:solray/api.dart';
import 'package:solray/screens/nabava_screen.dart';

/// 1.18.2 regression test: ticking (or deleting) a MANUALLY added Nabava item
/// used to PATCH "/api/boards/null/todo/{id}" → HTTP 422, so checkboxes on the
/// global list were dead. Manual entries must go to /api/nabava/items/{id}
/// (same branch the web app takes); board entries keep the board route.
void main() {
  /// Pumps the real NabavaTab against a canned backend and records every
  /// request as "METHOD body" keyed by URL path.
  Future<Map<String, String>> pumpTab(
    WidgetTester tester, {
    required List<Map<String, dynamic>> entries,
  }) async {
    final calls = <String, String>{};
    final client = MockClient((req) async {
      calls[req.url.path] = '${req.method} ${req.body}';
      if (req.method == 'GET' && req.url.path == '/api/nabava') {
        return http.Response(
            jsonEncode({'name': 'Nabava', 'entries': entries}), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'ok': true}), 200,
          headers: {'content-type': 'application/json'});
    });
    final api = Api('https://x.test', token: 't', client: client);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: NabavaTab(api: api))));
    await tester.pumpAndSettle();
    return calls;
  }

  Map<String, dynamic> entry(Map<String, dynamic> extra) => {
        'id': 9,
        'title': 'Silikon za kupaonicu',
        'is_done': false,
        'project_name': '',
        'board_name': '',
        ...extra,
      };

  testWidgets('tick on a manual entry hits /api/nabava/items/{id} (no 422)',
      (tester) async {
    final calls = await pumpTab(tester,
        entries: [entry({'board_id': null})]);
    expect(calls['/api/nabava'], startsWith('GET')); // body {} is always present
    calls.clear();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(calls, hasLength(2)); // PATCH + refetch
    expect(calls['/api/nabava/items/9'], 'PATCH {"is_done":true}');
  });

  testWidgets('tick on a board entry keeps the board-scoped route',
      (tester) async {
    final calls = await pumpTab(tester, entries: [
      entry({
        'board_id': 3,
        'project_name': 'Remete',
        'board_name': 'Kuhinja',
      }),
    ]);
    calls.clear();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(calls, hasLength(2)); // PATCH + refetch
    expect(calls['/api/boards/3/todo/9'], contains('PATCH'));
    expect(calls['/api/boards/3/todo/9'], contains('"is_done":true'));
  });

  testWidgets('delete on a manual entry hits /api/nabava/items/{id}',
      (tester) async {
    final calls = await pumpTab(tester,
        entries: [entry({'board_id': null})]);
    calls.clear();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(calls, hasLength(2)); // DELETE + refetch
    expect(calls['/api/nabava/items/9'], 'DELETE {}');
  });

  testWidgets('rename keeps the correct route for both entry kinds',
      (tester) async {
    final calls = await pumpTab(tester, entries: [
      entry({'board_id': null, 'id': 9}),
      entry({
        'board_id': 3,
        'id': 10,
        'title': 'Vijci 6x60',
        'project_name': 'Remete',
        'board_name': 'Kuhinja',
      }),
    ]);
    calls.clear();

    // Rename the manual row (id 9) via its edit pencil.
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Silikon crni');
    await tester.tap(find.text('Spremi'));
    await tester.pumpAndSettle();
    expect(calls['/api/nabava/items/9'], contains('PATCH'));

    // Rename the board row (id 10) — the list reloaded in between, so the
    // first row is the manual one again; take the second pencil.
    calls.clear();
    await tester.tap(find.byIcon(Icons.edit_outlined).at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Vijci 8x80');
    await tester.tap(find.text('Spremi'));
    await tester.pumpAndSettle();
    expect(calls['/api/boards/3/todo/10'], contains('PATCH'));
  });
}
