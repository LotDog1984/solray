import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:solray/api.dart';
import 'package:solray/screens/board_screen.dart';
import 'package:solray/screens/boards_screen.dart';
import 'package:solray/screens/projects_screen.dart';
import 'package:solray/theme.dart';

final List<Map<String, dynamic>> _projects = [
  {
    'id': 1,
    'name': 'Nebula project',
    'board_count': 1,
    'task_count': 3,
    'open_task_count': 2,
    'completed_task_count': 1,
    'boards': [
      {
        'id': 2,
        'name': 'Nebula board',
        'project_id': 1,
        'task_count': 3,
        'open_task_count': 2,
        'completed_task_count': 1,
      },
    ],
  },
];

Api _api() => Api(
      'https://example.test',
      token: 'test-token',
      client: MockClient((request) async {
        if (request.url.path == '/api/projects') {
          return http.Response(
            jsonEncode(_projects),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/boards/2') {
          return http.Response(
            jsonEncode({
              'id': 2,
              'name': 'Nebula board',
              'columns': [
                {
                  'id': 3,
                  'name': 'Open',
                  'position': 0,
                  'tasks': [
                    {
                      'id': 4,
                      'title': 'Do work',
                      'completed': false,
                      'items': []
                    },
                    {
                      'id': 5,
                      'title': 'Finish work',
                      'completed': true,
                      'items': []
                    },
                  ],
                },
              ],
              'todo_list': {'id': 6, 'entries': []},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/me') {
          return http.Response(
            jsonEncode({
              'id': 1,
              'username': 'test',
              'display_name': 'Test',
              'is_admin': false
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/settings') {
          return http.Response(
            jsonEncode({'default_todo_list': 'Nabava'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404,
            headers: {'content-type': 'application/json'});
      }),
    );

void main() {
  testWidgets('project card shows board and workload counts with progress ring',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: ProjectsScreen(api: _api())));
    await tester.pumpAndSettle();

    expect(find.text('Nebula project'), findsOneWidget);
    expect(find.text('1 ploče  ·  2 otvoreno'), findsOneWidget);
    expect(find.text('3 zadataka ukupno'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.byType(SRProgressRing), findsOneWidget);
  });

  testWidgets('board list shows open and total task counts with progress ring',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BoardsScreen(
          api: _api(), projectId: 1, projectName: 'Nebula project'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 ploče'), findsOneWidget);
    expect(find.text('2 otvoreno'), findsOneWidget);
    expect(find.text('2 otvoreno  ·  3 zadataka'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.byType(SRProgressRing), findsOneWidget);
  });

  testWidgets('board hero displays the project and task completion counts',
      (tester) async {
    final api = _api();
    String? syncScope;

    await tester.pumpWidget(MaterialApp(
      home: BoardScreen(
        api: api,
        boardId: 2,
        boardName: 'Nebula board',
        projects: _projects,
        syncListener: (scope, _) => syncScope = scope,
      ),
    ));
    await tester.pumpAndSettle();

    expect(syncScope, 'board:2');
    expect(
        find.text(
            'Nebula project  ·  1 otvoreno  ·  2 zadataka  ·  50% gotovo'),
        findsOneWidget);
    expect(find.text('Do work'), findsOneWidget);
  });

  testWidgets('progress ring clamps progress to its supported range',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SRProgressRing(progress: 1.5, label: '150%'),
      ),
    ));
    expect(
      tester
          .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator))
          .value,
      1.0,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SRProgressRing(progress: -0.5, label: '-50%'),
      ),
    ));
    expect(
      tester
          .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator))
          .value,
      0.0,
    );
  });
}
