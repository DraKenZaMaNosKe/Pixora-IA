import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/wallpaper_stats_service.dart';

/// 2026-06-14 — Combo 2+3+4+5 elegido por Eduardo para las cards del
/// grid LIVE. Envuelve cualquier `child` (la card visual) y le agrega:
///
///  · FLOATING EMOJI RISE — emoji del tipo de evento sube desde el
///    contador correspondiente con motion trail (max 1 vivo a la vez).
///  · MINI STAMP CORNER — sello chico tipo LIKED/SEEN/SAVED en una
///    de 3 esquinas según el tipo (max 1 vivo a la vez).
///  · HEARTBEAT CARD — la card entera hace breath pulse (scale 1.03)
///    + border glow del color del tipo (600 ms).
///  · GHOST CURSOR TAP — cursor fantasma + ripple en posición random
///    + label "@anon ♥" (max 1 vivo a la vez).
///
/// **Anti-saturación** (importante para escala alta):
///  · Cada card solo dispara 1 batch de efectos cada [_cardCooldown].
///  · Si llegan múltiples eventos dentro de la ventana, solo el
///    último se aplica al final (drop intermedios, mismo enfoque del
///    detail overlay).
///  · Replace mode: cada tipo de efecto tiene UNA instancia viva por
///    card — al disparar uno nuevo el anterior se reemplaza (ningún
///    AnimationController se acumula).
///  · IgnorePointer en los overlays para no romper el GestureDetector
///    del card padre.
class LiveGridCardOverlay extends StatefulWidget {
  final String wallpaperId;
  final double borderRadius;
  final Widget child;

  /// Posición del pill `⊙ N LIVE` ambient. Default: top-left (las cards
  /// LIVE ya tienen un HoloFoilPill en top-right).
  final Alignment presenceAlignment;

  const LiveGridCardOverlay({
    super.key,
    required this.wallpaperId,
    required this.child,
    this.borderRadius = 14,
    this.presenceAlignment = Alignment.topLeft,
  });

  @override
  State<LiveGridCardOverlay> createState() => _LiveGridCardOverlayState();
}

