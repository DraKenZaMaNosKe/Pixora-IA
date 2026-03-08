import 'dart:math';
import 'package:flutter/material.dart';

class TouchGlowEffect extends StatefulWidget {
  const TouchGlowEffect({
    required this.child,
    this.glowColor = Colors.white,
    this.maxRadius = 80.0,
    super.key,
  });

  final Widget child;
  final Color glowColor;
  final double maxRadius;

  @override
  State<TouchGlowEffect> createState() => _TouchGlowEffectState();
}

class _TouchGlowEffectState extends State<TouchGlowEffect>
    with TickerProviderStateMixin {
  final List<_GlowDot> _dots = [];

  void _onTouch(Offset position) {
    final controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    final dot = _GlowDot(
      position: position,
      controller: controller,
      color: widget.glowColor,
      maxRadius: widget.maxRadius,
    );

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _dots.remove(dot));
        controller.dispose();
      }
    });
    controller.addListener(() {
      if (mounted) setState(() {});
    });

    setState(() => _dots.add(dot));
    controller.forward();
  }

  @override
  void dispose() {
    for (final d in List.of(_dots)) {
      d.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) => _onTouch(d.localPosition),
      onPanUpdate: (d) => _onTouch(d.localPosition),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_dots.isNotEmpty)
            IgnorePointer(
              child: CustomPaint(
                painter: _GlowPainter(_dots),
                size: Size.infinite,
              ),
            ),
        ],
      ),
    );
  }
}

class _GlowDot {
  _GlowDot({
    required this.position,
    required this.controller,
    required this.color,
    required this.maxRadius,
  });

  final Offset position;
  final AnimationController controller;
  final Color color;
  final double maxRadius;
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.dots);
  final List<_GlowDot> dots;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in dots) {
      final progress = d.controller.value;
      final radius = d.maxRadius * progress;
      final opacity = (1.0 - progress) * 0.4;
      if (opacity <= 0) continue;

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            d.color.withOpacity(opacity),
            d.color.withOpacity(opacity * 0.3),
            d.color.withOpacity(0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
          Rect.fromCircle(center: d.position, radius: max(radius, 1)),
        );

      canvas.drawCircle(d.position, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) => true;
}
