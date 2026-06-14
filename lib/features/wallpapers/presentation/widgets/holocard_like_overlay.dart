import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/wallpaper_stats_service.dart';

/// 2026-06-13 — Animacion de like para el holocard (pantalla detail).
///
/// Combina tres efectos de los mockups elegidos por Eduardo:
///   #1 HEART BURST + PARTICLES  — corazon rojo grande explota desde el
///                                 centro + 12 particulas doradas
///   #3 HOLOGRAPHIC SHIMMER       — banda holografica diagonal cruza la
///                                 card en 1.4s + glow gold en el border
///   #4 STACK COUNTER             — toast "+1 LIKE" slide-in desde top-right
///                                 con count-up del contador
///
/// Uso:
/// ```dart
/// Stack(children: [
///   YourHolocardContent(),
///   HolocardLikeOverlay(wallpaperId: wallpaper.id),
/// ])
/// ```
///
/// El overlay se suscribe a `WallpaperStatsService.statsEventStream` y
/// dispara la animacion combinada cada vez que llega un evento de tipo
/// 'like' (sea local — tap del usuario — o remoto — Realtime de otro
/// device). Los unlikes y views se ignoran (este widget es solo para
/// celebrar likes positivos).
class HolocardLikeOverlay extends StatefulWidget {
  const HolocardLikeOverlay({super.key, required this.wallpaperId});
  final String wallpaperId;

  @override
  State<HolocardLikeOverlay> createState() => _HolocardLikeOverlayState();
}

class _HolocardLikeOverlayState extends State<HolocardLikeOverlay>
    with TickerProviderStateMixin {
  StreamSubscription<StatEvent>? _sub;
  final List<_LikeBurstInstance> _bursts = [];
  final List<_LikeToastInstance> _toasts = [];

  late final AnimationController _shimmerCtrl;

  // 2026-06-13 — Throttle + batching para storms de Realtime. Mismo
  // principio que GridCardAnimationOverlay: primer event dispara, los
  // siguientes durante el cooldown se acumulan y se fusionan en UN solo
  // efecto al expirar. Asi 100 likes en 1s = 1-2 animaciones en vez de
  // 100.
  static const _kCooldown = Duration(milliseconds: 1200);
  bool _onCooldown = false;
  int _pendingDelta = 0;
  StatEvent? _pendingTemplate;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _sub = WallpaperStatsService.instance.statsEventStream.listen((event) {
      if (!mounted) return;
      if (event.wallpaperId != widget.wallpaperId) return;
      if (event.type != 'like') return; // ignore unlike/view/download
      _onLikeEvent(event);
    });
  }

  @override
  void didUpdateWidget(HolocardLikeOverlay old) {
    super.didUpdateWidget(old);
    if (old.wallpaperId != widget.wallpaperId) {
      setState(() {
        _bursts.clear();
        _toasts.clear();
      });
      _pendingDelta = 0;
      _pendingTemplate = null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cooldownTimer?.cancel();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  void _onLikeEvent(StatEvent event) {
    if (_onCooldown) {
      _pendingDelta += event.delta;
      _pendingTemplate = event;
      return;
    }
    _trigger(event);
    _onCooldown = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(_kCooldown, () {
      if (!mounted) return;
      _onCooldown = false;
      if (_pendingDelta > 0 && _pendingTemplate != null) {
        final batched = StatEvent(
          wallpaperId: _pendingTemplate!.wallpaperId,
          type: _pendingTemplate!.type,
          delta: _pendingDelta,
          newValue: _pendingTemplate!.newValue,
          isLocal: _pendingTemplate!.isLocal,
        );
        _pendingDelta = 0;
        _pendingTemplate = null;
        _onLikeEvent(batched);
      }
    });
  }

  void _trigger(StatEvent event) {
    // Effect 3: Holographic shimmer (siempre)
    _shimmerCtrl.forward(from: 0);

    // Effect 1: Heart burst + particles (solo si es local — celebracion
    // grande para el usuario que tapeó). Para likes remotos hacemos un
    // burst mas pequeño (50% scale) para no saturar.
    final scale = event.isLocal ? 1.0 : 0.6;
    final burst = _LikeBurstInstance(scale: scale);
    setState(() => _bursts.add(burst));
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _bursts.remove(burst));
    });

    // Effect 4: Stack counter toast
    final toast = _LikeToastInstance(
      newValue: event.newValue,
      isLocal: event.isLocal,
      stackIndex: _toasts.length,
    );
    setState(() => _toasts.add(toast));
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      setState(() => _toasts.remove(toast));
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Shimmer holografico
          AnimatedBuilder(
            animation: _shimmerCtrl,
            builder: (context, _) {
              if (_shimmerCtrl.value == 0 || _shimmerCtrl.value == 1) {
                return const SizedBox.shrink();
              }
              return _HoloShimmer(progress: _shimmerCtrl.value);
            },
          ),

          // Heart bursts (uno por evento like)
          for (final b in _bursts) _HeartBurstWidget(instance: b),

          // Stack counter toasts (uno por evento like)
          for (final t in _toasts) _LikeToastWidget(instance: t),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//   EFFECT 1 — HEART BURST + PARTICLES
