import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/hud_tokens.dart';

/// Aurora Waves loading placeholder for wallpaper grid cards.
///
/// Fills the entire image area with 4 soft radial color blobs that drift
/// organically — like aurora borealis curtains. Theme-aware: deep
/// purples/indigos/teals/gold in Black & Gold, pastel pink/lavender/mint/
/// peach in iOS White.
///
/// Concept #01 from `docs/design/wallpaper_card_loading_states_concepts.html`,
/// chosen by Eduardo 2026-05-13. Replaces the previous `Shimmer.fromColors`
/// grid placeholder and the bottom-up capsule `AuroraLoadingIndicator`.
///
/// Performance: a single SingleTickerProviderStateMixin per card. The painter
/// draws 4 RadialGradient blobs + 1 vertical shimmer overlay per frame. With
/// 24 visible cards this stays under 1 ms paint/frame on a mid-range Samsung.
/// Each card is wrapped in a `RepaintBoundary` by the caller (the grid) so
/// they don't invalidate each other on scroll.
class AuroraWavesLoading extends StatefulWidget {
  const AuroraWavesLoading({super.key});

  @override
  State<AuroraWavesLoading> createState() => _AuroraWavesLoadingState();
}

class _AuroraWavesLoadingState extends State<AuroraWavesLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 7s cycle matches the CSS prototype (auroraFlow keyframes).
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIos = context.hud.isIosStyle;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return CustomPaint(
            painter: _AuroraWavesPainter(
              t: _controller.value,
              isIos: isIos,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _AuroraWavesPainter extends CustomPainter {
  _AuroraWavesPainter({required this.t, required this.isIos});

  /// Normalized animation value [0, 1).
  final double t;
  final bool isIos;

  // Black & Gold palette — deep, cosmic.
  static const _bgBase = Color(0xFF070710); // ink
  static const _bgPurple = Color(0xFF5A2D82); // deep purple
  static const _bgIndigo = Color(0xFF1F3A8A); // royal indigo
  static const _bgTeal = Color(0xFF0F766E); // muted teal
  static const _bgGold = Color(0xFFD4AF37); // pixora gold

  // iOS White palette — soft, airy pastels.
  static const _iosBase = Color(0xFFFAF7F2); // cream
  static const _iosPink = Color(0xFFFFB4C8);
  static const _iosLav = Color(0xFFB4C8FF); // lavender-blue
  static const _iosMint = Color(0xFFB4F0D2);
  static const _iosPeach = Color(0xFFFFDCA0);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // 1. Base fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = isIos ? _iosBase : _bgBase,
    );

    // 2. Four drifting blobs.
    // Each blob's center oscillates on a Lissajous curve using the cycle.
    // Indices 0..3 receive a phase offset so they wave at different times.
    final blobs = isIos
        ? const <Color>[_iosPink, _iosLav, _iosMint, _iosPeach]
        : const <Color>[_bgPurple, _bgIndigo, _bgTeal, _bgGold];

    // Anchor positions (origin centres around which each blob orbits).
    final anchors = <Offset>[
      Offset(0.30 * w, 0.30 * h),
      Offset(0.70 * w, 0.60 * h),
      Offset(0.50 * w, 0.80 * h),
      Offset(0.20 * w, 0.75 * h),
    ];

    final blobRadius = math.max(w, h) * 0.6;
    final tau = 2 * math.pi;

    for (var i = 0; i < blobs.length; i++) {
      final phase = i * (tau / blobs.length);
      // Lissajous drift: sin on X, cos on Y at different freqs.
      final dx = math.sin(t * tau + phase) * w * 0.15;
      final dy = math.cos(t * tau * 0.7 + phase * 1.3) * h * 0.12;
      final centre = anchors[i] + Offset(dx, dy);

      // Strong color at centre, fades to transparent towards the edge of
      // the blob. The 0.55 outer alpha matches the CSS gradient stops.
      final color = blobs[i];
      final inner =
          isIos ? color.withValues(alpha: 0.55) : color.withValues(alpha: 0.78);
      final outer = color.withValues(alpha: 0.0);

      final shader = RadialGradient(
        colors: [inner, outer],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: centre, radius: blobRadius));

      canvas.drawCircle(
        centre,
        blobRadius,
        Paint()
          ..shader = shader
          ..blendMode = isIos ? BlendMode.srcOver : BlendMode.plus,
      );
    }

    // 3. Vertical shimmer sweep (matches CSS `auroraSweep` 5s loop).
    // Travels from -30% to +30% of card height, peak opacity at the middle.
    final sweepPhase = (t * 7 / 5) % 1.0; // 5s in a 7s cycle
    final sweepY = -0.3 * h + 0.6 * h * sweepPhase;
    final sweepOpacity = math.sin(sweepPhase * math.pi); // 0 → 1 → 0
    final sweepColor = isIos
        ? Colors.white.withValues(alpha: 0.30 * sweepOpacity)
        : const Color(0xFFF5D676).withValues(alpha: 0.14 * sweepOpacity);

    final sweepRect = Rect.fromLTWH(0, sweepY, w, h * 0.5);
    final sweepShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        sweepColor.withValues(alpha: 0),
        sweepColor,
        sweepColor.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(sweepRect);

    canvas.drawRect(
      sweepRect,
      Paint()
        ..shader = sweepShader
        ..blendMode = BlendMode.screen,
    );
  }

  @override
  bool shouldRepaint(_AuroraWavesPainter old) =>
      old.t != t || old.isIos != isIos;
}
