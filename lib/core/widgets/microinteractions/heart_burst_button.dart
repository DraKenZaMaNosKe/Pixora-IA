import 'dart:math' as math;
import 'package:flutter/material.dart';

/// M06 — Heart Favorite Burst.
///
/// Botón de favorito que cuando se activa hace pop del corazón + rocía
/// partículas rosas radialmente. Replaza el `IconButton(Icons.favorite)`
/// estándar para cualquier wallpaper / track / ringtone.
///
/// Modo [attract] (Eduardo 2026-07-19): cuando el usuario AÚN no ha dado
/// like, el corazón LATE (heartbeat doble) y suelta corazoncitos chiquitos
/// que suben — un imán visual para invitar al like. Se apaga solo al activar.
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M06).
class HeartBurstButton extends StatefulWidget {
  const HeartBurstButton({
    super.key,
    required this.active,
    required this.onTap,
    this.size = 22,
    this.color = const Color(0xFFFF5A8E),
    this.attract = false,
  });

  final bool active;
  final VoidCallback onTap;
  final double size;
  final Color color;

  /// Si es true y NO está [active], el corazón late y emite corazoncitos
  /// para llamar la atención. Ignorado cuando ya es favorito.
  final bool attract;

  @override
  State<HeartBurstButton> createState() => _HeartBurstButtonState();
}

