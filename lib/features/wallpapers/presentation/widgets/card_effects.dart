import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Assigns a deterministic effect to a wallpaper based on its ID.
enum CardEffect {
  glowPulse,     // Border glows and pulses with the glow color
  shimmerSweep,  // Light streak sweeps across the card
  glitch,        // RGB split / interference flicker
  shake,         // Subtle vibration / wobble
  sparkle,       // Magic sparkle particles on the border
  neonBorder,    // Animated neon border trace
  fadeBreath,    // Card breathes (subtle scale + opacity pulse)
  holographic,   // Rainbow color shift on the border
}

CardEffect effectForId(String id) {
  final hash = id.codeUnits.fold<int>(0, (prev, c) => prev * 31 + c);
  return CardEffect.values[hash.abs() % CardEffect.values.length];
}

/// Wraps a card child with its assigned visual effect.
class CardEffectWrapper extends StatefulWidget {
  final String wallpaperId;
  final Color glowColor;
  final double borderRadius;
  final Widget child;

  const CardEffectWrapper({
    super.key,
    required this.wallpaperId,
    required this.glowColor,
    this.borderRadius = 12,
    required this.child,
  });

  @override
  State<CardEffectWrapper> createState() => _CardEffectWrapperState();
}

class _CardEffectWrapperState extends State<CardEffectWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CardEffect _effect;

  @override
  void initState() {
    super.initState();
    _effect = effectForId(widget.wallpaperId);
    _controller = AnimationController(
      vsync: this,
      duration: _durationForEffect(_effect),
    )..repeat(reverse: _shouldReverse(_effect));
  }

  Duration _durationForEffect(CardEffect e) {
    switch (e) {
      case CardEffect.glowPulse: return const Duration(milliseconds: 2000);
      case CardEffect.shimmerSweep: return const Duration(milliseconds: 2500);
      case CardEffect.glitch: return const Duration(milliseconds: 3000);
      case CardEffect.shake: return const Duration(milliseconds: 1500);
      case CardEffect.sparkle: return const Duration(milliseconds: 2000);
      case CardEffect.neonBorder: return const Duration(milliseconds: 3000);
      case CardEffect.fadeBreath: return const Duration(milliseconds: 2500);
      case CardEffect.holographic: return const Duration(milliseconds: 3500);
    }
  }

  bool _shouldReverse(CardEffect e) {
    switch (e) {
      case CardEffect.glowPulse:
      case CardEffect.fadeBreath:
      case CardEffect.shake:
        return true;
      default:
        return false;
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
      builder: (_, __) {
        switch (_effect) {
          case CardEffect.glowPulse:
            return _buildGlowPulse();
          case CardEffect.shimmerSweep:
            return _buildShimmerSweep();
          case CardEffect.glitch:
            return _buildGlitch();
          case CardEffect.shake:
            return _buildShake();
          case CardEffect.sparkle:
            return _buildSparkle();
          case CardEffect.neonBorder:
            return _buildNeonBorder();
          case CardEffect.fadeBreath:
            return _buildFadeBreath();
          case CardEffect.holographic:
            return _buildHolographic();
        }
      },
    );
  }

  // ── 1. Glow Pulse: fine border glow ────────────────────────────────
  Widget _buildGlowPulse() {
    final intensity = 0.2 + 0.3 * Curves.easeInOut.transform(_controller.value);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: widget.glowColor.withOpacity(intensity),
            blurRadius: 0.5 + 0.5 * _controller.value,
            spreadRadius: 0,
          ),
        ],
      ),
      child: widget.child,
    );
  }

  // ── 2. Shimmer Sweep: light streak across card ────────────────────
  Widget _buildShimmerSweep() {
    final sweepPos = -1.0 + 2.6 * _controller.value;
    return Stack(
      children: [
        // Glow border that pulses with sweep
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(0.1 + 0.1 * _controller.value),
                blurRadius: 1.5,
                spreadRadius: 0,
              ),
            ],
          ),
          child: widget.child,
        ),
        // Light streak overlay
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(sweepPos - 0.3, -1),
                    end: Alignment(sweepPos + 0.3, 1),
                    colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 3. Glitch: RGB interference flicker ───────────────────────────
  Widget _buildGlitch() {
    // Only glitch briefly during specific phases
    final phase = (_controller.value * 8).floor() % 8;
    final isGlitching = phase == 2 || phase == 5;
    final glitchOffset = isGlitching ? (math.sin(_controller.value * 50) * 2) : 0.0;

    return Stack(
      children: [
        // Red channel shift
        if (isGlitching)
          Positioned(
            left: glitchOffset,
            top: 0,
            right: -glitchOffset,
            bottom: 0,
            child: Opacity(
              opacity: 0.15,
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(HudTokens.goldDeep, BlendMode.modulate),
                child: widget.child,
              ),
            ),
          ),
        // Main card
        Transform.translate(
          offset: Offset(isGlitching ? glitchOffset * 0.5 : 0, 0),
          child: widget.child,
        ),
        // Scan line
        if (isGlitching)
          Positioned(
            left: 0,
            right: 0,
            top: (_controller.value * 200) % 200,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: widget.glowColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
      ],
    );
  }

  // ── 4. Shake: subtle vibration ────────────────────────────────────
  Widget _buildShake() {
    final shakeX = math.sin(_controller.value * math.pi * 6) * 1.2;
    final shakeY = math.cos(_controller.value * math.pi * 4) * 0.6;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: widget.glowColor.withOpacity(0.2),
            blurRadius: 0.5,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Transform.translate(
        offset: Offset(shakeX, shakeY),
        child: widget.child,
      ),
    );
  }

  // ── 5. Sparkle: magic particles on border ─────────────────────────
  Widget _buildSparkle() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _SparklePainter(
                progress: _controller.value,
                color: widget.glowColor,
                borderRadius: widget.borderRadius,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 6. Neon Border: animated trace around card ────────────────────
  Widget _buildNeonBorder() {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _NeonBorderPainter(
                progress: _controller.value,
                color: widget.glowColor,
                borderRadius: widget.borderRadius,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 7. Fade Breath: subtle scale + opacity pulse ──────────────────
  Widget _buildFadeBreath() {
    final breath = Curves.easeInOut.transform(_controller.value);
    final scale = 1.0 + 0.015 * breath;
    final opacity = 0.92 + 0.08 * breath;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: widget.glowColor.withOpacity(0.1 + 0.1 * breath),
            blurRadius: 0.5 + 0.5 * breath,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: widget.child,
        ),
      ),
    );
  }

  // ── 8. Holographic: rainbow glow around card ───────────────────────
  Widget _buildHolographic() {
    final hue = (_controller.value * 360) % 360;
    final holoColor = HSLColor.fromAHSL(1, hue, 0.8, 0.6).toColor();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: holoColor.withOpacity(0.35),
            blurRadius: 0.5,
            spreadRadius: 0,
          ),
        ],
      ),
      child: widget.child,
    );
  }
}

