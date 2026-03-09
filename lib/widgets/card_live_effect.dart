import 'dart:math';
import 'package:flutter/material.dart';

/// Assigns a random animated effect to each wallpaper card.
/// Effects: 0=BreathingGlow, 1=HoloShift, 2=FloatingParticles,
///          3=ScalePulse, 4=GlitchRGB, 5=PixelReveal
enum CardEffect { breathingGlow, holoShift, floatingParticles, scalePulse, glitchRGB, pixelReveal }

class CardLiveEffect extends StatefulWidget {
  const CardLiveEffect({
    required this.child,
    required this.glowColor,
    required this.effectSeed,
    super.key,
  });

  final Widget child;
  final Color glowColor;
  final int effectSeed;

  @override
  State<CardLiveEffect> createState() => _CardLiveEffectState();
}

class _CardLiveEffectState extends State<CardLiveEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CardEffect _effect;
  late final double _delay; // staggered start
  final _random = Random();
  List<_Particle>? _particles;

  @override
  void initState() {
    super.initState();
    _effect = CardEffect.values[widget.effectSeed % CardEffect.values.length];
    _delay = (widget.effectSeed % 7) * 0.14; // stagger animations

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    if (_effect == CardEffect.floatingParticles) {
      _particles = List.generate(8, (_) => _Particle(_random));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = (_controller.value + _delay) % 1.0;

        switch (_effect) {
          case CardEffect.breathingGlow:
            return _buildBreathingGlow(t, child!);
          case CardEffect.holoShift:
            return _buildHoloShift(t, child!);
          case CardEffect.floatingParticles:
            return _buildFloatingParticles(t, child!);
          case CardEffect.scalePulse:
            return _buildScalePulse(t, child!);
          case CardEffect.glitchRGB:
            return _buildGlitchRGB(t, child!);
          case CardEffect.pixelReveal:
            return _buildPixelReveal(t, child!);
        }
      },
      child: widget.child,
    );
  }

  /// Breathing glow shadow that pulses
  Widget _buildBreathingGlow(double t, Widget child) {
    final pulse = (sin(t * 2 * pi) * 0.5 + 0.5);
    final blur = 8.0 + pulse * 16.0;
    final opacity = 0.2 + pulse * 0.35;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: widget.glowColor.withOpacity(opacity),
            blurRadius: blur,
            spreadRadius: pulse * 4,
          ),
        ],
      ),
      child: child,
    );
  }

  /// Holographic rainbow overlay that shifts
  Widget _buildHoloShift(double t, Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1.0 + t * 4, -1.0),
                    end: Alignment(-0.5 + t * 4, 1.0),
                    colors: [
                      Colors.transparent,
                      Colors.purpleAccent.withOpacity(0.06),
                      Colors.cyanAccent.withOpacity(0.08),
                      Colors.pinkAccent.withOpacity(0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Floating glowing particles rising up
  Widget _buildFloatingParticles(double t, Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          child,
          if (_particles != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ParticlePainter(
                    particles: _particles!,
                    progress: t,
                    color: widget.glowColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Subtle scale breathing
  Widget _buildScalePulse(double t, Widget child) {
    final scale = 1.0 + sin(t * 2 * pi) * 0.015;
    return Transform.scale(
      scale: scale,
      child: child,
    );
  }

  /// Occasional RGB split glitch
  Widget _buildGlitchRGB(double t, Widget child) {
    // Glitch only 15% of the time for surprise effect
    final glitchPhase = (t * 7) % 1.0;
    final isGlitching = glitchPhase > 0.85;

    if (!isGlitching) return child;

    final offset = sin(glitchPhase * 50) * 3.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // Red channel shifted
          Positioned(
            left: offset,
            top: 0,
            right: -offset,
            bottom: 0,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0x30FF0000),
                BlendMode.srcATop,
              ),
              child: child,
            ),
          ),
          // Normal
          child,
          // Cyan channel shifted
          Positioned(
            left: -offset,
            top: 0,
            right: offset,
            bottom: 0,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0x1800FFFF),
                BlendMode.srcATop,
              ),
              child: child,
            ),
          ),
          // Scan line
          Positioned(
            left: 0,
            right: 0,
            top: glitchPhase * 300 % 250,
            child: Container(
              height: 2,
              color: Colors.white.withOpacity(0.15),
            ),
          ),
        ],
      ),
    );
  }

  /// Pixel grid overlay that reveals/hides
  Widget _buildPixelReveal(double t, Widget child) {
    final reveal = sin(t * 2 * pi) * 0.5 + 0.5;
    // Only show effect briefly
    if (reveal < 0.7) return child;

    final pixelAlpha = ((reveal - 0.7) / 0.3 * 0.3);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _PixelGridPainter(
                  progress: reveal,
                  color: widget.glowColor.withOpacity(pixelAlpha),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Particle {
  double x, y, speed, size;
  _Particle(Random r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        speed = 0.3 + r.nextDouble() * 0.7,
        size = 1.5 + r.nextDouble() * 2.5;
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color color;
  final _paint = Paint();

  _ParticlePainter({required this.particles, required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final y = (1.0 - ((progress * p.speed + p.y) % 1.0)) * size.height;
      final x = p.x * size.width + sin(progress * 6 + p.x * 10) * 8;
      final alpha = (1.0 - y / size.height).clamp(0.0, 1.0);

      _paint
        ..color = color.withOpacity(alpha * 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(x, y), p.size, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => true;
}

class _PixelGridPainter extends CustomPainter {
  final double progress;
  final Color color;
  final _paint = Paint();

  _PixelGridPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final pixelSize = 8.0;
    _paint.color = color;

    final cols = (size.width / pixelSize).ceil();
    final rows = (size.height / pixelSize).ceil();
    final threshold = (progress - 0.7) / 0.3;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        // Pseudo-random per cell
        final hash = ((r * 31 + c * 17) % 100) / 100.0;
        if (hash < threshold * 0.4) {
          canvas.drawRect(
            Rect.fromLTWH(c * pixelSize, r * pixelSize, pixelSize - 1, pixelSize - 1),
            _paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelGridPainter old) => progress != old.progress;
}
