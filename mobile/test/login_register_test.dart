import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solray/screens/login_screen.dart';

/// 1.17.0: the phone can now do what the web app could only do on a desktop —
/// register the FIRST user (the admin) of a fresh, empty instance.
Future<void> _pump(WidgetTester tester, MockClient client) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(MaterialApp(
    home: LoginScreen(baseUrl: 'https://x.test', client: client),
  ));
  await tester.pumpAndSettle();
}

http.Response _json(Object body, int status) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1.17.0: a configured instance offers no registration link', (tester) async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/auth/status') {
        return _json({'registration_open': false}, 200);
      }
      return _json({'detail': 'nf'}, 404);
    });

    await _pump(tester, client);

    expect(find.text('Prijava'), findsOneWidget);
    expect(find.text('Nova instanca? Registriraj administratora'), findsNothing);
    expect(find.text('Registriraj se i uđi'), findsNothing);
    expect(find.text('Puno ime'), findsNothing);
  });

  testWidgets('1.17.0: an empty instance offers registration and posts the right body',
      (tester) async {
    Map<String, dynamic>? registerBody;
    final client = MockClient((req) async {
      if (req.url.path == '/api/auth/status') {
        return _json({'registration_open': true}, 200);
      }
      if (req.url.path == '/api/auth/register') {
        registerBody = jsonDecode(req.body) as Map<String, dynamic>;
        // The server refuses once a user exists — the screen must say why.
        return _json({'detail': 'Registracija je zabranjena'}, 403);
      }
      return _json({'detail': 'nf'}, 404);
    });

    await _pump(tester, client);

    expect(find.text('Nova instanca? Registriraj administratora'), findsOneWidget);
    expect(find.text('Puno ime'), findsNothing);

    await tester.tap(find.text('Nova instanca? Registriraj administratora'));
    await tester.pumpAndSettle();

    expect(find.text('Puno ime'), findsOneWidget);
    expect(find.text('Registriraj se i uđi'), findsOneWidget);

    // Field order in register mode: username, display name, password.
    await tester.enterText(find.byType(TextField).at(0), 'Branko');
    await tester.enterText(find.byType(TextField).at(1), 'Branko Juriša');
    await tester.enterText(find.byType(TextField).at(2), 'tajna12345');
    await tester.tap(find.text('Registriraj se i uđi'));
    await tester.pumpAndSettle();

    // The username is normalised the way the backend (and the web form) wants.
    expect(registerBody, {
      'username': 'branko',
      'display_name': 'Branko Juriša',
      'password': 'tajna12345',
    });
    expect(find.text('Registracija je zabranjena'), findsOneWidget);

    // Toggling back returns to the plain login form.
    await tester.tap(find.text('Natrag na prijavu'));
    await tester.pumpAndSettle();
    expect(find.text('Prijava'), findsOneWidget);
    expect(find.text('Puno ime'), findsNothing);
  });
}
