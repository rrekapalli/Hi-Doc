import 'package:flutter/material.dart';

class AppTheme {
  // Core palette
  static const Color primary = Color(0xFF0B6EF6);
  static const Color primaryAccent = Color(0xFF3B8CFF);
  static const Color primarySoft = Color(0xFFE2F0FF);
  static const Color bg = Color(0xFFF7FAFF);
  static const Color surfaceBorder = Color(0xFFDBE5F5);
  static const Color textColor = Color(0xFF142033);
  static const Color textSoft = Color(0xFF4D5B70);
  static const Color line = Color(0xFFE2E9F3);

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      secondary: primaryAccent,
      surface: Colors.white,
  // background deprecated; keep scaffoldBackgroundColor manually set
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent, // we paint gradient manually
      textTheme: base.textTheme.apply(
        bodyColor: textColor,
        displayColor: textColor,
      ),
      dividerTheme: DividerThemeData(
        color: line,
        thickness: 1,
        space: 32,
      ),
      cardTheme: const CardThemeData(
        elevation: 1,
        margin: EdgeInsets.all(8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: _roundedInputBorder(),
        enabledBorder: _roundedInputBorder(),
        focusedBorder: _roundedInputBorder(color: primary, width: 1.6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          elevation: 2,
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ).merge(ButtonStyle(
          overlayColor: WidgetStateProperty.all(primaryAccent.withValues(alpha: .12)),
          shadowColor: WidgetStateProperty.all(Colors.black.withValues(alpha: .20)),
        )),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          backgroundColor: primarySoft,
          foregroundColor: primary,
          side: BorderSide(color: primarySoft.darken(0.12)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: primarySoft,
        selectedColor: primary,
        labelStyle: const TextStyle(color: textColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: surfaceBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(10),
        radius: const Radius.circular(20),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? const Color(0xFFA9C4E2)
              : const Color(0xFFC2D5EB),
        ),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        minThumbLength: 48,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
  backgroundColor: Colors.white.withValues(alpha: .70),
        surfaceTintColor: Colors.white,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
        foregroundColor: textColor,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: primarySoft,
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primary : textSoft,
            letterSpacing: .1,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? primary : textSoft,
          );
        }),
      ),
    );
  }

  static OutlineInputBorder _roundedInputBorder({Color? color, double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color ?? line, width: width),
    );
  }
}

// Small color extension helper.
extension _ColorUtils on Color {
  Color darken([double amount = .1]) {
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}