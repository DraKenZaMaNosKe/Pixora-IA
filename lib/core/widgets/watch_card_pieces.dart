import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/hud_tokens.dart';
import '../services/wallpaper_stats_service.dart';

/// Watch Brand Cartouche pill (concept #04, Eduardo 2026-05-16).
/// Charcoal/dark cartucho con dot ticking cada 1.6s — Apple Watch
/// complication vibe. Reemplaza el NEW pill sólido viejo en LIVE cards.
class WatchCartouchePill extends StatefulWidget {
  const WatchCartouchePill({super.key, required this.label});
  final String label;

  @override
  State<WatchCartouchePill> createState() => _WatchCartouchePillState();
}

class _WatchCartouchePillState extends State<WatchCartouchePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick;

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIos = context.hud.isIosStyle;
    final bgTop = isIos ? const Color(0xFF2C2E33) : const Color(0xFF1A1A26);
    final bgBot = isIos ? const Color(0xFF1C1E22) : const Color(0xFF0A0A14);
    final border = isIos ? const Color(0xFF3A3D44) : const Color(0xFF3A3214);
    final textColor = isIos ? const Color(0xFFF3F3F5) : const Color(0xFFF5D676);
    final dotColor = isIos ? const Color(0xFFFF453A) : const Color(0xFFF5D676);

    return AnimatedBuilder(
      animation: _tick,
      builder: (_, __) {
        final v = _tick.value;
        final dotAlpha = v < 0.5 ? 1.0 : 0.45;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgTop, bgBot],
            ),
            border: Border.all(color: border, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor.withValues(alpha: dotAlpha),
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.4 * dotAlpha),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                widget.label.toUpperCase(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                  letterSpacing: 1.4,
                  height: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Activity Rings stats (concept #04, Eduardo 2026-05-16).
/// Tres conic-gradient rings (likes/views/downloads) tipo Apple Watch.
/// Cada ring se llena con animación al aparecer → social proof épico.
class ActivityRings extends StatefulWidget {
  const ActivityRings({super.key, required this.wallpaperId});
  final String wallpaperId;

  @override
  State<ActivityRings> createState() => _ActivityRingsState();
}

class _ActivityRingsState extends State<ActivityRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill;
  late final WallpaperStatsService _service;
  StreamSubscription? _sub;
  Map<String, int> _stats = {'likes': 0, 'views': 0, 'downloads': 0};

  @override
  void initState() {
    super.initState();
    _service = WallpaperStatsService.instance;
    _stats = _service.getStats(widget.wallpaperId);
    _fill = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _sub = _service.statsStream.listen((all) {
      final fresh = all[widget.wallpaperId];
      if (fresh != null && mounted) {
        setState(() => _stats = fresh);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _fill.dispose();
    super.dispose();
  }

  static const _maxLikes = 50.0;
  static const _maxViews = 500.0;
  static const _maxDownloads = 100.0;

  @override
  Widget build(BuildContext context) {
    final isIos = context.hud.isIosStyle;
    final likes = (_stats['likes'] ?? 0).toDouble();
    final views = (_stats['views'] ?? 0).toDouble();
    final downloads = (_stats['downloads'] ?? 0).toDouble();

    final likeColor = isIos ? const Color(0xFFFF453A) : const Color(0xFFF5D676);
    final viewColor = isIos ? const Color(0xFF0A84FF) : const Color(0xFFD4AF37);
    final downloadColor =
        isIos ? const Color(0xFF30D158) : const Color(0xFFC49245);
    final innerBg = isIos ? const Color(0xFF1C1E22) : const Color(0xFF0A0A14);
    final labelColor = isIos ? Colors.white : const Color(0xFFF5D676);

    return AnimatedBuilder(
      animation: _fill,
      builder: (_, __) {
        final t = Curves.easeOutCubic.transform(_fill.value);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Ring(
              value: ((likes / _maxLikes) * t).clamp(0.0, 1.0),
              color: likeColor,
              innerBg: innerBg,
              count: likes.toInt(),
              label: 'LIKES',
              labelColor: labelColor,
            ),
            const SizedBox(width: 12),
            _Ring(
              value: ((views / _maxViews) * t).clamp(0.0, 1.0),
              color: viewColor,
              innerBg: innerBg,
              count: views.toInt(),
              label: 'VIEWS',
              labelColor: labelColor,
            ),
            const SizedBox(width: 12),
            _Ring(
              value: ((downloads / _maxDownloads) * t).clamp(0.0, 1.0),
              color: downloadColor,
              innerBg: innerBg,
              count: downloads.toInt(),
              label: 'DLDS',
              labelColor: labelColor,
            ),
          ],
        );
      },
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.value,
    required this.color,
    required this.innerBg,
    required this.count,
    required this.label,
    required this.labelColor,
  });
  final double value;
  final Color color;
  final Color innerBg;
  final int count;
  final String label;
  final Color labelColor;

  String _format(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CustomPaint(
            painter: _RingPainter(
              value: value,
              color: color,
              innerBg: innerBg,
            ),
            child: Center(
              child: Text(
                _format(count),
                style: GoogleFonts.inter(
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 5.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            height: 1.5,
            color: labelColor.withValues(alpha: 0.70),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.innerBg,
  });
  final double value;
  final Color color;
  final Color innerBg;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const ringWidth = 2.5;
    final radius = size.width / 2;

    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;
    canvas.drawCircle(center, radius - ringWidth / 2, bgPaint);

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - ringWidth / 2),
      -3.1415 / 2,
      2 * 3.1415 * value,
      false,
      progressPaint,
    );

    final fillPaint = Paint()..color = innerBg;
    canvas.drawCircle(center, radius - ringWidth - 0.5, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color || old.innerBg != innerBg;
}
