import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solray/screens/nabava_screen.dart';

/// Exercises the real NabavaEntryCard (the row the Nabava tab renders) with
/// canned data — no network involved (API paths are covered by backend e2e).
void main() {
  testWidgets('open entry shows title + origin; toggle/delete/open fire', (tester) async {
    var toggled = false;
    var deleted = false;
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NabavaEntryCard(
            entry: const {
              'id': 7,
              'board_id': 3,
              'title': 'Vijci 6x60',
              'is_done': false,
              'project_name': 'Remete',
              'board_name': 'Kuhinja',
            },
            onToggle: (_) async { toggled = true; },
            onDelete: (_) async { deleted = true; },
            onOpen: (_) async { opened = true; },
          ),
        ),
      ),
    );

    expect(find.text('Vijci 6x60'), findsOneWidget);
    expect(find.text('📁 Remete → Kuhinja'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(toggled, isTrue);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(deleted, isTrue);

    await tester.tap(find.text('📁 Remete → Kuhinja'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('done entry renders struck through; empty project omitted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NabavaEntryCard(
            entry: const {
              'id': 8,
              'board_id': 3,
              'title': 'Boja bijela',
              'is_done': true,
              'project_name': '',
              'board_name': 'Spavaća soba',
            },
            onToggle: (_) async {},
            onDelete: (_) async {},
            onOpen: (_) async {},
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Boja bijela'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
    // No project part in the origin chip when project_name is empty
    expect(find.text('📁 Spavaća soba'), findsOneWidget);
  });

  testWidgets('1.9.0: manually added entry shows ✍️ marker, not origin chip', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NabavaEntryCard(
            entry: const {
              'id': 9,
              'board_id': null,
              'title': 'Silikon za kupaonicu',
              'is_done': false,
              'project_name': '',
              'board_name': '',
            },
            onToggle: (_) async {},
            onDelete: (_) async { deleted = true; },
            onOpen: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Silikon za kupaonicu'), findsOneWidget);
    expect(find.text('✍️ Ručno dodano'), findsOneWidget);
    expect(find.textContaining('📁'), findsNothing); // no tappable origin chip
    expect(find.text('📁 Remete → Kuhinja'), findsNothing);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(deleted, isTrue);
  });
}
