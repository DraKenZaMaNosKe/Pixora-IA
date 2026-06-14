import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/wallpaper_stats_service.dart';

/// 2026-06-13 — Animaciones de like + view para las cards del grid
/// (TRENDING / ARTE / NEW / etc.). Reutiliza una sola suscripcion al
/// statsEventStream filtrada por wallpaperId.
///
/// LIKE COMBO (1+3+4 elegido por Eduardo):
///   #1 PULSE BORDER + FLOAT +1 — borde cyan→pink respira, "+1" rojo
///                                 flota subiendo desde el centro
///   #3 MAGNETIC ATTRACT          — sparks doradas son atraidas al ring
///                                 de likes, ring hace punch animation
///   #4 LIGHTNING STRIKE          — rayo cyan baja del cielo, golpea el
///                                 ring, card hace flash brightness
///
/// VIEW COMBO (1+3+5 elegido por Eduardo):
///   #1 SCAN LINE                 — linea cyan baja escaneando
///   #3 VIEWPORT CORNERS          — 4 esquinas cyan como camera focus
///   #5 NUMBER ASCEND             — "+1" cyan sube con trail vertical
///
/// Uso:
/// ```dart
/// Stack(children: [
///   YourGridCardContent(),
///   GridCardAnimationOverlay(wallpaperId: wp.id),
/// ])
/// ```
class GridCardAnimationOverlay extends StatefulWidget {
  const GridCardAnimationOverlay({
    super.key,
    required this.wallpaperId,
    this.ringPosition = const Offset(0.5, 0.92),
  });

  /// Wallpaper a observar.
  final String wallpaperId;

  /// Posicion relativa (0-1) del ring de likes dentro del card —
  /// el magnetic attract converge ahi. Default: bottom-center donde
  /// estan los ActivityRings.
  final Offset ringPosition;

  @override
  State<GridCardAnimationOverlay> createState() =>
      _GridCardAnimationOverlayState();
}

