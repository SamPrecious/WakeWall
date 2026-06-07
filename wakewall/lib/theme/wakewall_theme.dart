import 'package:flutter/material.dart';

abstract final class WakeWallColors {
  static const background = Color(0xFF101114);
  static const surface = Color(0xFF1B1C20);
  static const raisedSurface = Color(0xFF25262B);
  static const outline = Color(0xFF3F4148);
  static const muted = Color(0xFFA7A9B0);
  static const teal = Color(0xFFA8C7FA);
  static const tealStrong = Color(0xFF8AB4F8);
  static const ink = Color(0xFF10213A);
  static const danger = Color(0xFFF2B8B5);
}

abstract final class WakeWallTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: WakeWallColors.teal,
      onPrimary: WakeWallColors.ink,
      surface: WakeWallColors.surface,
      onSurface: Color(0xFFE3E3E8),
      outline: WakeWallColors.outline,
      error: WakeWallColors.danger,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: WakeWallColors.background,
      fontFamily: 'sans-serif',
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 38,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.5,
        ),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(fontSize: 16, height: 1.35),
        bodyMedium: TextStyle(fontSize: 14, height: 1.35),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
      ),
      iconTheme: const IconThemeData(color: WakeWallColors.teal, size: 23),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: WakeWallColors.surface,
        modalBackgroundColor: WakeWallColors.surface,
        showDragHandle: true,
        dragHandleColor: WakeWallColors.outline,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: WakeWallColors.raisedSurface,
        elevation: 8,
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentTextStyle: const TextStyle(
          color: Color(0xFFE3E3E8),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: WakeWallColors.teal,
          foregroundColor: WakeWallColors.ink,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: WakeWallColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      dividerColor: WakeWallColors.outline,
    );
  }
}
