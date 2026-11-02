import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:solray/api.dart';
import 'package:solray/screens/board_screen.dart';

/// 1.22.0: a project in Arhiva is fully read-only for adds. These tests pin
/// the two mobile controls removed by that change — the "Nova kolona" AppBar
/// button and the To-Do panel's "Dodaj stavku" button — and check the same
/// board keeps both when the project is active.
final Map<String, dynamic> _board = {
  'id': 2,
  'name': 'Arhivirana ploča',
  'columns': [
    {
      'id': 10,
      'name': 'Gotovo',
      'position': 0,
      'tasks': [
        {
          'id': 100,
          'title': 'Farbanje',
          'description': '',
          'completed': true,
          'items': [],
        },
      ],
    },
  ],
  'todo_list': {'id': 99, 'entries': []},
};

Api _api() => Api(
      'https://x.test',
      token: 't',
      client: MockClient((req) async {
        if (req.url.path == '/api/boards/2') {
          return http.Response(jsonEncode(_board), 200,
              headers: {'content-type': 'application/json'});
        }
        if (req.url.path == '/api/settings') {
          return http.Response(
              jsonEncode({'default_todo_list': 'Nabava'}), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{"detail": "not found"}', 404,
            headers: {'content-type': 'application/json'});
      }),
    );

Future<void> _pumpBoard(WidgetTester tester, {required bool archived}) async {
  await tester.pumpWidget(MaterialApp(
    home: BoardScreen(
      api: _api(),
      boardId: 2,
      boardName: 'Arhivirana ploča',
      archived: archived,
      // No real SyncBus in tests — same pattern as the other board suites.
      syncListener: (scope, _) {},
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('archived board hides add-column and Nabava add controls',
      (tester) async {
    await _pumpBoard(tester, archived: true);

    // The archived content itself is still browsable...
    expect(find.text('Farbanje'), findsOneWidget);
    expect(find.textContaining('🗄'), findsOneWidget);
    // ...but nothing can be added on the phone.
    expect(find.byTooltip('Nova kolona'), findsNothing);
    expect(find.text('Dodaj stavku'), findsNothing);
    // The To-Do panel explains why its add button is gone.
    expect(find.text('Nema stavki (Arhiva — samo pregled).'), findsOneWidget);
  });

  testWidgets('active board keeps the add-column and Nabava add controls',
      (tester) async {
    await _pumpBoard(tester, archived: false);

    expect(find.byTooltip('Nova kolona'), findsOneWidget);
    expect(find.text('Dodaj stavku'), findsOneWidget);
    expect(find.text('Nema stavki — dodajte prvu ispod.'), findsOneWidget);
    expect(find.textContaining('🗄'), findsNothing);
  });
}