class _LiveGridCardOverlayState extends State<LiveGridCardOverlay>
    with TickerProviderStateMixin {
  // ── per-card subscription + throttle ────────────────────────────
  StreamSubscription<StatEvent>? _sub;
  static const _cardCooldown = Duration(milliseconds: 850);
  DateTime? _lastFired;
  Timer? _pendingTimer;
  StatEvent? _pending;

  // ── effect state — single instance per type ─────────────────────
  late final AnimationController _heartbeatCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _emojiCtrl;
  late final AnimationController _stampCtrl;
  late final AnimationController _ghostCtrl;

  Color _glowColor = const Color(0xFFFF3B5C);

  // emoji
  String _emojiChar = '♥';
  Color _emojiColor = const Color(0xFFFF3B5C);
  Offset _emojiOrigin = const Offset(0, 0); // bottom-left relative
  double _emojiCurveX = 6;

  // stamp
  String _stampLabel = 'LIKED';
  Color _stampColor = const Color(0xFFFF3B5C);
  AlignmentGeometry _stampAlign = Alignment.bottomLeft;

  // ghost
  Offset _ghostPos = const Offset(40, 90);
  Color _ghostColor = const Color(0xFF00F0FF);
  String _ghostLabel = '@anon ♥';

  // ⊙ N LIVE presence — small simulated number that fluctuates
  late int _presenceN;
  Timer? _presenceTimer;
  static final _rnd = math.Random();
  static const _anonNames = [
    '@anon',
    '@mx',
    '@otaku',
    '@dragon',
    '@gdl',
    '@bulmista',
    '@luffyx',
    '@neon',
    '@vaporwave',
  ];

  @override
  void initState() {
    super.initState();
    _heartbeatCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));
    _emojiCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _stampCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _ghostCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));

    _presenceN = 2 + _rnd.nextInt(5);

    _sub = WallpaperStatsService.instance.statsEventStream.listen(_onEvent);

    // ambient flicker of the presence number every 6-12s
    _scheduleNextPresenceFlicker();
  }

  void _scheduleNextPresenceFlicker() {
    _presenceTimer?.cancel();
    final delayMs = 6000 + _rnd.nextInt(6000);
    _presenceTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      setState(() {
        final delta = _rnd.nextBool() ? 1 : -1;
        _presenceN = (_presenceN + delta).clamp(1, 9);
      });
      _scheduleNextPresenceFlicker();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pendingTimer?.cancel();
    _presenceTimer?.cancel();
    _heartbeatCtrl.dispose();
    _glowCtrl.dispose();
    _emojiCtrl.dispose();
    _stampCtrl.dispose();
    _ghostCtrl.dispose();
    super.dispose();
  }

  // ── event dispatcher ────────────────────────────────────────────
  void _onEvent(StatEvent e) {
    if (!mounted) return;
    if (e.wallpaperId != widget.wallpaperId) return;
    // Skip the user's own local events on the grid card — animations
    // here are for AMBIENT social proof (otros usuarios). Local events
    // ya tienen su feedback en la pantalla detail (sello + ticker).
    if (e.isLocal) return;
    if (!_isAmbientType(e.type)) return;

    final now = DateTime.now();
    final readyTime = _lastFired == null ? now : _lastFired!.add(_cardCooldown);
    if (!now.isBefore(readyTime)) {
      _fireBatch(e);
      _lastFired = now;
    } else {
      _pending = e;
      _pendingTimer?.cancel();
      _pendingTimer = Timer(readyTime.difference(now), () {
        if (!mounted || _pending == null) return;
        _fireBatch(_pending!);
        _pending = null;
        _lastFired = DateTime.now();
      });
    }
  }

  bool _isAmbientType(String t) =>
      t == 'like' || t == 'view' || t == 'download';

  Color _colorFor(String type) {
    switch (type) {
      case 'like':
        return const Color(0xFFFF3B5C);
      case 'view':
        return const Color(0xFF00F0FF);
      case 'download':
        return const Color(0xFFE6B655);
    }
    return const Color(0xFFE6B655);
  }

  String _emojiFor(String type) {
    switch (type) {
      case 'like':
        return '♥';
      case 'view':
        return '👁';
      case 'download':
        return '⤓';
    }
    return '★';
  }

  String _stampLabelFor(String type) {
    switch (type) {
      case 'like':
        return 'NEW FAN';
      case 'view':
        return 'SEEN';
      case 'download':
        return 'SAVED';
    }
    return '★';
  }

  AlignmentGeometry _stampAlignFor(String type) {
    switch (type) {
      case 'like':
        return Alignment.bottomLeft;
      case 'view':
        return const Alignment(-1, -0.5); // upper-left below LIVE pill
      case 'download':
        return Alignment.bottomRight;
    }
    return Alignment.bottomLeft;
  }

  void _fireBatch(StatEvent e) {
    if (!mounted) return;
    final color = _colorFor(e.type);

    setState(() {
      // heartbeat + glow
      _glowColor = color;
      _heartbeatCtrl.forward(from: 0);
      _glowCtrl.forward(from: 0);

      // floating emoji
      _emojiChar = _emojiFor(e.type);
      _emojiColor = color;
      _emojiCurveX = _rnd.nextDouble() * 14 - 7;
      _emojiOrigin = _emojiOriginFor(e.type);
      _emojiCtrl.forward(from: 0);

      // mini stamp
      _stampLabel = _stampLabelFor(e.type);
      _stampColor = color;
      _stampAlign = _stampAlignFor(e.type);
      _stampCtrl.forward(from: 0);

      // ghost cursor — random position inside the card
      _ghostColor = color;
      _ghostPos = _ghostRandomPos();
      _ghostLabel =
          '${_anonNames[_rnd.nextInt(_anonNames.length)]} ${_emojiChar}';
      _ghostCtrl.forward(from: 0);
    });
  }

  /// Origen relativo del emoji flotante según el counter del que sale.
  /// Coords son fracciones de width/height del card: (x, y) en [0,1].
  Offset _emojiOriginFor(String type) {
    switch (type) {
      case 'like':
        return const Offset(0.18, 0.85);
      case 'view':
        return const Offset(0.50, 0.85);
      case 'download':
        return const Offset(0.82, 0.85);
    }
    return const Offset(0.5, 0.85);
  }

  Offset _ghostRandomPos() {
    // Avoid the top badge area + bottom strip
    final fx = 0.20 + _rnd.nextDouble() * 0.60;
    final fy = 0.30 + _rnd.nextDouble() * 0.35;
    return Offset(fx, fy);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _heartbeatCtrl,
      builder: (_, child) {
        // Map heartbeat: 0→1 with elastic peak at 0.5 (scale 1.03)
        final t = _heartbeatCtrl.value;
        double scale;
        if (t == 0) {
          scale = 1.0;
        } else if (t < 0.5) {
          scale = 1.0 + 0.03 * (t / 0.5);
        } else {
          scale = 1.03 - 0.03 * ((t - 0.5) / 0.5);
        }
        return Transform.scale(scale: scale, child: child);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The actual card
          widget.child,
          // Overlays clipped to the card border
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: LayoutBuilder(
                  builder: (_, c) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildGlowBorder(),
                      _buildFloatingEmoji(c.maxWidth, c.maxHeight),
                      _buildMiniStamp(),
                      _buildGhost(c.maxWidth, c.maxHeight),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Presence pill (NOT clipped — sits on top of card edge)
          _buildPresencePill(),
        ],
      ),
    );
  }

  Widget _buildGlowBorder() {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (_, __) {
        final t = _glowCtrl.value;
        // Curve: 0 → 1 → 0 (peak at 0.3)
        double a;
        if (t == 0) {
          a = 0;
        } else if (t < 0.3) {
          a = t / 0.3;
        } else {
          a = 1 - (t - 0.3) / 0.7;
        }
        a = a.clamp(0.0, 1.0);
        if (a == 0) return const SizedBox.shrink();
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _glowColor.withValues(alpha: a),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: _glowColor.withValues(alpha: a * 0.55),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFloatingEmoji(double w, double h) {
    return AnimatedBuilder(
      animation: _emojiCtrl,
      builder: (_, __) {
        final t = _emojiCtrl.value;
        if (t == 0) return const SizedBox.shrink();
        // 4-stop curve from the mockup keyframes
        double opacity;
        double sc;
        double yOff;
        double xOff;
        if (t < 0.15) {
          final k = t / 0.15;
          opacity = k;
          sc = 0.5 + (1.3 - 0.5) * k;
          yOff = 0 + (-10 - 0) * k;
          xOff = 0;
        } else if (t < 0.30) {
          final k = (t - 0.15) / 0.15;
          opacity = 1.0;
          sc = 1.3 + (1.0 - 1.3) * k;
          yOff = -10 + (-40 - -10) * k;
          xOff = _emojiCurveX * k;
        } else {
          final k = (t - 0.30) / 0.70;
          opacity = 1.0 - k;
          sc = 1.0 - 0.1 * k;
          yOff = -40 + (-120 - -40) * k;
          xOff = _emojiCurveX + _emojiCurveX * k;
        }
        opacity = opacity.clamp(0.0, 1.0);
        // base position from origin (relative to card)
        final baseX = _emojiOrigin.dx * w;
        final baseY = _emojiOrigin.dy * h;
        return Positioned(
          left: baseX + xOff - 10,
          top: baseY + yOff - 10,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: sc,
              child: Text(
                _emojiChar,
                style: TextStyle(
                  fontSize: 18,
                  color: _emojiColor,
                  shadows: [
                    Shadow(
                        color: _emojiColor.withValues(alpha: 0.7),
                        blurRadius: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniStamp() {
    return AnimatedBuilder(
      animation: _stampCtrl,
      builder: (_, __) {
        final t = _stampCtrl.value;
        if (t == 0) return const SizedBox.shrink();
        double opacity;
        double sc;
        if (t < 0.25) {
          final k = t / 0.25;
          opacity = k;
          sc = 2.2 + (0.85 - 2.2) * k;
        } else if (t < 0.5) {
          final k = (t - 0.25) / 0.25;
          opacity = 1;
          sc = 0.85 + (1.0 - 0.85) * k;
        } else if (t < 0.8) {
          opacity = 1;
          sc = 1.0;
        } else {
          final k = (t - 0.8) / 0.2;
          opacity = 1 - k;
          sc = 1.0;
        }
        opacity = opacity.clamp(0.0, 1.0);
        return Align(
          alignment: _stampAlign,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Opacity(
              opacity: opacity,
              child: Transform.rotate(
                angle: -15 * math.pi / 180,
                child: Transform.scale(
                  scale: sc,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _stampColor, width: 2),
                      gradient: RadialGradient(
                        colors: [
                          _stampColor.withValues(alpha: 0.20),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.7],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _stampColor.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _stampLabel,
                          style: GoogleFonts.blackOpsOne(
                            fontSize: 8,
                            color: _stampColor,
                            letterSpacing: 1.2,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '2026',
                          style: GoogleFonts.shareTechMono(
                            fontSize: 6,
                            color: _stampColor.withValues(alpha: 0.85),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGhost(double w, double h) {
    return AnimatedBuilder(
      animation: _ghostCtrl,
      builder: (_, __) {
        final t = _ghostCtrl.value;
        if (t == 0) return const SizedBox.shrink();
        double cursorOpacity;
        double cursorScale;
        if (t < 0.25) {
          final k = t / 0.25;
          cursorOpacity = k;
          cursorScale = 1.4 + (1.0 - 1.4) * k;
        } else if (t < 0.5) {
          final k = (t - 0.25) / 0.25;
          cursorOpacity = 1;
          cursorScale = 1.0 + (0.7 - 1.0) * k;
        } else if (t < 0.75) {
          final k = (t - 0.5) / 0.25;
          cursorOpacity = 1;
          cursorScale = 0.7 + (1.0 - 0.7) * k;
        } else {
          final k = (t - 0.75) / 0.25;
          cursorOpacity = 1 - k;
          cursorScale = 1.0 + 0.1 * k;
        }
        cursorOpacity = cursorOpacity.clamp(0.0, 1.0);

        // ripple: 0→1 expanding
        final rippleOpacity = (1.0 - t).clamp(0.0, 0.8);
        final rippleScale = 0.4 + 5.0 * t;

        // label opacity
        double lblOpacity;
        if (t < 0.25) {
          lblOpacity = t / 0.25;
        } else if (t < 0.75) {
          lblOpacity = 1;
        } else {
          lblOpacity = 1 - (t - 0.75) / 0.25;
        }
        lblOpacity = lblOpacity.clamp(0.0, 1.0);

        final cx = _ghostPos.dx * w;
        final cy = _ghostPos.dy * h;

        return Positioned.fill(
          child: Stack(
            children: [
              // ripple
              Positioned(
                left: cx - 7,
                top: cy - 7,
                child: Opacity(
                  opacity: rippleOpacity,
                  child: Transform.scale(
                    scale: rippleScale,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _ghostColor, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
              // cursor
              Positioned(
                left: cx - 9,
                top: cy - 9,
                child: Opacity(
                  opacity: cursorOpacity,
                  child: Transform.scale(
                    scale: cursorScale,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _ghostColor.withValues(alpha: 0.3),
                        border: Border.all(color: _ghostColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: _ghostColor.withValues(alpha: 0.7),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // label
              Positioned(
                left: cx + 12,
                top: cy - 6,
                child: Opacity(
                  opacity: lblOpacity,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _ghostLabel,
                      style: GoogleFonts.shareTechMono(
                        fontSize: 8,
                        color: _ghostColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresencePill() {
    return Align(
      alignment: widget.presenceAlignment,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFE6B655).withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PresenceDot(),
              const SizedBox(width: 4),
              Text(
                '$_presenceN LIVE',
                style: GoogleFonts.shareTechMono(
                  fontSize: 8,
                  color: const Color(0xFFE6B655),
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresenceDot extends StatefulWidget {
  @override
  State<_PresenceDot> createState() => _PresenceDotState();
}

class _PresenceDotState extends State<_PresenceDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        // 0 → 0.7 expand glow, 0.7 → 1 reset
        final glow = (t < 0.7 ? t / 0.7 : 0.0).clamp(0.0, 1.0);
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF3DE69A),
            boxShadow: [
              BoxShadow(
                color:
                    const Color(0xFF3DE69A).withValues(alpha: 0.6 * (1 - glow)),
                blurRadius: 4,
                spreadRadius: 4 * glow,
              ),
            ],
          ),
        );
      },
    );
  }
}