class _GridCardAnimationOverlayState extends State<GridCardAnimationOverlay>
    with TickerProviderStateMixin {
  StreamSubscription<StatEvent>? _sub;
  Timer? _likeCleanupTimer;
  Timer? _viewCleanupTimer;

  // 2026-06-13 — REPLACE MODE en vez de queue para evitar mem-pressure.
  // Antes: cada evento agregaba una nueva instancia a las listas; con
  // eventos rapidos (likes/views cascading desde Realtime) se acumulaban
  // 5-10+ widgets con AnimationController por card x N cards = OOM.
  // Ahora: maximo 1 instancia activa por tipo per card. Si llega otro
  // evento mientras hay uno en curso, REEMPLAZA el actual (el nuevo
  // controller en initState arranca de cero igual). Crash 2026-06-13
  // en Samsung mientras Huawei estaba dando likes.
  _PulseBorderInstance? _activePulse;
  _PlusOneInstance? _activePlusOne;
  _MagneticInstance? _activeMagnetic;
  _LightningInstance? _activeLightning;
  _ScanLineInstance? _activeScan;
  _ViewportCornersInstance? _activeViewport;
  _NumberAscendInstance? _activeAscend;

  // 2026-06-13 — Throttle + batching para resistir storms de Realtime.
  // Sin esto, si 1000 usuarios dan like al mismo wallpaper en 1s, el
  // overlay dispararia 1000 animaciones encadenadas (cada una replace-
  // mode no acumula widgets pero SI dispara setState + create
  // AnimationController) = frame jank seguro. Cooldown de 1200ms:
  //   - Primer evento dispara la animacion inmediatamente
  //   - Eventos posteriores durante el cooldown se ACUMULAN en pending
  //   - Al expirar el cooldown, si hay pending, se dispara UN nuevo
  //     efecto con el total agrupado (instancia recibe pendingCount
  //     para mostrar "+N" en vez de "+1" si N > 1)
  static const _kCooldown = Duration(milliseconds: 1200);
  bool _likeOnCooldown = false;
  bool _viewOnCooldown = false;
  int _pendingLikes = 0;
  int _pendingViews = 0;
  Timer? _likeCooldownTimer;
  Timer? _viewCooldownTimer;

  @override
  void initState() {
    super.initState();
    _sub = WallpaperStatsService.instance.statsEventStream.listen((e) {
      if (!mounted) return;
      if (e.wallpaperId != widget.wallpaperId) return;
      if (e.type == 'like') _onLikeEvent(e);
      if (e.type == 'view') _onViewEvent(e);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _likeCleanupTimer?.cancel();
    _viewCleanupTimer?.cancel();
    _likeCooldownTimer?.cancel();
    _viewCooldownTimer?.cancel();
    super.dispose();
  }

  void _onLikeEvent(StatEvent e) {
    if (_likeOnCooldown) {
      _pendingLikes += e.delta;
      return;
    }
    _triggerLike(e.delta);
    _likeOnCooldown = true;
    _likeCooldownTimer?.cancel();
    _likeCooldownTimer = Timer(_kCooldown, () {
      if (!mounted) return;
      _likeOnCooldown = false;
      if (_pendingLikes > 0) {
        final batched = _pendingLikes;
        _pendingLikes = 0;
        // Re-enter to fire the batched animation respecting cooldown again.
        _onLikeEvent(StatEvent(
          wallpaperId: widget.wallpaperId,
          type: 'like',
          delta: batched,
          newValue: 0,
          isLocal: false,
        ));
      }
    });
  }

  void _onViewEvent(StatEvent e) {
    if (_viewOnCooldown) {
      _pendingViews += e.delta;
      return;
    }
    _triggerView(e.delta);
    _viewOnCooldown = true;
    _viewCooldownTimer?.cancel();
    _viewCooldownTimer = Timer(_kCooldown, () {
      if (!mounted) return;
      _viewOnCooldown = false;
      if (_pendingViews > 0) {
        final batched = _pendingViews;
        _pendingViews = 0;
        _onViewEvent(StatEvent(
          wallpaperId: widget.wallpaperId,
          type: 'view',
          delta: batched,
          newValue: 0,
          isLocal: false,
        ));
      }
    });
  }

  void _triggerLike(int delta) {
    setState(() {
      _activePulse = _PulseBorderInstance();
      _activePlusOne = _PlusOneInstance();
      _activeMagnetic = _MagneticInstance(ringPosition: widget.ringPosition);
      _activeLightning = _LightningInstance();
    });
    _likeCleanupTimer?.cancel();
    _likeCleanupTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _activePulse = null;
        _activePlusOne = null;
        _activeMagnetic = null;
        _activeLightning = null;
      });
    });
  }

  void _triggerView(int delta) {
    setState(() {
      _activeScan = _ScanLineInstance();
      _activeViewport = _ViewportCornersInstance();
      _activeAscend = _NumberAscendInstance(ringPosition: widget.ringPosition);
    });
    _viewCleanupTimer?.cancel();
    _viewCleanupTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _activeScan = null;
        _activeViewport = null;
        _activeAscend = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // LIKE layer (max 1 instance each — replace mode)
          if (_activePulse != null) _PulseBorderWidget(instance: _activePulse!),
          if (_activePlusOne != null) _PlusOneWidget(instance: _activePlusOne!),
          if (_activeMagnetic != null)
            _MagneticWidget(instance: _activeMagnetic!),
          if (_activeLightning != null)
            _LightningWidget(instance: _activeLightning!),

          // VIEW layer (max 1 instance each — replace mode)
          if (_activeScan != null) _ScanLineWidget(instance: _activeScan!),
          if (_activeViewport != null)
            _ViewportCornersWidget(instance: _activeViewport!),
          if (_activeAscend != null)
            _NumberAscendWidget(instance: _activeAscend!),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
//   LIKE EFFECTS
// ═════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────
//   LIKE #1 — PULSE BORDER (cyan → pink)
// ─────────────────────────────────────────────────────────────────────

class _PulseBorderInstance {
  final int seed;
  _PulseBorderInstance() : seed = DateTime.now().microsecondsSinceEpoch;
}

class _PulseBorderWidget extends StatefulWidget {
  const _PulseBorderWidget({required this.instance});
  final _PulseBorderInstance instance;

  @override
  State<_PulseBorderWidget> createState() => _PulseBorderWidgetState();
}

class _PulseBorderWidgetState extends State<_PulseBorderWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
      builder: (_, __) {
        final t = _ctrl.value;
        Color color;
        double opacity;
        if (t < 0.25) {
          color = const Color(0xFF00F0FF); // cyan
          opacity = (t / 0.25).clamp(0, 1).toDouble();
        } else if (t < 0.6) {
          final p = (t - 0.25) / 0.35;
          color =
              Color.lerp(const Color(0xFF00F0FF), const Color(0xFFFF2BD6), p)!;
          opacity = 1;
        } else {
          color = const Color(0xFFFF2BD6);
          opacity = 1 - ((t - 0.6) / 0.4).clamp(0, 1).toDouble();
        }
        return IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
                  width: 2),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color:
                      color.withValues(alpha: (opacity * 0.6).clamp(0.0, 1.0)),
                  blurRadius: 16,
                  spreadRadius: 1,
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
//   LIKE #2 — FLOATING +1
// ─────────────────────────────────────────────────────────────────────

class _PlusOneInstance {
  final int seed;
  _PlusOneInstance() : seed = DateTime.now().microsecondsSinceEpoch;
}

class _PlusOneWidget extends StatefulWidget {
  const _PlusOneWidget({required this.instance});
  final _PlusOneInstance instance;

  @override
  State<_PlusOneWidget> createState() => _PlusOneWidgetState();
}

class _PlusOneWidgetState extends State<_PlusOneWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
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
      builder: (_, __) {
        final t = _ctrl.value;
        // Y: 10 → -10 → -40 → -80
        // Opacity: 0 → 1 → 1 → 0
        // Scale: 0.5 → 1.2 → 1 → 0.8
        double dy, opacity, scale;
        if (t < 0.2) {
          final p = t / 0.2;
          dy = 10 - p * 20; // 10 → -10
          opacity = p;
          scale = 0.5 + p * 0.7; // 0.5 → 1.2
        } else if (t < 0.6) {
          final p = (t - 0.2) / 0.4;
          dy = -10 - p * 30; // -10 → -40
          opacity = 1;
          scale = 1.2 - p * 0.2; // 1.2 → 1.0
        } else {
          final p = (t - 0.6) / 0.4;
          dy = -40 - p * 40; // -40 → -80
          opacity = 1 - p;
          scale = 1.0 - p * 0.2; // 1.0 → 0.8
        }
        return Center(
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Text(
                  '+1',
                  style: GoogleFonts.audiowide(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFF3B5C),
                    shadows: [
                      Shadow(
                          color: const Color(0xFFFF3B5C).withValues(alpha: 0.9),
                          blurRadius: 20),
                      Shadow(
                          color: const Color(0xFFFF3B5C).withValues(alpha: 0.6),
                          blurRadius: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//   LIKE #3 — MAGNETIC ATTRACT (sparks → likes ring)
// ─────────────────────────────────────────────────────────────────────

class _MagneticInstance {
  final Offset ringPosition;
  final int seed;
  _MagneticInstance({required this.ringPosition})
      : seed = DateTime.now().microsecondsSinceEpoch;
}

class _MagneticWidget extends StatefulWidget {
  const _MagneticWidget({required this.instance});
  final _MagneticInstance instance;

  @override
  State<_MagneticWidget> createState() => _MagneticWidgetState();
}

class _MagneticWidgetState extends State<_MagneticWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Spark> _sparks;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(widget.instance.seed);
    _sparks = List.generate(8, (_) {
      return _Spark(
        startX: rng.nextDouble(),
        startY: rng.nextDouble() * 0.7,
        delayMs: rng.nextInt(120),
      );
    });
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
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
      builder: (_, __) {
        final t = _ctrl.value;
        return LayoutBuilder(builder: (context, c) {
          final endX = widget.instance.ringPosition.dx * c.maxWidth;
          final endY = widget.instance.ringPosition.dy * c.maxHeight;
          return Stack(
            children: _sparks.map((s) {
              // staggered start
              final delay = s.delayMs / 1000.0;
              final localT = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
              if (localT <= 0) return const SizedBox.shrink();

              // path: start → ring
              final startX = s.startX * c.maxWidth;
              final startY = s.startY * c.maxHeight;
              double curX, curY, opacity, scale;
              if (localT < 0.2) {
                final p = localT / 0.2;
                curX = startX;
                curY = startY;
                opacity = p;
                scale = p;
              } else if (localT < 0.85) {
                final p = (localT - 0.2) / 0.65;
                curX = startX + (endX - startX) * p;
                curY = startY + (endY - startY) * p;
                opacity = 1;
                scale = 1 - p * 0.5; // 1 → 0.5
              } else {
                final p = (localT - 0.85) / 0.15;
                curX = endX;
                curY = endY;
                opacity = 1 - p;
                scale = 0.5 - p * 0.5;
              }
              return Positioned(
                left: curX - 3,
                top: curY - 3,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE44D),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFFFFE44D)
                                  .withValues(alpha: 0.8),
                              blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        });
      },
    );
  }
}

class _Spark {
  final double startX;
  final double startY;
  final int delayMs;
  _Spark({required this.startX, required this.startY, required this.delayMs});
}

// ─────────────────────────────────────────────────────────────────────
//   LIKE #4 — LIGHTNING STRIKE
// ─────────────────────────────────────────────────────────────────────

class _LightningInstance {
  final int seed;
  _LightningInstance() : seed = DateTime.now().microsecondsSinceEpoch;
}

class _LightningWidget extends StatefulWidget {
  const _LightningWidget({required this.instance});
  final _LightningInstance instance;

  @override
  State<_LightningWidget> createState() => _LightningWidgetState();
}

class _LightningWidgetState extends State<_LightningWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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
      builder: (_, __) {
        final t = _ctrl.value;
        // Lightning height: 0 → full at 40%
        // Opacity: 0 → 1 → flicker → 0
        double heightPct;
        double opacity;
        double jitter = 0;
        if (t < 0.1) {
          heightPct = 0;
          opacity = t * 10;
        } else if (t < 0.4) {
          heightPct = (t - 0.1) / 0.3;
          opacity = 1;
        } else if (t < 0.6) {
          heightPct = 1;
          opacity = 0.6;
          jitter = -2;
        } else if (t < 0.7) {
          heightPct = 1;
          opacity = 1;
          jitter = 2;
        } else {
          heightPct = 1;
          opacity = 1 - ((t - 0.7) / 0.3);
        }
        return Stack(
          children: [
            // Vertical lightning bolt down center
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: Transform.translate(
                  offset: Offset(jitter, 0),
                  child: LayoutBuilder(builder: (context, c) {
                    // 2026-06-13 — clamp a maxHeight para evitar bottom
                    // overflow en cards chiquitas del grid (la mult x 1.5
                    // antes podia hacer height > altura del card).
                    final h =
                        (c.maxWidth * heightPct * 1.5).clamp(0.0, c.maxHeight);
                    return Container(
                      width: 4,
                      height: h,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF00F0FF)
                                .withValues(alpha: opacity.clamp(0.0, 1.0)),
                            Colors.white
                                .withValues(alpha: opacity.clamp(0.0, 1.0)),
                            const Color(0xFF00F0FF)
                                .withValues(alpha: opacity.clamp(0.0, 1.0)),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF00F0FF).withValues(
                                  alpha: (opacity * 0.7).clamp(0.0, 1.0)),
                              blurRadius: 16),
                          BoxShadow(
                              color: const Color(0xFFFF2BD6).withValues(
                                  alpha: (opacity * 0.4).clamp(0.0, 1.0)),
                              blurRadius: 32),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
            // Flash overlay (brightness boost)
            if (t < 0.3)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F0FF).withValues(
                        alpha: (0.08 * (1 - t / 0.3)).clamp(0.0, 1.0)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
//   VIEW EFFECTS (more subtle — cyan, ~900-1200ms)
// ═════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────
//   VIEW #1 — SCAN LINE
// ─────────────────────────────────────────────────────────────────────

class _ScanLineInstance {
  final int seed;
  _ScanLineInstance() : seed = DateTime.now().microsecondsSinceEpoch;
}

class _ScanLineWidget extends StatefulWidget {
  const _ScanLineWidget({required this.instance});
  final _ScanLineInstance instance;

  @override
  State<_ScanLineWidget> createState() => _ScanLineWidgetState();
}

class _ScanLineWidgetState extends State<_ScanLineWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
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
    // 2026-06-13 fix — antes el `Positioned` estaba dentro del
    // AnimatedBuilder + LayoutBuilder, lo cual rompia el contrato del Stack
    // padre (ParentDataWidget error). Ahora el root es Padding (no
    // Positioned), el AnimatedBuilder envuelve el Container, y la posicion
    // vertical se controla via padding-top dinamico.
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        double opacity;
        if (t < 0.1) {
          opacity = t * 10;
        } else if (t < 0.9) {
          opacity = 1;
        } else {
          opacity = 1 - ((t - 0.9) / 0.1);
        }
        return LayoutBuilder(builder: (context, c) {
          return Padding(
            padding: EdgeInsets.only(
              top: ((c.maxHeight - 2) * t).clamp(0.0, c.maxHeight - 2),
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: c.maxWidth,
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      const Color(0xFF00D4FF).withValues(
                          alpha: opacity.clamp(0.0, 1.0).toDouble()),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF00D4FF).withValues(
                            alpha: opacity.clamp(0.0, 0.7).toDouble()),
                        blurRadius: 12),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//   VIEW #3 — VIEWPORT CORNERS (camera focus)
// ─────────────────────────────────────────────────────────────────────

class _ViewportCornersInstance {
  final int seed;
  _ViewportCornersInstance() : seed = DateTime.now().microsecondsSinceEpoch;
}

class _ViewportCornersWidget extends StatefulWidget {
  const _ViewportCornersWidget({required this.instance});
  final _ViewportCornersInstance instance;

  @override
  State<_ViewportCornersWidget> createState() => _ViewportCornersWidgetState();
}

class _ViewportCornersWidgetState extends State<_ViewportCornersWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _corner({
    required double left,
    required double right,
    required double top,
    required double bottom,
    required bool isLeft,
    required bool isTop,
    required double t,
    required int delayIdx,
  }) {
    // Staggered start
    final delay = delayIdx * 0.04;
    final localT = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
    if (localT <= 0) return const SizedBox.shrink();
    double opacity, scale;
    if (localT < 0.2) {
      opacity = localT / 0.2;
      scale = 2 - (localT / 0.2);
    } else if (localT < 0.7) {
      opacity = 1;
      scale = 1;
    } else {
      opacity = 1 - ((localT - 0.7) / 0.3);
      scale = 1 - ((localT - 0.7) / 0.3) * 0.5;
    }
    return Positioned(
      left: left >= 0 ? left : null,
      right: right >= 0 ? right : null,
      top: top >= 0 ? top : null,
      bottom: bottom >= 0 ? bottom : null,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CustomPaint(
              painter: _CornerPainter(isLeft: isLeft, isTop: isTop),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Stack(
          children: [
            _corner(
                left: 8,
                right: -1,
                top: 8,
                bottom: -1,
                isLeft: true,
                isTop: true,
                t: t,
                delayIdx: 0),
            _corner(
                left: -1,
                right: 8,
                top: 8,
                bottom: -1,
                isLeft: false,
                isTop: true,
                t: t,
                delayIdx: 1),
            _corner(
                left: 8,
                right: -1,
                top: -1,
                bottom: 8,
                isLeft: true,
                isTop: false,
                t: t,
                delayIdx: 2),
            _corner(
                left: -1,
                right: 8,
                top: -1,
                bottom: 8,
                isLeft: false,
                isTop: false,
                t: t,
                delayIdx: 3),
          ],
        );
      },
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({required this.isLeft, required this.isTop});
  final bool isLeft;
  final bool isTop;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00D4FF)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    final glowPaint = Paint()
      ..color = const Color(0xFF00D4FF).withValues(alpha: 0.6)
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final path = Path();
    if (isLeft && isTop) {
      path.moveTo(0, h);
      path.lineTo(0, 0);
      path.lineTo(w, 0);
    } else if (!isLeft && isTop) {
      path.moveTo(0, 0);
      path.lineTo(w, 0);
      path.lineTo(w, h);
    } else if (isLeft && !isTop) {
      path.moveTo(0, 0);
      path.lineTo(0, h);
      path.lineTo(w, h);
    } else {
      path.moveTo(0, h);
      path.lineTo(w, h);
      path.lineTo(w, 0);
    }
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      isLeft != old.isLeft || isTop != old.isTop;
}

// ─────────────────────────────────────────────────────────────────────
//   VIEW #5 — NUMBER ASCEND (+1 cyan with trail)
// ─────────────────────────────────────────────────────────────────────

class _NumberAscendInstance {
  final Offset ringPosition;
  final int seed;
  _NumberAscendInstance({required this.ringPosition})
      : seed = DateTime.now().microsecondsSinceEpoch;
}

class _NumberAscendWidget extends StatefulWidget {
  const _NumberAscendWidget({required this.instance});
  final _NumberAscendInstance instance;

  @override
  State<_NumberAscendWidget> createState() => _NumberAscendWidgetState();
}

class _NumberAscendWidgetState extends State<_NumberAscendWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
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
      builder: (_, __) {
        final t = _ctrl.value;
        return LayoutBuilder(builder: (context, c) {
          final ringX = widget.instance.ringPosition.dx * c.maxWidth;
          final ringY = widget.instance.ringPosition.dy * c.maxHeight;

          // Trail position + height
          final trailHeight = (t * 100).clamp(0.0, 100.0);
          final trailOpacity = t < 0.2
              ? (t / 0.2)
              : t > 0.8
                  ? (1 - (t - 0.8) / 0.2)
                  : 1.0;

          // +1 ascending
          double plusDy, plusOpacity, plusScale;
          if (t < 0.2) {
            final p = t / 0.2;
            plusDy = 10 - p * 18; // 10 → -8
            plusOpacity = p;
            plusScale = 0.5 + p * 0.6;
          } else if (t < 0.7) {
            final p = (t - 0.2) / 0.5;
            plusDy = -8 - p * 24; // -8 → -32
            plusOpacity = 1;
            plusScale = 1.1 - p * 0.1;
          } else {
            final p = (t - 0.7) / 0.3;
            plusDy = -32 - p * 32; // -32 → -64
            plusOpacity = 1 - p;
            plusScale = 1.0 - p * 0.2;
          }

          return Stack(
            children: [
              // Trail
              Positioned(
                left: ringX - 1,
                bottom: c.maxHeight - ringY,
                child: Opacity(
                  opacity: trailOpacity.toDouble().clamp(0.0, 1.0),
                  child: Container(
                    width: 2,
                    height: trailHeight,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xFF00D4FF),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                            color:
                                const Color(0xFF00D4FF).withValues(alpha: 0.6),
                            blurRadius: 6),
                      ],
                    ),
                  ),
                ),
              ),
              // +1 number
              Positioned(
                left: ringX - 20,
                top: ringY - 30 + plusDy,
                child: Opacity(
                  opacity: plusOpacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: plusScale,
                    child: SizedBox(
                      width: 40,
                      child: Text(
                        '+1',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.audiowide(
                          fontSize: 13,
                          color: const Color(0xFF00D4FF),
                          shadows: [
                            Shadow(
                                color: const Color(0xFF00D4FF)
                                    .withValues(alpha: 0.9),
                                blurRadius: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        });
      },
    );
  }
}
