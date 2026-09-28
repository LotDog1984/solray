// 1.15.0: per-user attribution badges — who created a task/Stavka, who marked
// it done and who edited it last. Pure top-level functions (same pattern as
// `defaultPhotoName` in files_screen.dart) so they are trivially unit-testable
// and shared by the board, To-Do panel and Nabava screens.
//
// The backend sends additive display-name fields:
//   tasks:  created_by / completed_by / edited_by (+ edited_at)
//   entries: created_by / done_by / edited_by (+ edited_at)
// Legacy rows have nulls — the badge line simply disappears.

import 'package:flutter/material.dart';

import 'theme.dart';

String? _joinBadge(List<String> parts) {
  final clean = parts.where((p) => p.isNotEmpty).toList();
  if (clean.isEmpty) return null;
  return clean.join(' · ');
}

/// "➕ Ivan · ✓ Marko · ✏️ Ivan" for a task card, or null when nothing to show.
String? taskAttributionLine(Map<String, dynamic> task) {
  final created = (task['created_by'] as String?)?.trim() ?? '';
  final completedBy = task['completed'] == true ? ((task['completed_by'] as String?)?.trim() ?? '') : '';
  final edited = (task['edited_by'] as String?)?.trim() ?? '';
  // The editor badge is noise when it just repeats another name on the line.
  final showEdited = edited.isNotEmpty && edited != created && edited != completedBy;
  return _joinBadge([
    if (created.isNotEmpty) '➕ $created',
    if (completedBy.isNotEmpty) '✓ $completedBy',
    if (showEdited) '✏️ $edited',
  ]);
}

/// "➕ Ivan · 🛒 Marko · ✏️ Ivan" for a To-Do/Nabava row, or null when empty.
String? todoAttributionLine(Map<String, dynamic> entry) {
  final created = (entry['created_by'] as String?)?.trim() ?? '';
  final doneBy = entry['is_done'] == true ? ((entry['done_by'] as String?)?.trim() ?? '') : '';
  final edited = (entry['edited_by'] as String?)?.trim() ?? '';
  final showEdited = edited.isNotEmpty && edited != created && edited != doneBy;
  return _joinBadge([
    if (created.isNotEmpty) '➕ $created',
    if (doneBy.isNotEmpty) '🛒 $doneBy',
    if (showEdited) '✏️ $edited',
  ]);
}

/// Muted one-line badge widget for cards/rows; returns null when [line] is
/// null so callers can use the `if (...)` collection pattern.
Widget? attributionBadge(String? line, {double fontSize = 11}) {
  if (line == null || line.isEmpty) return null;
  return Text(
    line,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(color: SR.muted, fontSize: fontSize),
  );
}
