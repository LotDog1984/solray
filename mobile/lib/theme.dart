import 'package:flutter/material.dart';

import 'api.dart';

/// SolRay theme — same palette as the web app:
/// dark-blue sidebar / light-blue content / pink-purple buttons / white text.
class SR {
  static const bg = Color(0xFF1E293B); // content background
  static const panel = Color(0xFF283548); // cards
  static const panelDeep = Color(0xFF1E2A3F); // inputs, nested
  static const sidebar = Color(0xFF0F172A); // dark blue
  static const accent = Color(0xFFA78BFA); // pink/purple buttons
  static const accentDark = Color(0xFF8B5CF6);
  static const mention = Color(0xFFF59E0B); // orange = tagged tasks
  static const done = Color(0xFF22C55E); // green = completed
  static const text = Colors.white;
  static const muted = Color(0xFFB6C2D4);
  static const line = Color(0x24FFFFFF);

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: accentDark,
        surface: panel,
        error: const Color(0xFFDC2626),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: sidebar,
        foregroundColor: text,
        elevation: 0,
      ),
      cardTheme: const CardTheme(color: panelDeep, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelDeep,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: line),
        ),
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: text, side: const BorderSide(color: line)),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: text),
        bodySmall: TextStyle(color: muted),
        titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600),
        headlineSmall: TextStyle(color: text, fontWeight: FontWeight.w700),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? done : Colors.transparent),
        side: const BorderSide(color: muted),
      ),
      dividerColor: line,
    );
  }
}

/// Small wrapper so screens can share one Api instance.
class Session {
  Session({required this.api, required this.me, required this.settings});

  final Api api;
  final Map<String, dynamic> me;
  final Map<String, dynamic> settings;

  String get appName => (settings['app_name'] as String?) ?? 'SolRay';
  String get ntfyBase => (settings['ntfy_base_url'] as String?) ?? '';
  String get topic => (me['ntfy_topic'] as String?) ?? '';
}
