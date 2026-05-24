import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Aurora Borealis Ring loading indicator.
///
/// Vertical capsule that fills bottom-up with an animated aurora gradient
/// (purple → cyan → green → gold) plus drifting particles. Used as the
/// placeholder while wallpaper images download from Supabase Storage.
///
/// Concept #02 from `docs/design/pixora_wallpaper_loading_microinteractions.html`,
/// chosen by Eduardo 2026-05-09.
class AuroraLoadingIndicator extends StatefulWidget {
  const AuroraLoadingIndicator({
    super.key,
    this.capsuleWidth = 60,
    this.capsuleHeight = 280,
    this.cycleDuration = const Duration(milliseconds: 4500),
  });

  /// Logical width of the capsule.
  final double capsuleWidth;

  /// Logical height of the capsule.
  final double capsuleHeight;

  /// Total animation cycle: 4s ramp + 0.5s hold + reset.
  final Duration cycleDuration;

  @override
  State<AuroraLoadingIndicator> createState() => _AuroraLoadingIndicatorState();
}

class _AuroraLoadingIndicatorState extends State<AuroraLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final math.Random _rng = math.Random(42);

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.cycleDuration)
          ..repeat();
    _particles = List.generate(
        14,
        (i) =>
            _Particle.random(_rng, widget.capsuleWidth, widget.capsuleHeight));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: widget.capsuleWidth,
        height: widget.capsuleHeight,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            // 4s ramp + 0.5s hold inside the 4.5s cycle
            const rampPortion = 4000 / 4500;
            final progress = t < rampPortion ? (t / rampPortion) : 1.0;
            // Wall-clock seconds for particle / wave motion
            final wallClock =
                _controller.lastElapsedDuration?.inMilliseconds ?? 0;
            return CustomPaint(
              painter: _AuroraPainter(
                progress: progress,
                wallClockMs: wallClock,
                particles: _particles,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vy,
    required this.vxBase,
    required this.r,
    required this.opacity,
    required this.seed,
  });

  factory _Particle.random(math.Random rng, double w, double h) {
    return _Particle(
      x: 6 + rng.nextDouble() * (w - 12),
      y: rng.nextDouble() * h,
      vy: 0.18 + rng.nextDouble() * 0.35,
      vxBase: (rng.nextDouble() - 0.5) * 0.4,
      r: 0.7 + rng.nextDouble() * 1.3,
      opacity: 0.35 + rng.nextDouble() * 0.5,
      seed: rng.nextDouble() * 1000,
    );
  }

  double x;
  double y;
  double vy;
  double vxBase;
  double r;
  double opacity;
  double seed;
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.progress,
    required this.wallClockMs,
    required this.particles,
  });

  final double progress;
  final int wallClockMs;
  final List<_Particle> particles;

  static const _purple = Color(0xFF7C4DFF);
  static const _cyan = Color(0xFF5BC7FF);
  static const _green = Color(0xFF34D399);
  static const _gold = Color(0xFFD9B14A);
  static const _goldBorder = Color(0x52D9B14A); // alpha ~0.32

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = w / 2;

    // Capsule path
    final capsule = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(radius),
      ));

    // Subtle background tint (visible above the fill)
    canvas.save();
    canvas.clipPath(capsule);
    canvas.drawColor(const Color(0xCC0F0C19), BlendMode.srcOver);

    // Aurora fill from bottom up
    final eased = _easeOutCubic(progress);
    final fillH = h * eased;
    final fillY = h - fillH;

    if (fillH > 0) {
      // Animated gradient stops shift over time
      final phase = (wallClockMs / 2400) % 1;
      final shift1 = math.sin(phase * math.pi * 2);
      final shift2 = math.sin(phase * math.pi * 2 + 1);

      final stops = <double>[
        0.0,
        (0.32 + 0.08 * shift1).clamp(0.05, 0.5),
        (0.68 + 0.08 * shift2).clamp(0.5, 0.95),
        1.0,
      ];

      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [_purple, _cyan, _green, _gold],
        stops: stops,
      );

      final fillRect = Rect.fromLTWH(0, fillY, w, fillH);
      final fillPaint = Paint()..shader = gradient.createShader(fillRect);
      canvas.drawRect(fillRect, fillPaint);

      // Soft halo above the wave
      final haloRect = Rect.fromLTWH(0, fillY - 24, w, 32);
      final haloPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Color(0x59FFFFFF), // ~0.35
            Color(0x805BC7FF), // ~0.5
          ],
          stops: [0.0, 0.7, 1.0],
        ).createShader(haloRect);
      canvas.drawRect(haloRect, haloPaint);

      // Liquid wave at top edge
      final wavePath = Path();
      const step = 2.0;
      for (double x = 0; x <= w; x += step) {
        final y = fillY + math.sin((x + wallClockMs / 30) / 12) * 2.5;
        if (x == 0) {
          wavePath.moveTo(x, y);
        } else {
          wavePath.lineTo(x, y);
        }
      }
      wavePath
        ..lineTo(w, fillY)
        ..lineTo(0, fillY)
        ..close();
      canvas.drawPath(wavePath, Paint()..color = const Color(0x14FFFFFF));
    }

    // Particles drift upward, only visible inside the filled area
    for (final p in particles) {
      p.y -= p.vy;
      p.x += p.vxBase + math.sin(wallClockMs / 900 + p.seed + p.y / 40) * 0.25;
      if (p.x < 6) p.x = 6;
      if (p.x > w - 6) p.x = w - 6;
      if (p.y < -4) {
        p.y = h + 8;
        p.x = 6 + (p.seed % (w - 12).toInt()).toDouble();
      }
      if (p.y > fillY) {
        final distance = math.min(1.0, (p.y - fillY) / 60);
        final op = p.opacity * (0.3 + 0.7 * distance);
        canvas.drawCircle(
          Offset(p.x, p.y),
          p.r,
          Paint()..color = Color.fromRGBO(255, 255, 255, op),
        );
      }
    }

    canvas.restore();

    // Outer hairline border in gold
    canvas.drawPath(
      capsule,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _goldBorder,
    );
  }

  static double _easeOutCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.progress != progress || old.wallClockMs != wallClockMs;
}
