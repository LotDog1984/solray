import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:solray/api.dart';
import 'package:solray/attrib.dart';
import 'package:solray/screens/board_screen.dart';

/// 1.15.0: attribution badges — pure helper logic plus one widget test proving
/// the board renders the line for tasks that carry the additive fields (older
/// payloads without them must render without errors and without a badge).
void main() {
  group('taskAttributionLine', () {
    test('shows creator, done-by and editor', () {
      final line = taskAttributionLine({
        'created_by': 'Ivan',
        'completed': true,
        'completed_by': 'Marko',
        'edited_by': 'Luka',
      });
      expect(line, '➕ Ivan · ✓ Marko · ✏️ Luka');
    });

    test('hides editor when it repeats the creator', () {
      final line = taskAttributionLine({
        'created_by': 'Ivan',
        'completed': false,
        'completed_by': null,
        'edited_by': 'Ivan',
      });
      expect(line, '➕ Ivan');
    });

    test('no attribution data → null (no badge rendered)', () {
      expect(taskAttributionLine({}), isNull);
      expect(taskAttributionLine({'created_by': null, 'edited_by': null}), isNull);
    });

    test('completed_by hidden while the task is open again', () {
      final line = taskAttributionLine({
        'created_by': 'Ivan',
        'completed': false,
        'completed_by': null,
        'edited_by': 'Marko',
      });
      expect(line, '➕ Ivan · ✏️ Marko');
    });
  });

  group('todoAttributionLine', () {
    test('shows who added and who bought the Stavka', () {
      final line = todoAttributionLine({
        'created_by': 'Ivan',
        'is_done': true,
        'done_by': 'Marko',
        'edited_by': null,
      });
      expect(line, '➕ Ivan · 🛒 Marko');
    });

    test('legacy entry without attribution → null', () {
      expect(todoAttributionLine({'title': 'stari zapis'}), isNull);
    });
  });

  testWidgets('board task cards render the attribution badge', (tester) async {
    final api = Api(
      'https://x.test',
      token: 't',
      client: MockClient((req) async {
        if (req.url.path == '/api/boards/2') {
          return http.Response(
            jsonEncode({
              'id': 2,
              'name': 'B',
              'columns': [
                {
                  'id': 10,
                  'name': 'Col',
                  'position': 0,
                  'tasks': [
                    {
                      'id': 100,
                      'title': 'Zadatak s atribucijom',
                      'completed': true,
                      'created_by': 'Ivan',
                      'completed_by': 'Marko',
                      'edited_by': null,
                      'items': [],
                    },
                    // Legacy task: no attribution fields at all → no badge.
                    {'id': 101, 'title': 'Stari zadatak', 'completed': false, 'items': []},
                  ],
                },
              ],
              'todo_list': {
                'id': 99,
                'entries': [
                  {'id': 7, 'title': 'Ekruv', 'is_done': false, 'created_by': 'Luka'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path == '/api/settings') {
          return http.Response(jsonEncode({'default_todo_list': 'Nabava'}), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{"detail": "not found"}', 404,
            headers: {'content-type': 'application/json'});
      }),
    );

    await tester.pumpWidget(MaterialApp(
      home: BoardScreen(
        api: api,
        boardId: 2,
        boardName: 'B',
        // Capture the sync hook (no real SyncBus): the bus's periodic poll
        // timer would stay pending and fail the test binding's invariant.
        syncListener: (scope, onEvent) {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('➕ Ivan · ✓ Marko'), findsOneWidget);
    expect(find.text('➕ Luka'), findsOneWidget);
  });
}
