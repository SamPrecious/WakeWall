import 'package:flutter/material.dart';

@immutable
// Carries WakeWall's custom colours through Flutter's normal Theme system.
class WakeWallPalette extends ThemeExtension<WakeWallPalette> {
  const WakeWallPalette({
    required this.background,
    required this.surface,
    required this.raisedSurface,
    required this.outline,
    required this.muted,
    required this.teal,
    required this.tealStrong,
    required this.ink,
    required this.danger,
    required this.onSurface,
  });

  final Color background;
  final Color surface;
  final Color raisedSurface;
  final Color outline;
  final Color muted;
  final Color teal;
  final Color tealStrong;
  final Color ink;
  final Color danger;
  final Color onSurface;

  @override
  WakeWallPalette copyWith({
    Color? background,
    Color? surface,
    Color? raisedSurface,
    Color? outline,
    Color? muted,
    Color? teal,
    Color? tealStrong,
    Color? ink,
    Color? danger,
    Color? onSurface,
  }) {
    return WakeWallPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      raisedSurface: raisedSurface ?? this.raisedSurface,
      outline: outline ?? this.outline,
      muted: muted ?? this.muted,
      teal: teal ?? this.teal,
      tealStrong: tealStrong ?? this.tealStrong,
      ink: ink ?? this.ink,
      danger: danger ?? this.danger,
      onSurface: onSurface ?? this.onSurface,
    );
  }

  @override
  WakeWallPalette lerp(ThemeExtension<WakeWallPalette>? other, double t) {
    if (other is! WakeWallPalette) return this;
    return WakeWallPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raisedSurface: Color.lerp(raisedSurface, other.raisedSurface, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
      tealStrong: Color.lerp(tealStrong, other.tealStrong, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
    );
  }
}

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
  static const onSurface = Color(0xFFE3E3E8);

  static const dark = WakeWallPalette(
    background: background,
    surface: surface,
    raisedSurface: raisedSurface,
    outline: outline,
    muted: muted,
    teal: teal,
    tealStrong: tealStrong,
    ink: ink,
    danger: danger,
    onSurface: onSurface,
  );

  static const light = WakeWallPalette(
    background: Color(0xFFF8FAFD),
    surface: Color(0xFFFFFFFF),
    raisedSurface: Color(0xFFEFF3F8),
    outline: Color(0xFFD9DEE7),
    muted: Color(0xFF5F6368),
    teal: Color(0xFF0B57D0),
    tealStrong: Color(0xFF0B57D0),
    ink: Color(0xFFFFFFFF),
    danger: Color(0xFFB3261E),
    onSurface: Color(0xFF202124),
  );

  static const midnight = WakeWallPalette(
    background: Color(0xFF000000),
    surface: Color(0xFF08090B),
    raisedSurface: Color(0xFF121318),
    outline: Color(0xFF2B2F38),
    muted: Color(0xFF747C89),
    teal: Color(0xFF343A46),
    tealStrong: Color(0xFFAAB2BF),
    ink: Color(0xFFC5CBD5),
    danger: Color(0xFFBFA8A8),
    onSurface: Color(0xFFA0A7B3),
  );
}

extension WakeWallPaletteContext on BuildContext {
  WakeWallPalette get wakeWallColors =>
      Theme.of(this).extension<WakeWallPalette>() ?? WakeWallColors.dark;
}

extension WakeWallPaletteStyle on WakeWallPalette {
  bool get isMidnight =>
      background == WakeWallColors.midnight.background &&
      surface == WakeWallColors.midnight.surface &&
      raisedSurface == WakeWallColors.midnight.raisedSurface;
}

abstract final class WakeWallTheme {
  static ThemeData get dark =>
      _build(brightness: Brightness.dark, colors: WakeWallColors.dark);

  static ThemeData get light =>
      _build(brightness: Brightness.light, colors: WakeWallColors.light);

  static ThemeData get midnight =>
      _build(brightness: Brightness.dark, colors: WakeWallColors.midnight);

  static ThemeData _build({
    required Brightness brightness,
    required WakeWallPalette colors,
  }) {
    // Build every theme from the same shape so light/dark/midnight stay aligned.
    final scheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: colors.teal,
            onPrimary: colors.ink,
            surface: colors.surface,
            onSurface: colors.onSurface,
            outline: colors.outline,
            error: colors.danger,
          )
        : ColorScheme.light(
            primary: colors.teal,
            onPrimary: colors.ink,
            surface: colors.surface,
            onSurface: colors.onSurface,
            outline: colors.outline,
            error: colors.danger,
          );

    final textColor = colors.onSurface;
    final textTheme = TextTheme(
      displaySmall: TextStyle(
        color: textColor,
        fontSize: 38,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
      ),
      headlineSmall: TextStyle(color: textColor),
      titleLarge: TextStyle(
        color: textColor,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: textColor,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: textColor, fontSize: 16, height: 1.35),
      bodyMedium: TextStyle(color: textColor, fontSize: 14, height: 1.35),
      bodySmall: TextStyle(color: textColor),
      labelLarge: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: .2,
      ),
      labelSmall: TextStyle(color: textColor),
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      fontFamily: 'sans-serif',
      splashFactory: InkSparkle.splashFactory,
      extensions: [colors],
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: colors.teal, size: 23),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        modalBackgroundColor: colors.surface,
        showDragHandle: true,
        dragHandleColor: colors.outline,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.raisedSurface,
        elevation: 8,
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentTextStyle: TextStyle(
          color: colors.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.teal,
          foregroundColor: colors.ink,
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
          side: BorderSide(color: colors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      dividerColor: colors.outline,
    );
  }
}