class _HeartBurstButtonState extends State<HeartBurstButton>
    with TickerProviderStateMixin {
  late final AnimationController _popCtrl;
  late final AnimationController _particlesCtrl;
  late final AnimationController _beatCtrl; // heartbeat (attract)
  late final AnimationController _floatCtrl; // corazoncitos que suben

  /// Color rosa fijo del imán de like — los corazones se leen como "amor"
  /// aunque el ícono base sea dorado.
  static const _attractColor = Color(0xFFFF5A8E);

  // Latido doble: dos thumps rápidos y un descanso largo (~se siente vivo).
  late final Animation<double> _beat = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 11),
    TweenSequenceItem(
        tween: Tween(begin: 1.18, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 11),
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.11)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 9),
    TweenSequenceItem(
        tween: Tween(begin: 1.11, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 9),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
  ]).animate(_beatCtrl);

  @override
  void initState() {
    super.initState();
    _popCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _particlesCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _beatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _syncAttract();
  }

  @override
  void didUpdateWidget(HeartBurstButton old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.attract != widget.attract) {
      _syncAttract();
    }
  }

  /// Arranca o detiene el imán según attract && !active.
  void _syncAttract() {
    final on = widget.attract && !widget.active;
    if (on) {
      if (!_beatCtrl.isAnimating) _beatCtrl.repeat();
      if (!_floatCtrl.isAnimating) _floatCtrl.repeat();
    } else {
      _beatCtrl.stop();
      _floatCtrl.stop();
    }
  }

  @override
  void dispose() {
    _popCtrl.dispose();
    _particlesCtrl.dispose();
    _beatCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    if (!widget.active) {
      // Acaba de activarse → apagar imán y disparar burst.
      _beatCtrl.stop();
      _floatCtrl.stop();
      _popCtrl.forward(from: 0);
      _particlesCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attracting = widget.attract && !widget.active;
    // Accesibilidad: sin animaciones no corremos el imán.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Corazoncitos que suben (solo en modo imán)
            if (attracting && !reduceMotion)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _floatCtrl,
                    builder: (_, __) => CustomPaint(
                      painter: _FloatingHeartsPainter(
                        progress: _floatCtrl.value,
                        color: _attractColor,
                      ),
                    ),
                  ),
                ),
              ),
            // Partículas rosas (solo durante el burst al activar)
            AnimatedBuilder(
              animation: _particlesCtrl,
              builder: (_, __) {
                if (_particlesCtrl.value == 0) return const SizedBox.shrink();
                return CustomPaint(
                  size: const Size(60, 60),
                  painter: _ParticlesPainter(
                    progress: _particlesCtrl.value,
                    color: widget.color,
                  ),
                );
              },
            ),
            // Corazón: pop al activar, o latido en modo imán.
            AnimatedBuilder(
              animation: Listenable.merge([_popCtrl, _beatCtrl]),
              builder: (_, __) {
                double scale;
                if (attracting && !reduceMotion) {
                  scale = _beat.value;
                } else {
                  final t = _popCtrl.value;
                  if (t < 0.3) {
                    scale = 1.0 + (t / 0.3) * 0.5; // 1 → 1.5
                  } else if (t < 0.6) {
                    scale = 1.5 - ((t - 0.3) / 0.3) * 0.6; // 1.5 → 0.9
                  } else {
                    scale = 0.9 + ((t - 0.6) / 0.4) * 0.1; // 0.9 → 1.0
                  }
                }
                final Color iconColor;
                final List<Shadow>? glow;
                if (widget.active) {
                  iconColor = widget.color;
                  glow = [
                    Shadow(
                        color: widget.color.withValues(alpha: 0.6),
                        blurRadius: 8)
                  ];
                } else if (attracting) {
                  iconColor = _attractColor;
                  glow = [
                    Shadow(
                        color: _attractColor.withValues(alpha: 0.7),
                        blurRadius: 10)
                  ];
                } else {
                  iconColor = Colors.white.withValues(alpha: 0.4);
                  glow = null;
                }
                return Transform.scale(
                  scale: scale,
                  child: Icon(
                    widget.active ? Icons.favorite : Icons.favorite_border,
                    size: widget.size,
                    color: iconColor,
                    shadows: glow,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Dibuja 3 corazoncitos que suben desde el corazón y se desvanecen, en fases
/// escalonadas, con leve deriva horizontal — el "imán" de like.
class _FloatingHeartsPainter extends CustomPainter {
  _FloatingHeartsPainter({required this.progress, required this.color});
  final double progress; // 0..1 del ciclo global
  final Color color;

  static const int _count = 3;
  // Deriva horizontal por corazón (px) y desfase de fase (0..1).
  static const _driftX = [-11.0, 3.0, 12.0];
  static const _phase = [0.0, 0.34, 0.67];
  static const _sizes = [7.0, 5.5, 6.5];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final baseY = size.height * 0.72; // arranca cerca del corazón
    for (var i = 0; i < _count; i++) {
      // Progreso individual con desfase, envuelto a 0..1.
      final p = (progress + _phase[i]) % 1.0;
      // Sube de baseY hacia arriba; fade-in corto + fade-out largo.
      final y = baseY - p * (size.height * 0.66);
      final x = cx + _driftX[i] * p;
      final opacity =
          p < 0.15 ? (p / 0.15) : (1.0 - (p - 0.15) / 0.85).clamp(0.0, 1.0);
      if (opacity <= 0.01) continue;
      final s = _sizes[i] * (0.7 + 0.3 * p);
      final paint = Paint()
        ..color = color.withValues(alpha: opacity * 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawPath(_heart(Offset(x, y), s), paint);
    }
  }

  /// Corazoncito centrado en [c] con "radio" [s].
  Path _heart(Offset c, double s) {
    final p = Path();
    p.moveTo(c.dx, c.dy + s * 0.35);
    p.cubicTo(c.dx - s * 1.1, c.dy - s * 0.45, c.dx - s * 0.5, c.dy - s * 1.05,
        c.dx, c.dy - s * 0.35);
    p.cubicTo(c.dx + s * 0.5, c.dy - s * 1.05, c.dx + s * 1.1, c.dy - s * 0.45,
        c.dx, c.dy + s * 0.35);
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(_FloatingHeartsPainter old) =>
      old.progress != progress || old.color != color;
}

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  static const int _count = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 20 + progress * 20;
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    for (var i = 0; i < _count; i++) {
      final angle = (i / _count) * math.pi * 2;
      final dx = center.dx + math.cos(angle) * radius;
      final dy = center.dy + math.sin(angle) * radius;
      final particleSize = 2.5 * opacity;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity * 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
      canvas.drawCircle(Offset(dx, dy), particleSize, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter old) => old.progress != progress;
}
