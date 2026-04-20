import 'package:flutter/material.dart';

/// Cuts two opposite corners diagonally — the Gamer HUD signature shape.
/// Used on hero panels, cards, and buttons.
///
/// CSS equivalent:
///   clip-path: polygon(0 0, calc(100% - C) 0, 100% C, 100% 100%, C 100%, 0 calc(100% - C));
class CornerCutClipper extends CustomClipper<Path> {
  const CornerCutClipper({this.cut = 14});

  final double cut;

  @override
  Path getClip(Size size) {
    final p = Path();
    p.moveTo(0, 0);
    p.lineTo(size.width - cut, 0);
    p.lineTo(size.width, cut);
    p.lineTo(size.width, size.height);
    p.lineTo(cut, size.height);
    p.lineTo(0, size.height - cut);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant CornerCutClipper old) => old.cut != cut;
}

/// Paints a 1-2px border following the corner-cut outline. Useful when we need
/// both a clipped fill AND a visible angular stroke (accent border).
class CornerCutBorderPainter extends CustomPainter {
  const CornerCutBorderPainter({
    required this.color,
    this.cut = 14,
    this.strokeWidth = 2,
  });

  final Color color;
  final double cut;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.miter;
    final p = Path();
    final inset = strokeWidth / 2;
    p.moveTo(0, inset);
    p.lineTo(size.width - cut, inset);
    p.lineTo(size.width - inset, cut);
    p.lineTo(size.width - inset, size.height - inset);
    p.lineTo(cut, size.height - inset);
    p.lineTo(inset, size.height - cut);
    p.close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant CornerCutBorderPainter old) =>
      old.color != color || old.cut != cut || old.strokeWidth != strokeWidth;
}

/// Paints subtle horizontal scan-lines over the widget — evokes a CRT / HUD feel
/// without becoming distracting. Uses the current theme's text color at ~1.5% opacity.
class ScanLinesPainter extends CustomPainter {
  const ScanLinesPainter({required this.color, this.spacing = 3});

  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.015);
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant ScanLinesPainter old) =>
      old.color != color || old.spacing != spacing;
}
