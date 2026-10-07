import 'package:flutter_test/flutter_test.dart';

import 'package:solray/copy_text.dart';

/// 1.19.0: the clipboard builders must produce the exact same text as the web
/// app's builders (shared format) — title + description + checklist for a
/// task, "NAME\n====\n✓/• rows" for columns and To-Do lists.
void main() {
  group('buildTaskCopyText', () {
    test('title only', () {
      expect(buildTaskCopyText({'title': 'Slijeđenje ploče'}), 'Slijeđenje ploče');
    });

    test('title + description', () {
      final text = buildTaskCopyText({'title': 'Farbanje', 'description': 'Bijela, dva sloja'});
      expect(text, 'Farbanje\n\nBijela, dva sloja');
    });

    test('full task with checklist (✓/✗ lines)', () {
      final text = buildTaskCopyText({
        'title': 'Kupovina',
        'description': 'Za kuhinju',
        'items': [
          {'title': 'Vijci 6x60', 'is_done': true},
          {'title': 'Šarke', 'is_done': false},
        ],
      });
      expect(text, 'Kupovina\n\nZa kuhinju\n\nPopis:\n✓ Vijci 6x60\n✗ Šarke');
    });

    test('empty description adds no blank line', () {
      expect(buildTaskCopyText({'title': 'X', 'description': ''}), 'X');
    });
  });

  group('buildColumnCopyText', () {
    test('named column with tasks (✓ done, • open)', () {
      final text = buildColumnCopyText({
        'name': 'U tijeku',
        'tasks': [
          {'title': 'Zadatak 1', 'completed': false},
          {'title': 'Zadatak 2', 'completed': true},
        ],
      });
      expect(text, 'U tijeku\n========\n• Zadatak 1\n✓ Zadatak 2');
    });

    test('empty column → empty string (caller shows a hint, copies nothing)', () {
      expect(buildColumnCopyText({'name': 'Gotovo', 'tasks': []}), '');
    });
  });

  group('buildTodoCopyText', () {
    test('todo list with mixed entries', () {
      final text = buildTodoCopyText([
        {'title': 'Silikon', 'is_done': false},
        {'title': 'Boja', 'is_done': true},
      ], 'Nabava');
      expect(text, 'Nabava\n======\n• Silikon\n✓ Boja');
    });

    test('empty list → empty string', () {
      expect(buildTodoCopyText([], 'Nabava'), '');
    });

    test('blank list name falls back to Nabava', () {
      final text = buildTodoCopyText([
        {'title': 'X', 'is_done': false},
      ], '');
      expect(text.startsWith('Nabava\n'), isTrue);
    });
  });
}
