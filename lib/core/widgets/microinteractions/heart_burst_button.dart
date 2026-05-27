import 'dart:math' as math;
import 'package:flutter/material.dart';

/// M06 — Heart Favorite Burst.
///
/// Botón de favorito que cuando se activa hace pop del corazón + rocía
/// partículas rosas radialmente. Replaza el `IconButton(Icons.favorite)`
/// estándar para cualquier wallpaper / track / ringtone.
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M06).
class HeartBurstButton extends StatefulWidget {
  const HeartBurstButton({
    super.key,
    required this.active,
    required this.onTap,
    this.size = 22,
    this.color = const Color(0xFFFF5A8E),
  });

  final bool active;
  final VoidCallback onTap;
  final double size;
  final Color color;

  @override
  State<HeartBurstButton> createState() => _HeartBurstButtonState();
}

class _HeartBurstButtonState extends State<HeartBurstButton>
    with TickerProviderStateMixin {
  late final AnimationController _popCtrl;
  late final AnimationController _particlesCtrl;

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
  }

  @override
  void dispose() {
    _popCtrl.dispose();
    _particlesCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    if (!widget.active) {
      // Acaba de activarse → disparar burst
      _popCtrl.forward(from: 0);
      _particlesCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Partículas rosas (solo durante el burst)
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
            // Corazón con pop
            AnimatedBuilder(
              animation: _popCtrl,
              builder: (_, __) {
                final t = _popCtrl.value;
                double scale;
                if (t < 0.3) {
                  scale = 1.0 + (t / 0.3) * 0.5; // 1 → 1.5
                } else if (t < 0.6) {
                  scale = 1.5 - ((t - 0.3) / 0.3) * 0.6; // 1.5 → 0.9
                } else {
                  scale = 0.9 + ((t - 0.6) / 0.4) * 0.1; // 0.9 → 1.0
                }
                return Transform.scale(
                  scale: scale,
                  child: Icon(
                    widget.active ? Icons.favorite : Icons.favorite_border,
                    size: widget.size,
                    color: widget.active
                        ? widget.color
                        : Colors.white.withValues(alpha: 0.4),
                    shadows: widget.active
                        ? [
                            Shadow(
                              color: widget.color.withValues(alpha: 0.6),
                              blurRadius: 8,
                            )
                          ]
                        : null,
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
