import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────
// M10 — AutoRotate Slow Rotate Icon
// ─────────────────────────────────────────────────────────────────────

/// Ícono pequeño que rota lento (1 vuelta cada 30s) cuando Pixora Daily
/// está activo. Confirma estado sin distraer. Visible en header.
class AutoRotateActiveIcon extends StatefulWidget {
  const AutoRotateActiveIcon({
    super.key,
    this.size = 18,
    this.color = const Color(0xFFC9A650),
  });
  final double size;
  final Color color;

  @override
  State<AutoRotateActiveIcon> createState() => _AutoRotateActiveIconState();
}

class _AutoRotateActiveIconState extends State<AutoRotateActiveIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Transform.rotate(
          angle: _ctrl.value * math.pi * 2,
          child: Icon(Icons.refresh, size: widget.size, color: widget.color),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// M12 — Subscriber Gold Ring (avatar wrapper)
// ─────────────────────────────────────────────────────────────────────

/// Wrap cualquier widget avatar para agregar un ring dorado con shimmer
/// sutil que indica suscriptor activo.
class SubscriberGoldRing extends StatefulWidget {
  const SubscriberGoldRing({super.key, required this.child, this.size = 40});
  final Widget child;
  final double size;

  @override
  State<SubscriberGoldRing> createState() => _SubscriberGoldRingState();
}

class _SubscriberGoldRingState extends State<SubscriberGoldRing>
    with SingleTickerProviderStateMixin {
  static const Color _gold = Color(0xFFC9A650);
  static const Color _goldRich = Color(0xFFE0C275);
  static const Color _amberBright = Color(0xFFFFD66B);

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Container(
          width: widget.size,
          height: widget.size,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _goldRich, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Color.lerp(_gold, _amberBright, t)!
                    .withValues(alpha: 0.5 + t * 0.3),
                blurRadius: 16 + t * 8,
              ),
            ],
          ),
          child: ClipOval(child: widget.child),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// M13 — Pixora Daily Pulse Badge
// ─────────────────────────────────────────────────────────────────────

/// Badge "DAILY ACTIVO" con pulse rosa lento. Para listas / settings.
class DailyActiveBadge extends StatefulWidget {
  const DailyActiveBadge({super.key, this.label = 'DAILY ACTIVO'});
  final String label;

  @override
  State<DailyActiveBadge> createState() => _DailyActiveBadgeState();
}

class _DailyActiveBadgeState extends State<DailyActiveBadge>
    with SingleTickerProviderStateMixin {
  static const Color _rose = Color(0xFFFF5A8E);
  static const Color _roseBright = Color(0xFFFF8AB0);

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _rose.withValues(alpha: 0.12),
            border: Border.all(color: _rose),
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: _rose.withValues(alpha: t * 0.4),
                blurRadius: 16,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _rose,
                  boxShadow: [BoxShadow(color: _rose, blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                  color: _roseBright,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// M16 — Pull to Refresh Drop (custom indicator)
// ─────────────────────────────────────────────────────────────────────

/// Gota dorada elástica que reemplaza el spinner default de pull-to-refresh.
///
/// ```dart
/// RefreshIndicator.adaptive(
///   onRefresh: () async { ... },
///   ...
/// );
/// // Para nuestro custom:
/// RefreshIndicator(
///   color: ...,
///   child: ...,
/// );
/// // O usar PullToRefreshDrop como builder de un CustomScrollView.
/// ```
class PullToRefreshDrop extends StatefulWidget {
  const PullToRefreshDrop({super.key, this.size = 40});
  final double size;

  @override
  State<PullToRefreshDrop> createState() => _PullToRefreshDropState();
}

class _PullToRefreshDropState extends State<PullToRefreshDrop>
    with SingleTickerProviderStateMixin {
  static const Color _amberBright = Color(0xFFFFD66B);
  static const Color _amberDeep = Color(0xFFB07A00);
  static const Color _amber = Color(0xFFFFB400);

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final stretch = _ctrl.value; // 0..1..0
        final scaleY = 1.0 + stretch * 0.4;
        final scaleX = 1.0 - stretch * 0.15;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft:
                    Radius.elliptical(widget.size * 0.5, widget.size * 0.6),
                topRight:
                    Radius.elliptical(widget.size * 0.5, widget.size * 0.6),
                bottomLeft:
                    Radius.elliptical(widget.size * 0.5, widget.size * 0.4),
                bottomRight:
                    Radius.elliptical(widget.size * 0.5, widget.size * 0.4),
              ),
              gradient: const RadialGradient(
                center: Alignment(-0.4, -0.4),
                colors: [_amberBright, _amberDeep],
              ),
              boxShadow: [
                BoxShadow(
                  color: _amber.withValues(alpha: 0.6),
                  blurRadius: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// M18 — First-Time Offline Wobble (drop-in via key reset)
// ─────────────────────────────────────────────────────────────────────

/// Wrapper que sacude su hijo con rotation wobble cuando se cambia su key.
/// Pensado para reemplazar [OfflineIndicator] la PRIMERA vez que el usuario
/// pierde conexión. Crear nuevo `UniqueKey()` lo dispara.
class FirstOfflineWobble extends StatefulWidget {
  const FirstOfflineWobble({super.key, required this.child});
  final Widget child;

  @override
  State<FirstOfflineWobble> createState() => _FirstOfflineWobbleState();
}

class _FirstOfflineWobbleState extends State<FirstOfflineWobble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = _ctrl.value;
        // 3 wobble cycles in 1.8s, sin wave de amplitud decreciente
        final angle =
            math.sin(t * math.pi * 6) * 0.1 * (1.0 - t).clamp(0.0, 1.0);
        return Transform.rotate(angle: angle, child: child);
      },
      child: widget.child,
    );
  }
}
