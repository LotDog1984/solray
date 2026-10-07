import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:solray/api.dart';
import 'package:solray/screens/board_screen.dart';

/// 1.19.0: the board screen's copy actions — column ⧉ button, task popup
/// "Kopiraj tekst", To-Do panel ⧉ — must write the SAME clipboard text the
/// web app's copy buttons produce (shared format, see copy_text.dart).
///
/// The tests mock the clipboard platform channel (flutter/platform channel
/// `flutter/platform`, Clipboard.setData): without a handler the await inside
/// the app never completes and the test binding hangs forever.
void main() {
  // Last text written by the app under test.
  String? clipboard;
  setUp(() {
    clipboard = null;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.hasStrings') {
        return clipboard != null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  final boardData = {
    'id': 2,
    'name': 'B',
    'columns': [
      {
        'id': 10,
        'name': 'U tijeku',
        'position': 0,
        'tasks': [
          {
            'id': 100,
            'title': 'Farbanje',
            'description': 'Bijela, dva sloja',
            'completed': false,
            'items': [
              {'id': 1, 'title': 'Nakupiti boju', 'is_done': true},
              {'id': 2, 'title': 'Farbanje', 'is_done': false},
            ],
          },
          {'id': 101, 'title': 'Stari zadatak', 'completed': true, 'items': []},
        ],
      },
    ],
    'todo_list': {
      'id': 99,
      'entries': [
        {'id': 7, 'title': 'Silikon', 'is_done': false},
      ],
    },
  };

  Future<void> pumpBoard(WidgetTester tester) async {
    final api = Api(
      'https://x.test',
      token: 't',
      client: MockClient((req) async {
        if (req.url.path == '/api/boards/2') {
          return http.Response(jsonEncode(boardData), 200,
              headers: {'content-type': 'application/json'});
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
        // Capture the sync hook (no real SyncBus) — same pattern as
        // attribution_test.dart.
        syncListener: (scope, onEvent) {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('column copy button copies name + all tasks', (tester) async {
    await pumpBoard(tester);

    await tester.tap(find.byTooltip('Kopiraj sve zadatke kolone'));
    await tester.pump();

    expect(clipboard, 'U tijeku\n========\n• Farbanje\n✓ Stari zadatak');
    expect(find.textContaining('Kolona kopirana'), findsOneWidget);
  });

  testWidgets('task popup "Kopiraj tekst" copies title + description + checklist',
      (tester) async {
    await pumpBoard(tester);

    // Open the task popup menu of the first task card.
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopiraj tekst'));
    await tester.pump();

    expect(clipboard,
        'Farbanje\n\nBijela, dva sloja\n\nPopis:\n✓ Nakupiti boju\n✗ Farbanje');
    expect(find.textContaining('Zadatak kopiran'), findsOneWidget);
  });

  testWidgets('To-Do panel copy button copies the list', (tester) async {
    await pumpBoard(tester);

    await tester.tap(find.byTooltip('Kopiraj cijeli popis'));
    await tester.pump();

    expect(clipboard, 'Nabava\n======\n• Silikon');
    expect(find.textContaining('Popis kopiran'), findsOneWidget);
  });
}
