import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:solray/api.dart';
import 'package:solray/screens/board_screen.dart';

/// Board with 6 columns (290px each + 12px margin → ~1800px of content),
/// far wider than the test viewport, so horizontal scrolling is possible.
Map<String, dynamic> _boardPayload() => {
      'id': 2,
      'name': 'Wide board',
      'columns': [
        for (var i = 0; i < 6; i++)
          {
            'id': 10 + i,
            'name': 'Kolona $i',
            'position': i,
            'tasks': [
              {'id': 100 + i, 'title': 'Task u koloni $i', 'completed': false, 'items': []},
            ],
          },
      ],
      'todo_list': {'id': 99, 'entries': []},
    };

Api _api() => Api('https://x.test', token: 't',
    client: MockClient((req) async {
      if (req.url.path == '/api/boards/2') {
        return http.Response(jsonEncode(_boardPayload()), 200,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/api/settings') {
        return http.Response(jsonEncode({'default_todo_list': 'Nabava'}), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{"detail": "not found"}', 404,
          headers: {'content-type': 'application/json'});
    }));

void main() {
  testWidgets('horizontal position survives a silent reload (task add / sync)',
      (tester) async {
    // Capture the sync callback the screen registers — firing it is exactly
    // what happens when the backend broadcast a board change (after a task
    // add from web/another device) or when the user adds a task locally.
    void Function()? fireSync;
    final api = _api();

    await tester.pumpWidget(MaterialApp(
      home: BoardScreen(
        api: api,
        boardId: 2,
        boardName: 'Wide board',
        syncListener: (scope, onEvent) => fireSync = onEvent,
      ),
    ));
    await tester.pumpAndSettle();

    // Fling the board far to the right (towards the last column).
    await tester.fling(find.byType(Scrollable).first, const Offset(-600, 0), 3000);
    await tester.pumpAndSettle();
    final afterFling = _scrollOffset(tester);
    expect(afterFling, greaterThan(300),
        reason: 'board should be scrolled right before the reload');

    // Fire the silent reload (same path as after adding a task).
    fireSync!();
    await tester.pumpAndSettle();

    final afterReload = _scrollOffset(tester);
    expect(afterReload, afterFling,
        reason: 'scroll position must be restored after the reload');
    expect(afterReload, greaterThan(300));
  });
}

double _scrollOffset(WidgetTester tester) {
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
  return scrollable.position.pixels;
}
