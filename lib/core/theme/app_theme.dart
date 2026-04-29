import 'package:flutter/material.dart';

import '../design/hud_tokens.dart';

/// App-level theme wired to [HudTokens] / [HudTheme].
///
/// Any widget can grab HUD colors via `context.hud.accent`, etc.
class AppTheme {
  AppTheme._();

  static ThemeData get night => _buildTheme(HudTheme.night);
  static ThemeData get iosWhite => _buildTheme(HudTheme.iosWhite);

  /// Back-compat alias so existing code referencing `AppTheme.dark` keeps working
  /// during the incremental migration to HUD.
  static ThemeData get dark => night;

  /// Build a ThemeData from any HudTheme — used by ThemeService at the
  /// MaterialApp root to swap themes live.
  static ThemeData forHud(HudTheme h) => _buildTheme(h);

  static ThemeData _buildTheme(HudTheme h) {
    return ThemeData(
      brightness: h.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: h.bg,
      colorScheme: ColorScheme(
        brightness: h.isDark ? Brightness.dark : Brightness.light,
        primary: h.accent,
        onPrimary: Colors.white,
        secondary: h.accent2,
        onSecondary: Colors.black,
        surface: h.surface,
        onSurface: h.text,
        error: h.accent,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: h.bg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: HudTokens.display(
          size: 18,
          weight: FontWeight.w900,
          color: h.text,
          letterSpacing: 0.03,
        ),
        iconTheme: IconThemeData(color: h.text),
      ),
      cardTheme: CardThemeData(
        color: h.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(HudTokens.rSmall)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: h.surface,
        selectedColor: h.accent,
        labelStyle: HudTokens.mono(size: 11, color: h.text, letterSpacing: 0.1),
        secondaryLabelStyle: HudTokens.mono(
          size: 11,
          weight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.1,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(HudTokens.rChip)),
        ),
        side: BorderSide(color: h.divider, width: 1),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: h.bg,
        selectedItemColor: h.accent,
        unselectedItemColor: h.textDim,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: HudTokens.mono(
            size: 9, weight: FontWeight.w700, letterSpacing: 0.1),
        unselectedLabelStyle: HudTokens.mono(
            size: 9, weight: FontWeight.w500, letterSpacing: 0.1),
      ),
      textTheme: TextTheme(
        headlineLarge: HudTokens.display(size: 30, color: h.text),
        headlineMedium: HudTokens.display(size: 22, color: h.text),
        titleLarge:
            HudTokens.display(size: 16, color: h.text, letterSpacing: 0.04),
        bodyLarge: HudTokens.body(size: 15, color: h.text),
        bodyMedium: HudTokens.body(size: 13, color: h.text),
        bodySmall: HudTokens.mono(size: 11, color: h.textDim),
        labelSmall:
            HudTokens.mono(size: 10, color: h.textDim, letterSpacing: 0.15),
      ),
      dividerTheme: DividerThemeData(color: h.divider, thickness: 1, space: 1),
      extensions: <ThemeExtension<dynamic>>[h],
    );
  }
}
