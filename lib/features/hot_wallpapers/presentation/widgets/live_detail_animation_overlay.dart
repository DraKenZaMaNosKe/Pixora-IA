import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/wallpaper_stats_service.dart';

/// 2026-06-14 — Combo PRINT STAMP + TICKER TAPE para la pantalla
/// detalle LIVE (Neon Editorial Magazine).
///
/// Reacciona a [WallpaperStatsService.statsEventStream] filtrado por
/// el [wallpaperId] activo:
///
/// 1. **Print stamp**: cada vez que llega un evento (like local,
///    like remoto, view remoto, download), se imprime un sello
///    redondo de tinta sobre el centro de la pantalla con label
///    contextual (LIKED / NEW FAN / SEEN / SAVED). Animación elástica
///    de ~1.1s. Throttle de 1.2s entre stamps para evitar saturar
///    cuando llegan muchos eventos juntos (escala alta).
///
/// 2. **Ticker tape**: panel horizontal permanente abajo, estilo
///    bolsa de valores / NYT live feed. Items scrollean
///    constantemente. Cada evento nuevo se inserta al inicio con
///    flash blanco→gold. Mantenemos máximo ~30 items para que el
///    Row no crezca infinitamente.
///
/// Se inyecta como hijo del Stack del Scaffold, NO envuelve la
/// pantalla — los Positioned se posicionan absoluto contra el
/// SafeArea padre.
class LiveDetailAnimationOverlay extends StatefulWidget {
  final String wallpaperId;

  const LiveDetailAnimationOverlay({
    super.key,
    required this.wallpaperId,
  });

  @override
  State<LiveDetailAnimationOverlay> createState() =>
      _LiveDetailAnimationOverlayState();
}

