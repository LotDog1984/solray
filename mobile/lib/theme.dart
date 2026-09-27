import 'package:flutter/material.dart';

import 'api.dart';

/// My Team theme — "Nebula Glass" (v1.13.0), same design language as the web
/// app: dark "space" canvas, aurora glow, frosted-glass feel, violet/cyan
/// accents. Meanings kept from the classic theme: amber = tagged (@mention),
/// mint/green = done, violet = action.
///
/// The aurora is painted ONCE behind the navigator (see [auroraBackground]),
/// so every Scaffold uses a transparent background and the glow shows through.
/// Static gradients only — no runtime blur — so it stays cheap on old phones.
class SR {
  // Surfaces (matched to the web tokens: glass layers over #0A0C1C)
  static const bg = Color(0xFF0A0C1C); // app canvas
  static const ink = Color(0xFF080A16); // deepest background
  static const panel = Color(0xCC1A1D33); // translucent glass cards
  static const panelDeep = Color(0xFF0E1024); // inputs, nested surfaces
  static const panelSolid = Color(0xFF131731); // menus/popovers
  static const sidebar = Color(0xEB10132A); // translucent app bars / bottom nav
  static const line = Color(0x21FFFFFF); // rgba(255,255,255,.13)
  static const lineHi = Color(0x42FFFFFF);
  static const accentWash = Color(0x388B7BFF);
  static const mentionWash = Color(0x2EFFB03A);
  static const doneWash = Color(0x294ADE80);
  static const columnAccents = <Color>[Color(0xFF8B7BFF), Color(0xFF3EE0F2), Color(0xFFF472B6), Color(0xFF4ADE80)];

  // Accents
  static const accent = Color(0xFF8B7BFF); // violet — action
  static const accentDark = Color(0xFF6D5CF6);
  static const cyan = Color(0xFF3EE0F2); // info
  static const mention = Color(0xFFFFB03A); // amber — tagged tasks
  static const done = Color(0xFF4ADE80); // mint — completed
  static const text = Color(0xFFF5F8FF);
  static const muted = Color(0xFF93A2C6);
  static const muted2 = Color(0xFF6E7DA3);

  static const danger = Color(0xFFE5484D);

  /// Aurora backdrop: four soft color blobs over the space canvas (the mockup's
  /// .app-bg). Painted behind ALL screens via MaterialApp.builder.
  static const Decoration auroraBackground = BoxDecoration(
    color: bg,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0B0E20), Color(0xFF0A0C1C), Color(0xFF0D0A1E)],
    ),
  );

  /// The full aurora widget tree (blobs + subtle vignette). Cheap: pure
  /// gradients, no blur filters.
  static Widget aurora(BuildContext context, Widget? child) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0C0F24), Color(0xFF0A0C1C), Color(0xFF0E0B20)],
              ),
            ),
          ),
        ),
        Positioned(
          left: -140,
          top: -180,
          child: _blob(520, const Color(0x8C6D5CF6)), // violet, 55%
        ),
        Positioned(
          right: -160,
          top: -120,
          child: _blob(460, const Color(0x661FB6CE)), // cyan, 40%
        ),
        Positioned(
          left: -100,
          bottom: -240,
          child: _blob(480, const Color(0x7A4C3CE0)), // deep violet, 48%
        ),
        Positioned(
          right: -120,
          bottom: -200,
          child: _blob(420, const Color(0x4DB84F9E)), // pink, 30%
        ),
        if (child != null) child,
      ],
    );
  }

  static Widget _blob(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
        ),
      ),
    );
  }

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      // Transparent: the aurora painted by [aurora] shows through everywhere.
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: accentDark,
        surface: panel,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
      ),
      cardTheme: const CardTheme(color: panel, elevation: 0, shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: line),
      )),
      dialogTheme: const DialogTheme(backgroundColor: panelSolid, shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      )),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: panelSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelDeep,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: muted2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF0B0D1C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: sidebar,
        indicatorColor: accent.withAlpha(90),
        elevation: 0,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? text : muted2,
              size: 22,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: s.contains(WidgetState.selected) ? text : muted2,
            )),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: cyan,
        linearTrackColor: line,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Color(0xFF0B0D1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: panelSolid,
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
      ),
      dividerColor: line,
    );
  }
}

/// Compact progress ring reused in project and board cards.
class SRProgressRing extends StatelessWidget {
  const SRProgressRing({
    super.key,
    required this.progress,
    required this.label,
    this.size = 46,
    this.strokeWidth = 3.5,
  });

  final double progress;
  final String label;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: strokeWidth,
              backgroundColor: SR.line,
              color: value >= 1 ? SR.done : SR.cyan,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: SR.text)),
        ],
      ),
    );
  }
}

/// Small wrapper so screens can share one Api instance.
class Session {
  Session({required this.api, required this.me, required this.settings});

  final Api api;
  final Map<String, dynamic> me;
  final Map<String, dynamic> settings;

  String get appName => (settings['app_name'] as String?) ?? 'My Team';
  String get ntfyBase => (settings['ntfy_base_url'] as String?) ?? '';
  String get topic => (me['ntfy_topic'] as String?) ?? '';
}
