import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solray/api.dart';
import 'package:solray/screens/settings_screen.dart';
import 'package:solray/theme.dart';

/// 1.18.0: „Zadane kolone novih ploča" is an editable chip list on both
/// platforms now (the comma-separated text field is gone), and the ntfy topic
/// editor was removed from Postavke.
Map<String, dynamic> _settings({List<String> columns = const ['Za napraviti', 'U radu', 'Gotovo']}) => {
      'app_name': 'My Team',
      'default_columns': columns,
      'default_todo_list': 'Nabava',
      'nabava_group': [],
    };

({Widget widget, List<Map<String, dynamic>> puts}) _harness() {
  SharedPreferences.setMockInitialValues({});
  final puts = <Map<String, dynamic>>[];
  var columns = ['Za napraviti', 'U radu', 'Gotovo'];
  const json = {'content-type': 'application/json; charset=utf-8'};
  final client = MockClient((req) async {
    if (req.url.path == '/api/users' && req.method == 'GET') {
      return http.Response(
          jsonEncode([
            {'id': 1, 'username': 'branko', 'display_name': 'Branko Juriša', 'is_admin': true}
          ]),
          200,
          headers: json);
    }
    if (req.url.path == '/api/settings' && req.method == 'PUT') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      puts.add(body);
      columns = [
        for (final c in (body['default_columns'] as List<dynamic>? ?? [])) c.toString()
      ];
      return http.Response(jsonEncode(_settings(columns: columns)), 200, headers: json);
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
      'is_admin': true,
    },
    settings: _settings(),
  );
  return (
    widget: MaterialApp(home: SettingsScreen(session: session, onChanged: () {})),
    puts: puts,
  );
}

/// The settings screen is a long ListView — a tall viewport keeps every
/// section built, so finders don't depend on the scroll position.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder get _columnCard => find.byKey(const ValueKey('columnEditorCard'));
Finder _columnFields() =>
    find.descendant(of: _columnCard, matching: find.byType(TextField));
List<String> _columnValues(WidgetTester tester) => [
      for (final f in tester.widgetList<TextField>(_columnFields())) f.controller!.text,
    ];
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1.18.0: columns render as editable chips with add and remove', (tester) async {
    _tallView(tester);
    final h = _harness();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    expect(find.text('Zadane kolone novih ploča'), findsOneWidget);
    expect(_columnValues(tester), ['Za napraviti', 'U radu', 'Gotovo']);
    expect(find.textContaining('3 / 20'), findsOneWidget);
    expect(find.byTooltip('Ukloni kolonu'), findsNWidgets(3));

    // Add a fourth column and name it.
    await _tap(tester, find.text('Dodaj novu kolonu'));
    expect(_columnValues(tester), ['Za napraviti', 'U radu', 'Gotovo', '']);
    expect(find.textContaining('4 / 20'), findsOneWidget);
    await tester.enterText(_columnFields().at(3), 'Pregled');
    await tester.pumpAndSettle();

    // Remove the second column — the rest shift up and keep their names.
    await _tap(tester, find.byTooltip('Ukloni kolonu').at(1));
    expect(_columnValues(tester), ['Za napraviti', 'Gotovo', 'Pregled']);

    // Save: the PUT carries the trimmed list next to the other settings.
    await _tap(tester, find.text('Spremi postavke'));
    expect(h.puts.single['default_columns'], ['Za napraviti', 'Gotovo', 'Pregled']);
    expect(h.puts.single['app_name'], 'My Team');
    expect(h.puts.single['default_todo_list'], 'Nabava');
    expect(find.text('Postavke spremljene.'), findsOneWidget);
  });

  testWidgets('1.18.0: a blank column list is refused, trimmed names are saved', (tester) async {
    _tallView(tester);
    final h = _harness();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    // Blank out every name → nothing may be sent.
    for (var i = 0; i < 3; i++) {
      await tester.enterText(_columnFields().at(i), '   ');
    }
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Spremi postavke'));
    expect(h.puts, isEmpty);
    expect(find.text('Potrebna je barem jedna kolona.'), findsOneWidget);

    // Two real names with padding → exactly those two are stored.
    await tester.enterText(_columnFields().at(0), '  Za napraviti  ');
    await tester.enterText(_columnFields().at(1), 'Gotovo');
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Spremi postavke'));
    expect(h.puts.single['default_columns'], ['Za napraviti', 'Gotovo']);
  });

  testWidgets('1.18.0: the ntfy topic editor is gone from Postavke', (tester) async {
    _tallView(tester);
    final h = _harness();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    expect(find.text('Obavijesti (ntfy)'), findsNothing);
    expect(find.text('Vaš ntfy topic'), findsNothing);
    expect(find.text('Provjeri vezu'), findsNothing);
    // The device-notification controls stay.
    expect(find.text('Sistemske obavijesti'), findsOneWidget);
    expect(find.text('Testiraj Google push'), findsOneWidget);
  });
}
