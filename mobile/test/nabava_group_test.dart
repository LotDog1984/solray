import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solray/api.dart';
import 'package:solray/screens/settings_screen.dart';
import 'package:solray/theme.dart';

/// 1.17.0: Postavke → „Nabava grupa" — the mobile twin of the web admin panel
/// that decides who receives the „🔔 Pošalji obavijest" notify.
Map<String, dynamic> _settings({List<int> group = const []}) => {
      'app_name': 'My Team',
      'default_columns': ['Backlog', 'U tijeku', 'Gotovo'],
      'default_todo_list': 'Nabava',
      'nabava_group': group,
    };

const _users = [
  {'id': 1, 'username': 'branko', 'display_name': 'Branko Juriša', 'is_admin': true},
  {'id': 2, 'username': 'ivana', 'display_name': 'Ivana', 'is_admin': false},
];

/// SettingsScreen wired to a MockClient that remembers the settings PUTs.
({Widget widget, List<Map<String, dynamic>> puts}) _harness({
  required List<int> group,
  bool admin = true,
}) {
  SharedPreferences.setMockInitialValues({});
  final puts = <Map<String, dynamic>>[];
  var current = group;
  // charset=utf-8 matters: without it http falls back to latin1 and the
  // Croatian names ("Branko Juriša") fail to decode.
  const json = {'content-type': 'application/json; charset=utf-8'};
  final client = MockClient((req) async {
    if (req.url.path == '/api/users' && req.method == 'GET') {
      return http.Response(jsonEncode(_users), 200, headers: json);
    }
    if (req.url.path == '/api/settings' && req.method == 'PUT') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      puts.add(body);
      current = [
        for (final id in (body['nabava_group'] as List<dynamic>? ?? [])) (id as num).toInt(),
      ];
      return http.Response(jsonEncode(_settings(group: current)), 200, headers: json);
    }
    return http.Response('{"detail":"not found"}', 404, headers: json);
  });
  final api = Api('https://x.test', token: 't', client: client);
  final session = Session(
    api: api,
    me: {
      'id': 1,
      'username': 'branko',
      'display_name': 'Branko Juriša',
      'is_admin': admin,
      'ntfy_topic': '',
    },
    settings: _settings(group: group),
  );
  return (
    widget: MaterialApp(home: SettingsScreen(session: session, onChanged: () {})),
    puts: puts,
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Names appear in several cards (account, group, the users list), so member
/// assertions are scoped to the group card itself.
Finder _inGroupCard(Finder matching) => find.descendant(
    of: find.byKey(const ValueKey('nabavaGroupCard')), matching: matching);

/// The settings screen is a long ListView — a tall viewport keeps every
/// section built, so finders don't depend on the scroll position.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1.17.0: admin sees the group members and can remove one', (tester) async {
    _tallView(tester);
    final h = _harness(group: [2]);
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    expect(find.text('Nabava grupa'), findsOneWidget);
    expect(_inGroupCard(find.text('Ivana')), findsOneWidget);
    expect(_inGroupCard(find.text('@ivana')), findsOneWidget);

    await _tapVisible(tester, find.byTooltip('Ukloni iz grupe').first);

    expect(h.puts.single['nabava_group'], isEmpty);
    // The API needs the (required) app name on every settings write — the
    // SAVED one, never whatever is currently typed in the form above.
    expect(h.puts.single['app_name'], 'My Team');
    expect(
        find.text('Grupa je prazna — nitko neće primiti obavijest dok ne dodate korisnike.'),
        findsOneWidget);
  });

  testWidgets('1.17.0: admin adds a user to the group through the picker', (tester) async {
    _tallView(tester);
    final h = _harness(group: [1]);
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Dodaj u grupu'));

    // The picker offers only users who are not in the group yet (the account
    // card above shows the admin's own name, so scope the search to the dialog).
    expect(find.text('Dodaj u Nabava grupu'), findsOneWidget);
    expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Ivana')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Branko Juriša')),
        findsNothing);

    // The users list further down also holds an "Ivana" — tap the dialog's.
    await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Ivana')));
    await tester.pumpAndSettle();

    expect(h.puts.single['nabava_group'], [1, 2]);
    // The saved response is what the list renders (server is the truth).
    expect(_inGroupCard(find.text('Ivana')), findsOneWidget);
  });

  testWidgets('1.17.0: the group picker says so when everybody is already in', (tester) async {
    _tallView(tester);
    final h = _harness(group: [1, 2]);
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    // Both users are listed as members of the group card.
    expect(_inGroupCard(find.text('Branko Juriša')), findsOneWidget);
    expect(_inGroupCard(find.text('Ivana')), findsOneWidget);

    await _tapVisible(tester, find.text('Dodaj u grupu'));

    expect(find.text('Svi su korisnici već u Nabava grupi.'), findsOneWidget);
    expect(h.puts, isEmpty);
  });

  testWidgets('1.17.0: non-admins never see the group section', (tester) async {
    _tallView(tester);
    final h = _harness(group: [2], admin: false);
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    expect(find.text('Nabava grupa'), findsNothing);
    expect(find.text('Dodaj u grupu'), findsNothing);
  });
}