// ─────────────────────────────────────────────────────────────────────

class _LikeBurstInstance {
  final double scale;
  final int seed;
  _LikeBurstInstance({required this.scale})
      : seed = DateTime.now().microsecondsSinceEpoch;
}

class _HeartBurstWidget extends StatefulWidget {
  const _HeartBurstWidget({required this.instance});
  final _LikeBurstInstance instance;

  @override
  State<_HeartBurstWidget> createState() => _HeartBurstWidgetState();
}

class _HeartBurstWidgetState extends State<_HeartBurstWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(widget.instance.seed);
    _particles = List.generate(12, (i) {
      final angle = (i / 12) * math.pi * 2 + rng.nextDouble() * 0.3;
      final dist = 80 + rng.nextDouble() * 60;
      return _Particle(angle: angle, distance: dist);
    });
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          // Heart: pops to 1.4x at 40%, settles at 1.1x, fades + scales to 2x
          double heartScale;
          double heartOpacity;
          if (t < 0.4) {
            heartScale = (t / 0.4) * 1.4;
            heartOpacity = (t / 0.4).clamp(0, 1).toDouble();
          } else if (t < 0.6) {
            heartScale = 1.4 - ((t - 0.4) / 0.2) * 0.3; // 1.4 → 1.1
            heartOpacity = 1;
          } else {
            heartScale = 1.1 + ((t - 0.6) / 0.4) * 0.9; // 1.1 → 2.0
            heartOpacity = 1 - ((t - 0.6) / 0.4); // 1 → 0
          }

          return SizedBox(
            width: 200 * widget.instance.scale,
            height: 200 * widget.instance.scale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Particles (gold/yellow)
                ..._particles.map((p) {
                  final dx = math.cos(p.angle) * p.distance * t;
                  final dy = math.sin(p.angle) * p.distance * t;
                  final size = 8 * (1 - t * 0.8);
                  final opacity = t < 0.1
                      ? t * 10
                      : (1 - (t - 0.1) / 0.9).clamp(0, 1).toDouble();
                  return Transform.translate(
                    offset: Offset(
                        dx * widget.instance.scale, dy * widget.instance.scale),
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6B655),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE6B655)
                                  .withValues(alpha: 0.8),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                // Big heart
                Opacity(
                  opacity: heartOpacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: heartScale * widget.instance.scale,
                    child: Icon(
                      Icons.favorite,
                      size: 80,
                      color: const Color(0xFFFF3B5C),
                      shadows: [
                        Shadow(
                          color: const Color(0xFFFF3B5C).withValues(alpha: 0.9),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double distance;
  _Particle({required this.angle, required this.distance});
}

// ─────────────────────────────────────────────────────────────────────
//   EFFECT 3 — HOLOGRAPHIC SHIMMER
// ─────────────────────────────────────────────────────────────────────

class _HoloShimmer extends StatelessWidget {
  const _HoloShimmer({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      // Slide a translucent diagonal band from off-screen left (-w) to
      // off-screen right (+2w) so the cycle travels its full width plus
      // one band width.
      final dx = -w + progress * (w * 3);
      return Stack(
        children: [
          // Border glow (gold pulse during shimmer)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFFE6B655).withValues(
                    alpha: math.sin(progress * math.pi).clamp(0.0, 1.0),
                  ),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE6B655).withValues(
                      alpha: math.sin(progress * math.pi) * 0.4,
                    ),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          // Diagonal shimmer band
          ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: dx,
                  top: 0,
                  bottom: 0,
                  width: w * 0.6,
                  child: Transform.rotate(
                    angle: 0.14, // ~8 degrees
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            const Color(0xFFFFE44D).withValues(alpha: 0.35),
                            const Color(0xFF00F0FF).withValues(alpha: 0.45),
                            const Color(0xFFFF2BD6).withValues(alpha: 0.35),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.4, 0.5, 0.6, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────
//   EFFECT 4 — STACK COUNTER TOAST
// ─────────────────────────────────────────────────────────────────────

class _LikeToastInstance {
  final int newValue;
  final bool isLocal;
  final int stackIndex;
  final int seed;
  _LikeToastInstance({
    required this.newValue,
    required this.isLocal,
    required this.stackIndex,
  }) : seed = DateTime.now().microsecondsSinceEpoch;
}

class _LikeToastWidget extends StatefulWidget {
  const _LikeToastWidget({required this.instance});
  final _LikeToastInstance instance;

  @override
  State<_LikeToastWidget> createState() => _LikeToastWidgetState();
}

class _LikeToastWidgetState extends State<_LikeToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 2026-06-13 fix — antes el `Positioned` estaba ADENTRO del
    // AnimatedBuilder. El Stack padre (HolocardLikeOverlay) NO veia el
    // Positioned como child directo y tiraba ParentDataWidget error en
    // cada frame. Fix: el Positioned ahora es el root (Stack lo ve), y
    // el AnimatedBuilder vive ADENTRO controlando el FractionalTranslation
    // y la Opacity.
    return Positioned(
      top: 60 + widget.instance.stackIndex * 44.0,
      right: 0,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          // Slide-in from right (0-15%), hold (15-75%), slide-out (75-100%)
          double offsetX;
          double opacity;
          if (t < 0.15) {
            final p = t / 0.15;
            offsetX = 1.0 - p; // 1 → 0
            opacity = p;
          } else if (t < 0.75) {
            offsetX = 0;
            opacity = 1;
          } else {
            final p = (t - 0.75) / 0.25;
            offsetX = p * 0.4; // 0 → 0.4 (sale a la derecha)
            opacity = 1 - p;
          }

          return FractionalTranslation(
            translation: Offset(offsetX, 0),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0A001A).withValues(alpha: 0.95),
                      const Color(0xFF1A0033).withValues(alpha: 0.95),
                    ],
                  ),
                  border: Border.all(
                      color: widget.instance.isLocal
                          ? const Color(0xFFFF3B5C)
                          : const Color(0xFFFF2BD6),
                      width: 1),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (widget.instance.isLocal
                              ? const Color(0xFFFF3B5C)
                              : const Color(0xFFFF2BD6))
                          .withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.favorite,
                      color: Color(0xFFFF3B5C),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '+1',
                      style: GoogleFonts.shareTechMono(
                        color: widget.instance.isLocal
                            ? const Color(0xFFFF3B5C)
                            : const Color(0xFFFF2BD6),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.instance.isLocal ? 'LIKE' : 'LIKE NUEVO',
                      style: GoogleFonts.shareTechMono(
                        color: const Color(0xFFE8E0FF),
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
