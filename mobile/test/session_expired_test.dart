import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solray/api.dart';
import 'package:solray/screens/home_screen.dart';

http.Response _json(Object body, int status) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// Mock server whose /api/me behaves per the current scenario (the flag is
/// flipped mid-test to simulate the server coming back / rejecting the token).
class _Server {
  _Server();

  bool meExpired = true;
  bool meDown = false;
  int meCalls = 0;

  Future<http.Response> handle(http.Request req) async {
    if (req.url.path == '/api/me') {
      meCalls++;
      if (meDown) return http.Response('boom', 500);
      if (meExpired) {
        return _json({'detail': 'Sesija je istekla'}, 401);
      }
      return _json({
        'id': 1,
        'username': 'branko',
        'display_name': 'Branko',
        'is_admin': true,
      }, 200);
    }
    if (req.url.path == '/api/settings') {
      return _json({'app_name': 'My Team', 'default_todo_list': 'Nabava'}, 200);
    }
    if (req.url.path == '/api/projects') return _json([], 200);
    if (req.url.path == '/api/notifications/unread-count') return _json({'count': 0}, 200);
    if (req.url.path == '/api/auth/status') return _json({'registration_open': false}, 200);
    return _json({'detail': 'nf'}, 404);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1.18.1: expired session at boot lands on the login screen (no dead-end retry)',
      (tester) async {
    final server = _Server()..meExpired = true;
    SharedPreferences.setMockInitialValues({
      'solray_url': 'https://x.test',
      'solray_token': 'dead-token',
    });
    final api = Api('https://x.test', token: 'dead-token', client: MockClient(server.handle));

    await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api)));
    await tester.pumpAndSettle();

    // The dead-end "Sesija je istekla / Pokušaj ponovno" screen must not appear;
    // the app goes straight to the login screen for the same server.
    expect(find.text('Sesija je istekla — prijavite se ponovno.'), findsNothing);
    expect(find.text('Pokušaj ponovno'), findsNothing);
    expect(find.text('Korisničko ime'), findsOneWidget);
    expect(find.text('Prijava'), findsOneWidget);

    // The dead token was cleared, the server URL kept — logging in again goes
    // to the same instance without the user clearing the app's cache.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('solray_token'), isNull);
    expect(prefs.getString('solray_url'), 'https://x.test');
    expect(server.meCalls, 1);
  });

  testWidgets('1.18.1: "Pokušaj ponovno" on a transient error recovers, and a dead token then still reaches login',
      (tester) async {
    final server = _Server()
      ..meDown = true // first boot attempt: server unreachable (HTTP 500)
      ..meExpired = true;
    SharedPreferences.setMockInitialValues({});
    final api = Api('https://x.test', token: 'dead-token', client: MockClient(server.handle));

    await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api)));
    await tester.pumpAndSettle();

    // Generic failure → the retry screen, exactly as before.
    expect(find.text('Pokušaj ponovno'), findsOneWidget);

    // Retry while the server is back but the stored token has expired —
    // the button used to loop forever here (the reported bug).
    server.meDown = false;
    await tester.tap(find.text('Pokušaj ponovno'));
    await tester.pumpAndSettle();

    expect(find.text('Korisničko ime'), findsOneWidget);
    expect(find.text('Prijava'), findsOneWidget);
    expect(find.text('Pokušaj ponovno'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('solray_token'), isNull);
    expect(server.meCalls, 2);
  });

  testWidgets('1.18.1: a non-auth error keeps the retry screen (generic retry unchanged)',
      (tester) async {
    final server = _Server()
      ..meDown = true
      ..meExpired = false;
    SharedPreferences.setMockInitialValues({});
    final api = Api('https://x.test', token: 't', client: MockClient(server.handle));

    await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Pokušaj ponovno'), findsOneWidget);

    await tester.tap(find.text('Pokušaj ponovno'));
    await tester.pumpAndSettle();

    // Still down → still the retry screen, no login redirect.
    expect(find.text('Pokušaj ponovno'), findsOneWidget);
    expect(find.text('Korisničko ime'), findsNothing);
    expect(server.meCalls, 2);
  });
}
