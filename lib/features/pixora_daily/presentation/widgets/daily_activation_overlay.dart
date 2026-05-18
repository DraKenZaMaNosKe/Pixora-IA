import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Full-screen synthwave activation transition shown when the user taps
/// ACTIVAR DAILY. Eduardo's request 2026-05-17: "ponerlo en pantalla
/// completa el fondo morado con líneas que se mueven".
///
/// Visual recipe:
/// - Deep purple gradient bg (matches Pixora Daily page bg)
/// - Synthwave perspective grid that scrolls toward the viewer
/// - Horizon sun glow in pink (Miami Vice / Outrun aesthetic)
/// - Center: orbitron text "ACTIVANDO PIXORA DAILY..." with subtitle
///   (the configured interval) and a pulsating triangle play icon
///
/// Usage:
/// ```dart
/// final route = PageRouteBuilder(
///   opaque: false,
///   barrierDismissible: false,
///   pageBuilder: (_, __, ___) => DailyActivationOverlay(
///     intervalLabel: '15 min',
///     onComplete: () { /* close + continue */ },
///   ),
///   transitionDuration: const Duration(milliseconds: 250),
///   transitionsBuilder: (_, anim, __, child) =>
///       FadeTransition(opacity: anim, child: child),
/// );
/// Navigator.of(context).push(route);
/// ```
///
/// [onComplete] fires after the full sequence (default 3s). The overlay
/// auto-pops itself after firing.
class DailyActivationOverlay extends StatefulWidget {
  const DailyActivationOverlay({
    super.key,
    required this.intervalLabel,
    required this.onComplete,
    this.duration = const Duration(milliseconds: 3000),
  });

  /// Display label of the active interval (e.g. '15 min', '1 h').
  final String intervalLabel;

  /// Callback fired AFTER the overlay has been popped from the navigator.
  /// Use this to show the success snackbar / continue with downstream logic.
  final VoidCallback onComplete;

  /// How long the overlay stays visible total. Default 3 seconds is enough
  /// for the user to feel the transition without blocking too long.
  final Duration duration;

  // Synthwave palette (matches PixoraDailyPage)
  static const _bgTop = Color(0xFF1A0033);
  static const _bgMid = Color(0xFF3D0066);
  static const _bgDeep = Color(0xFF7A0099);
  static const _neonPink = Color(0xFFFF2BD6);
  static const _neonCyan = Color(0xFF00F0FF);
  static const _neonYellow = Color(0xFFFFE44D);

  @override
  State<DailyActivationOverlay> createState() => _DailyActivationOverlayState();
}

