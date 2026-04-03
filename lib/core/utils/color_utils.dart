import 'dart:ui';

/// Parse a hex color string (with or without #) to a Color.
/// Returns [fallback] if parsing fails.
Color parseHexColor(String hex, {Color fallback = const Color(0xFF7C4DFF)}) {
  try {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  } catch (_) {
    return fallback;
  }
}
