/// 1.19.0: clipboard text builders — ONE shared format with the web app
/// (frontend/app.js `buildTaskCopyText` / `buildColumnCopyText` /
/// `buildTodoCopyText`), so a task copied on the phone pastes identically to
/// one copied in the browser:
///   a task   = title + description + checklist ("✓/✗ item" lines);
///   a column = name, an "=" underline, one line per task (✓ done, • open);
///   a list   = same shape for To-Do/Nabava Stavke.
/// Pure functions (no Flutter imports) so they test without widgets.
library;

/// Full text of one task: title, then the description (if any), then the
/// checklist ("Popis:" + ✓/✗ lines) — everything the task holds.
String buildTaskCopyText(Map<String, dynamic> task) {
  var text = task['title'] as String? ?? '';
  final description = task['description'] as String? ?? '';
  if (description.isNotEmpty) text += '\n\n$description';
  final items = List<Map<String, dynamic>>.from(
      (task['items'] as List<dynamic>? ?? []).map((i) => Map<String, dynamic>.from(i as Map)));
  if (items.isNotEmpty) {
    text +=
        '\n\nPopis:\n${items.map((i) => "${(i['is_done'] as bool? ?? false) ? '✓' : '✗'} ${i['title'] ?? ''}").join('\n')}';
  }
  return text;
}

/// All tasks of one kanban column: "NAME\n====\n✓/• task" — empty string when
/// the column has no tasks (callers show a "prazno" snack instead of copying).
String buildColumnCopyText(Map<String, dynamic> column) {
  final name = column['name'] as String? ?? '';
  final tasks = List<Map<String, dynamic>>.from(
      (column['tasks'] as List<dynamic>? ?? []).map((t) => Map<String, dynamic>.from(t as Map)));
  if (tasks.isEmpty) return '';
  final lines = tasks
      .map((t) => "${(t['completed'] as bool? ?? false) ? '✓' : '•'} ${t['title'] ?? ''}")
      .join('\n');
  return '$name\n${'=' * name.length}\n$lines';
}

/// All Stavke of a To-Do / Nabava list — same shape as a column. Empty string
/// when there are no entries.
String buildTodoCopyText(List<Map<String, dynamic>> entries, String listName) {
  final name = listName.isEmpty ? 'Nabava' : listName;
  if (entries.isEmpty) return '';
  final lines = entries
      .map((e) => "${(e['is_done'] as bool? ?? false) ? '✓' : '•'} ${e['title'] ?? ''}")
      .join('\n');
  return '$name\n${'=' * name.length}\n$lines';
}