class _DailyActivationOverlayState extends State<DailyActivationOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _gridCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    // Continuous loop — the grid never stops moving while overlay visible
    _gridCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: 0,
    );
    _fadeCtrl.forward();
    // Auto-close after [widget.duration]
    Future.delayed(widget.duration, _close);
  }

  Future<void> _close() async {
    if (!mounted) return;
    await _fadeCtrl.reverse();
    if (!mounted) return;
    Navigator.of(context).maybePop();
    widget.onComplete();
  }

  @override
  void dispose() {
    _gridCtrl.dispose();
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fadeCtrl,
      builder: (_, __) {
        return Opacity(
          opacity: _fadeCtrl.value,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                // Background gradient + sun glow
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: const [
                          DailyActivationOverlay._bgTop,
                          DailyActivationOverlay._bgMid,
                          DailyActivationOverlay._bgDeep,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
                // Horizon sun glow (Outrun aesthetic)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, 1.1),
                        radius: 0.9,
                        colors: [
                          DailyActivationOverlay._neonPink
                              .withValues(alpha: 0.55),
                          DailyActivationOverlay._neonPink
                              .withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Perspective grid (the "líneas que se mueven")
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _gridCtrl,
                    builder: (_, __) => CustomPaint(
                      painter: _SynthGridPainter(
                        progress: _gridCtrl.value,
                        gridColor: DailyActivationOverlay._neonCyan
                            .withValues(alpha: 0.6),
                        horizonGlow: DailyActivationOverlay._neonPink
                            .withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
                // Central content
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Eyebrow
                      Text(
                        '// PIXORA · DAILY',
                        style: GoogleFonts.orbitron(
                          fontSize: 11,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w600,
                          color: DailyActivationOverlay._neonCyan,
                          shadows: [
                            Shadow(
                              color: DailyActivationOverlay._neonCyan
                                  .withValues(alpha: 0.8),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Triangle play icon pulsating
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) {
                          final t = _pulseCtrl.value;
                          final scale = 1.0 + (t * 0.18);
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: DailyActivationOverlay._neonYellow,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: DailyActivationOverlay._neonYellow
                                        .withValues(alpha: 0.45 + (t * 0.35)),
                                    blurRadius: 30,
                                  ),
                                  BoxShadow(
                                    color: DailyActivationOverlay._neonPink
                                        .withValues(alpha: 0.35),
                                    blurRadius: 24,
                                    spreadRadius: -4,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                size: 44,
                                color: DailyActivationOverlay._neonYellow,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 26),
                      // Main title
                      Text(
                        'ACTIVANDO DAILY',
                        style: GoogleFonts.orbitron(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: DailyActivationOverlay._neonYellow,
                          letterSpacing: 3,
                          shadows: [
                            Shadow(
                              color: DailyActivationOverlay._neonYellow
                                  .withValues(alpha: 0.85),
                              blurRadius: 14,
                            ),
                            Shadow(
                              color: DailyActivationOverlay._neonPink
                                  .withValues(alpha: 0.6),
                              blurRadius: 22,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Interval subtitle
                      Text(
                        'Tu pantalla vivirá · cada ${widget.intervalLabel}',
                        style: GoogleFonts.orbitron(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: DailyActivationOverlay._neonCyan,
                          letterSpacing: 1.6,
                          shadows: [
                            Shadow(
                              color: DailyActivationOverlay._neonCyan
                                  .withValues(alpha: 0.55),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// CustomPainter that draws the synthwave perspective grid.
/// Lines converge on a horizon point ~55% down the screen, with
/// horizontal "rows" scrolling toward the viewer using [progress].
class _SynthGridPainter extends CustomPainter {
  _SynthGridPainter({
    required this.progress,
    required this.gridColor,
    required this.horizonGlow,
  });

  /// 0..1 loop. 0 = lines just appeared at horizon, 1 = lines at the
  /// viewer's feet. Reset to 0 to loop seamlessly.
  final double progress;

  /// Color of the grid lines.
  final Color gridColor;

  /// Color used to draw a soft glow line at the horizon.
  final Color horizonGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizonY = h * 0.55;

    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 1. Vertical lines (perspective rays converging at horizon)
    final vanishing = Offset(w / 2, horizonY);
    const verticalCount = 15;
    for (var i = -verticalCount; i <= verticalCount; i++) {
      // Spread along bottom of screen
      final bottomX = (w / 2) + (i / verticalCount) * w * 1.5;
      canvas.drawLine(
        vanishing,
        Offset(bottomX, h),
        paint,
      );
    }

    // 2. Horizontal lines (rows scrolling toward viewer)
    // Use exponential spacing so closer rows are far apart, far rows close.
    const rowCount = 12;
    for (var i = 0; i < rowCount; i++) {
      // 0..1 normalized depth, offset by progress for animation
      final raw = (i / rowCount) + (progress / rowCount);
      final t = raw - raw.floor(); // wrap 0..1
      // Convert linear t -> exponential (perspective)
      final perspective = math.pow(t, 2.5).toDouble();
      final y = horizonY + perspective * (h - horizonY);
      // Skip lines too close to horizon (visual noise)
      if (y - horizonY < 8) continue;
      // Fade in near horizon, fully visible near viewer
      final alpha = (perspective * 1.6).clamp(0.0, 1.0);
      paint.color = gridColor.withValues(alpha: alpha * gridColor.a);
      canvas.drawLine(
        Offset(0, y),
        Offset(w, y),
        paint,
      );
    }

    // 3. Horizon line with glow
    final glowPaint = Paint()
      ..color = horizonGlow
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(w, horizonY),
      glowPaint,
    );
    final crispPaint = Paint()
      ..color = horizonGlow
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(w, horizonY),
      crispPaint,
    );
  }

  @override
  bool shouldRepaint(_SynthGridPainter old) =>
      old.progress != progress ||
      old.gridColor != gridColor ||
      old.horizonGlow != horizonGlow;
}