// ── Sparkle Painter ─────────────────────────────────────────────────
class _SparklePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double borderRadius;

  _SparklePainter({
    required this.progress,
    required this.color,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;

    // Generate sparkle positions along the border
    for (int i = 0; i < 8; i++) {
      final t = ((progress + i * 0.125) % 1.0);
      final sparkleOpacity = (math.sin(t * math.pi * 2) * 0.5 + 0.5);

      if (sparkleOpacity < 0.2) continue;

      // Position along perimeter
      final perimeter = 2 * (size.width + size.height);
      final pos = ((i * 0.125 + progress * 0.3 + rng.nextDouble() * 0.05) % 1.0) * perimeter;

      Offset point;
      if (pos < size.width) {
        point = Offset(pos, 0); // top
      } else if (pos < size.width + size.height) {
        point = Offset(size.width, pos - size.width); // right
      } else if (pos < 2 * size.width + size.height) {
        point = Offset(size.width - (pos - size.width - size.height), size.height); // bottom
      } else {
        point = Offset(0, size.height - (pos - 2 * size.width - size.height)); // left
      }

      final sparkleSize = 2.0 + 2.0 * sparkleOpacity;
      paint.color = color.withOpacity(sparkleOpacity * 0.8);
      canvas.drawCircle(point, sparkleSize, paint);

      // Cross sparkle
      paint.color = Colors.white.withOpacity(sparkleOpacity * 0.6);
      canvas.drawRect(
        Rect.fromCenter(center: point, width: sparkleSize * 3, height: 0.8),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: point, width: 0.8, height: sparkleSize * 3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.progress != progress;
}

// ── Neon Border Painter ─────────────────────────────────────────────
class _NeonBorderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double borderRadius;

  _NeonBorderPainter({
    required this.progress,
    required this.color,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Trace a portion of the border
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().first;
    final totalLength = metrics.length;

    final traceLength = totalLength * 0.3; // 30% of perimeter
    final start = (progress * totalLength) % totalLength;
    final end = start + traceLength;

    final extractedPath = metrics.extractPath(start, end.clamp(0, totalLength));
    if (end > totalLength) {
      extractedPath.addPath(metrics.extractPath(0, end - totalLength), Offset.zero);
    }

    // Glow
    canvas.drawPath(
      extractedPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );

    // Core line
    canvas.drawPath(
      extractedPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withOpacity(0.8)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_NeonBorderPainter old) => old.progress != progress;
}