class _LiveDetailAnimationOverlayState extends State<LiveDetailAnimationOverlay>
    with TickerProviderStateMixin {
  // ── Stamp ───────────────────────────────────────────────────────
  late final AnimationController _stampCtrl;
  String _stampLabel = 'LIKED';
  Color _stampColor = const Color(0xFFFF3B5C);

  // ── Ticker ──────────────────────────────────────────────────────
  late final AnimationController _tickerCtrl;
  final List<_TickerItem> _items = [];

  // ── Throttle ────────────────────────────────────────────────────
  static const _stampCooldown = Duration(milliseconds: 1200);
  DateTime? _lastStamp;
  Timer? _pendingTimer;
  _PendingEvent? _pending;

  StreamSubscription<StatEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _stampCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _tickerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();

    // Seed con items genéricos para que el ticker no aparezca vacío
    _items.addAll(const [
      _TickerItem(text: 'LIVE WALLPAPER', kind: _TickerKind.banner),
      _TickerItem(text: '♥ HOT', kind: _TickerKind.like),
      _TickerItem(text: '👁 TRENDING', kind: _TickerKind.view),
      _TickerItem(text: '⤓ +1 SAVED', kind: _TickerKind.download),
      _TickerItem(text: '♥ +1 FAN', kind: _TickerKind.like),
      _TickerItem(text: '👁 LIVE', kind: _TickerKind.view),
    ]);

    _sub = WallpaperStatsService.instance.statsEventStream.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pendingTimer?.cancel();
    _stampCtrl.dispose();
    _tickerCtrl.dispose();
    super.dispose();
  }

  void _onEvent(StatEvent e) {
    if (!mounted) return;
    if (e.wallpaperId != widget.wallpaperId) return;

    // Inject into ticker immediately (cheap)
    _injectTicker(e);

    // Throttle the stamp (expensive visually) — at most one every 1.2s.
    // If multiple events arrive inside the cooldown, only the latest
    // gets stamped when the window opens (the ticker still captures all).
    final now = DateTime.now();
    if (_lastStamp == null || now.difference(_lastStamp!) >= _stampCooldown) {
      _fireStamp(e);
      _lastStamp = now;
    } else {
      _pending = _PendingEvent(e);
      _pendingTimer?.cancel();
      final wait = _stampCooldown - now.difference(_lastStamp!);
      _pendingTimer = Timer(wait, () {
        if (!mounted || _pending == null) return;
        _fireStamp(_pending!.event);
        _lastStamp = DateTime.now();
        _pending = null;
      });
    }
  }

  void _fireStamp(StatEvent e) {
    final cfg = _stampConfigFor(e);
    if (cfg == null) return;
    setState(() {
      _stampLabel = cfg.label;
      _stampColor = cfg.color;
    });
    _stampCtrl.forward(from: 0);
  }

  _StampConfig? _stampConfigFor(StatEvent e) {
    switch (e.type) {
      case 'like':
        return e.isLocal
            ? const _StampConfig(label: 'LIKED', color: Color(0xFFFF3B5C))
            : const _StampConfig(label: 'NEW FAN', color: Color(0xFF00F0FF));
      case 'unlike':
        // Sello discreto para unlike — usamos gris claro
        return e.isLocal
            ? const _StampConfig(label: 'UNLIKED', color: Color(0xFF8678A8))
            : null;
      case 'view':
        // Solo los views REMOTOS muestran sello (sense of presence).
        // Los locales son del propio user y no aportan info nueva.
        return e.isLocal
            ? null
            : const _StampConfig(label: 'SEEN', color: Color(0xFF00F0FF));
      case 'download':
        return const _StampConfig(label: 'SAVED', color: Color(0xFFE6B655));
      default:
        return null;
    }
  }

  void _injectTicker(StatEvent e) {
    final cfg = _tickerConfigFor(e);
    if (cfg == null) return;
    setState(() {
      _items.insert(0, cfg);
      if (_items.length > 30) {
        _items.removeRange(30, _items.length);
      }
    });
  }

  _TickerItem? _tickerConfigFor(StatEvent e) {
    switch (e.type) {
      case 'like':
        return _TickerItem(
          text: e.isLocal ? '♥ +1 YOU' : '♥ +1 FAN',
          kind: _TickerKind.like,
          fresh: true,
        );
      case 'view':
        return _TickerItem(
          text: e.isLocal ? '👁 SEEN' : '👁 +1 LIVE',
          kind: _TickerKind.view,
          fresh: true,
        );
      case 'download':
        return const _TickerItem(
          text: '⤓ +1 SAVED',
          kind: _TickerKind.download,
          fresh: true,
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Allow taps to pass through to the underlying UI
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // ── Print stamp ─────────────────────────────────────────
            Center(
                child: _StampWidget(
                    controller: _stampCtrl,
                    label: _stampLabel,
                    color: _stampColor)),
            // ── Ticker tape (bottom) ────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _TickerWidget(
                  items: _items,
                  controller: _tickerCtrl,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── helpers ─────────────────────────────────────────────────────

class _StampConfig {
  final String label;
  final Color color;
  const _StampConfig({required this.label, required this.color});
}

class _PendingEvent {
  final StatEvent event;
  _PendingEvent(this.event);
}

enum _TickerKind { like, view, download, banner }

class _TickerItem {
  final String text;
  final _TickerKind kind;
  final bool fresh;
  const _TickerItem({
    required this.text,
    required this.kind,
    this.fresh = false,
  });
}

// ─── STAMP widget ────────────────────────────────────────────────

class _StampWidget extends StatelessWidget {
  final AnimationController controller;
  final String label;
  final Color color;

  const _StampWidget({
    required this.controller,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        if (controller.value == 0) return const SizedBox.shrink();
        final t = controller.value;
        // Map CSS keyframes stampHit to scale/opacity
        double scale;
        double opacity;
        if (t < 0.35) {
          final k = t / 0.35;
          scale = 2.2 + (0.9 - 2.2) * k;
          opacity = k;
        } else if (t < 0.55) {
          final k = (t - 0.35) / 0.2;
          scale = 0.9 + (1.05 - 0.9) * k;
          opacity = 1.0;
        } else if (t < 0.8) {
          final k = (t - 0.55) / 0.25;
          scale = 1.05 + (1.0 - 1.05) * k;
          opacity = 1.0;
        } else {
          final k = (t - 0.8) / 0.2;
          scale = 1.0;
          opacity = 1.0 - k;
        }
        opacity = opacity.clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: -18 * math.pi / 180,
            child: Transform.scale(
              scale: scale,
              child: _stampBody(),
            ),
          ),
        );
      },
    );
  }

  Widget _stampBody() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.18),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer solid ring (double border via two containers)
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 4),
            ),
          ),
          // Inner dashed ring drawn via CustomPaint
          Padding(
            padding: const EdgeInsets.all(10),
            child: CustomPaint(
              size: const Size(180, 180),
              painter: _DashedCirclePainter(
                color: color.withValues(alpha: 0.55),
              ),
            ),
          ),
          // Text block
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.blackOpsOne(
                  fontSize: 26,
                  color: color,
                  letterSpacing: 4,
                  shadows: [
                    Shadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'REGISTRADO · 2026 · MX',
                style: GoogleFonts.shareTechMono(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.85),
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    const dashCount = 32;
    const dashSweep = 2 * math.pi / dashCount * 0.55;
    final gap = 2 * math.pi / dashCount;
    for (int i = 0; i < dashCount; i++) {
      final start = i * gap;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) => old.color != color;
}

// ─── TICKER widget ───────────────────────────────────────────────

class _TickerWidget extends StatelessWidget {
  final List<_TickerItem> items;
  final AnimationController controller;

  const _TickerWidget({required this.items, required this.controller});

  static const _height = 30.0;

  Color _bgColor(_TickerKind k) {
    switch (k) {
      case _TickerKind.like:
        return Colors.black.withValues(alpha: 0.30);
      case _TickerKind.view:
        return Colors.white.withValues(alpha: 0.30);
      case _TickerKind.download:
        return const Color(0xFFE6B655).withValues(alpha: 0.45);
      case _TickerKind.banner:
        return Colors.black.withValues(alpha: 0.50);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txtStyle = GoogleFonts.shareTechMono(
      fontSize: 11,
      color: const Color(0xFF0B0020),
      letterSpacing: 1.4,
      fontWeight: FontWeight.bold,
    );

    return Container(
      height: _height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF2BD6), Color(0xFF00F0FF)],
        ),
        border: Border(
          top: BorderSide(color: Colors.white24, width: 1),
          bottom: BorderSide(color: Colors.white24, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          // LIVE label
          Container(
            width: 60,
            color: Colors.black,
            alignment: Alignment.center,
            child: Text(
              'LIVE',
              style: GoogleFonts.audiowide(
                fontSize: 11,
                color: const Color(0xFF00F0FF),
                letterSpacing: 3.2,
              ),
            ),
          ),
          // Scrolling track
          Expanded(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: controller,
                builder: (_, __) {
                  return _TickerTrack(
                    items: items,
                    progress: controller.value,
                    bgFor: _bgColor,
                    txtStyle: txtStyle,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TickerTrack extends StatelessWidget {
  final List<_TickerItem> items;
  final double progress;
  final Color Function(_TickerKind) bgFor;
  final TextStyle txtStyle;

  const _TickerTrack({
    required this.items,
    required this.progress,
    required this.bgFor,
    required this.txtStyle,
  });

  @override
  Widget build(BuildContext context) {
    // We render the items twice so the scroll can wrap seamlessly.
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(_chip(items[i], false));
    }
    for (var i = 0; i < items.length; i++) {
      children.add(_chip(items[i], true));
    }
    // estimated single-loop width — based on average chip ~110 px + gap 16
    final loopWidth = items.length * 126.0;
    final dx = -loopWidth * progress;

    return Transform.translate(
      offset: Offset(dx, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _chip(_TickerItem it, bool isDup) {
    final base = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: bgFor(it.kind),
        borderRadius: BorderRadius.circular(3),
        border: it.fresh && !isDup
            ? Border.all(color: Colors.white, width: 1.4)
            : null,
        boxShadow: it.fresh && !isDup
            ? const [
                BoxShadow(
                  color: Color(0xAAFFFFFF),
                  blurRadius: 6,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Text(it.text, style: txtStyle),
    );
    return base;
  }
}
