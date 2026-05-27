import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// M09 + M20 — Celebración con partículas (confetti / cosmic burst).
///
/// Overlay reusable que dispara partículas doradas/ámbar saliendo del
/// centro al ser activado. Uso:
///   • [CelebrationBurst.confetti] — para activación de suscripción
///   • [CelebrationBurst.badge]    — para badges de logros (10 wallpapers, etc.)
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html`
/// (M09 Subscription Confetti, M20 Collector Badge Burst).
class CelebrationBurst extends StatefulWidget {
  const CelebrationBurst._({
    required this.child,
    required this.controller,
    required this.particleColors,
    required this.particleCount,
    required this.spread,
  });

  /// Confetti dorado para suscripción.
  factory CelebrationBurst.confetti({
    required CelebrationController controller,
    required Widget child,
  }) {
    return CelebrationBurst._(
      controller: controller,
      child: child,
      particleColors: const [
        Color(0xFFC9A650),
        Color(0xFFFFD66B),
        Color(0xFFFFB400),
        Color(0xFFE0C275),
      ],
      particleCount: 24,
      spread: 200,
    );
  }

  /// Cosmic burst para badges de logro.
  factory CelebrationBurst.badge({
    required CelebrationController controller,
    required Widget child,
  }) {
    return CelebrationBurst._(
      controller: controller,
      child: child,
      particleColors: const [
        Color(0xFFFFD66B),
        Color(0xFFC9A650),
        Color(0xFFE0C275),
      ],
      particleCount: 18,
      spread: 140,
    );
  }

  final Widget child;
  final CelebrationController controller;
  final List<Color> particleColors;
  final int particleCount;
  final double spread;

  @override
  State<CelebrationBurst> createState() => _CelebrationBurstState();
}

class CelebrationController extends ChangeNotifier {
  int _ticks = 0;
  int get ticks => _ticks;
  void celebrate() {
    _ticks++;
    notifyListeners();
  }
}

class _CelebrationBurstState extends State<CelebrationBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _particles = _generateParticles();
    widget.controller.addListener(_onCelebrate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCelebrate);
    _ctrl.dispose();
    super.dispose();
  }

  void _onCelebrate() {
    _particles = _generateParticles();
    _ctrl.forward(from: 0);
  }

  List<_Particle> _generateParticles() {
    final rng = math.Random();
    return List.generate(widget.particleCount, (i) {
      final angle = rng.nextDouble() * math.pi * 2;
      final distance = widget.spread * (0.4 + rng.nextDouble() * 0.6);
      return _Particle(
        angle: angle,
        distance: distance,
        size: 1.5 + rng.nextDouble() * 1.5,
        color: widget.particleColors[rng.nextInt(widget.particleColors.length)],
        startDelay: rng.nextDouble() * 0.2,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            if (_ctrl.value == 0) return const SizedBox.shrink();
            return IgnorePointer(
              child: CustomPaint(
                size: Size(widget.spread * 2, widget.spread * 2),
                painter: _BurstPainter(
                  progress: _ctrl.value,
                  particles: _particles,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Particle {
  _Particle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
    required this.startDelay,
  });
  final double angle;
  final double distance;
  final double size;
  final Color color;
  final double startDelay;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.particles});
  final double progress;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final p in particles) {
      // Each particle has its own start delay, then expands radially
      final localT =
          ((progress - p.startDelay) / (1.0 - p.startDelay)).clamp(0.0, 1.0);
      if (localT == 0) continue;
      final eased = Curves.easeOutQuart.transform(localT);
      final dx = center.dx + math.cos(p.angle) * p.distance * eased;
      final dy = center.dy +
          math.sin(p.angle) * p.distance * eased +
          eased * eased * 30; // gravity
      final opacity = (1.0 - eased).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8);
      canvas.drawCircle(Offset(dx, dy), p.size * (1.0 - eased * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────
// M20 — Collector Badge (medalla + título + meta + burst de partículas)
// ─────────────────────────────────────────────────────────────────────

/// Badge editorial para logros del usuario. Se muestra dentro de un
/// [CelebrationBurst.badge] para tener la animación de partículas al
/// aparecer.
class CollectorBadge extends StatelessWidget {
  const CollectorBadge({
    super.key,
    required this.title,
    required this.meta,
    this.medal = '★',
  });

  final String title;
  final String meta;
  final String medal;

  static const Color _gold = Color(0xFFC9A650);
  static const Color _amberBright = Color(0xFFFFD66B);
  static const Color _rust = Color(0xFFC77A3B);
  static const Color _cream = Color(0xFFF0E6D2);
  static const Color _charcoal = Color(0xFF1F1B17);
  static const Color _amber = Color(0xFFFFB400);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const RadialGradient(
          colors: [Color(0x2EFFB400), Color(0x99000000)],
        ),
        border: Border.all(color: _gold, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_gold, _rust],
              ),
              border: Border.all(color: _amberBright, width: 2),
              boxShadow: [
                BoxShadow(
                  color: _amber.withValues(alpha: 0.6),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Center(
              child: Text(
                medal,
                style: GoogleFonts.fraunces(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _charcoal,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.fraunces(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: _cream,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.6,
                  color: _gold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
