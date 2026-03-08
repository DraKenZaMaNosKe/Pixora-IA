import 'package:flutter/material.dart';

class PixoraTheme {
  static ThemeData get light => ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C4DFF),
          secondary: Color(0xFF00E5FF),
          background: Color(0xFF050018),
        ),
        scaffoldBackgroundColor: const Color(0xFF050018),
        textTheme: Typography.whiteMountainView,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF0E0626).withOpacity(.9),
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      );
}
