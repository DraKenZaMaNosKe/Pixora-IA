import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const _primary = Color(0xFF7C4DFF);
  static const _secondary = Color(0xFF00E5FF);
  static const _background = Color(0xFF0A0A0F);
  static const _surface = Color(0xFF141420);
  static const _card = Color(0xFF1A1A2E);

  static const _fontFamily = 'SF Pro Display';

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: _primary,
          secondary: _secondary,
          surface: _surface,
        ),
        scaffoldBackgroundColor: _background,
        fontFamily: _fontFamily,
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: _fontFamily,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        cardTheme: CardTheme(
          color: _card,
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _surface,
          selectedColor: _primary,
          labelStyle: const TextStyle(fontFamily: _fontFamily, fontSize: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: _background,
          selectedItemColor: _primary,
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
        ),
      );
}
