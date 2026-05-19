import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/hud_tokens.dart';
import '../../../../core/services/auto_rotate_service.dart';
import '../../../../core/services/wallpaper_engine_coordinator.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../pixora_daily/presentation/pixora_daily_page.dart';

/// Featured banner card on the Wallpapers home that drives discovery of
/// Pixora Daily — the auto-rotating wallpaper feature that competes with
/// Bing Spotlight on Windows.
///
/// Sits right after the HeroBanner. Tapping opens the dedicated
/// `PixoraDailyPage` where the user can configure interval / target /
/// category and toggle on.
///
/// Reactive to `WallpaperEngineCoordinator` so the copy updates between
/// "Activar Daily" (when off) and "Daily activo · cada X" (when on).
class PixoraDailyBanner extends StatefulWidget {
  const PixoraDailyBanner({super.key});

  @override
  State<PixoraDailyBanner> createState() => _PixoraDailyBannerState();
}

class _PixoraDailyBannerState extends State<PixoraDailyBanner>
    with TickerProviderStateMixin {
  bool _enabled = false;
  int _intervalMinutes = 0;

  // iOS — Concept #04 "Particle Orbit" (Eduardo 2026-05-18, replaced #05).
  // B&G — Concept #03 "Star Field Drift" (Eduardo 2026-05-18).
  // _orbitCtrl drives iOS orbiting particles + dashed ring rotation.
  // _starsCtrl drives B&G constellation drift, _scanCtrl drives twinkle.
  late final AnimationController _orbitCtrl;
  late final AnimationController _scanCtrl;
  late final AnimationController _starsCtrl;

  @override
  void initState() {
    super.initState();
    WallpaperEngineCoordinator.instance.addListener(_onEngineChanged);
    _loadStatus();
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _starsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 11000),
    )..repeat();
  }

  @override
  void dispose() {
    _orbitCtrl.dispose();
    _scanCtrl.dispose();
    _starsCtrl.dispose();
    WallpaperEngineCoordinator.instance.removeListener(_onEngineChanged);
    super.dispose();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final s = await AutoRotateService.instance.getStatus();
    if (!mounted) return;
    setState(() {
      _enabled = s['enabled'] == true;
      _intervalMinutes = s['intervalMinutes'] as int? ?? 30;
    });
  }

  String _intervalLabel(int m) {
    if (m < 60) return '$m min';
    if (m < 1440) return '${m ~/ 60} h';
    return '24 h';
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    // iOS White theme uses "Apple Blue Filled" — picked by user 2026-05-06
    // for high contrast on white app bg. Black & Gold keeps the original
    // gold/blue gradient (it has proper contrast over the dark background).
    final isLight = !h.isDark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PixoraDailyPage()),
            );
            _loadStatus();
          },
          borderRadius: BorderRadius.circular(16),
          child: isLight ? _buildLightTheme() : _buildDarkTheme(),
        ),
      ),
    );
  }

  /// iOS White theme — Apple Premium base (concept #01, 2026-05-15) +
  /// Particle Orbit overlay (concept #04, 2026-05-18). Two particles (cyan +
  /// mint) orbit the icon while a dashed ring rotates around it.
  Widget _buildLightTheme() {
    const appleBlue = Color(0xFF0A84FF);
    const appleBlueDeep = Color(0xFF0066CC);
    const cyan = Color(0xFF22D3EE);
    const mint = Color(0xFF6EE7B7);
    final radius = BorderRadius.circular(16);
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [appleBlue, appleBlueDeep],
            ),
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: appleBlue.withValues(alpha: 0.30),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.autorenew_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Pixora Daily',
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.05,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _enabled ? 'ACTIVO' : 'NUEVO',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _enabled
                          ? LocaleHelper.pick(
                              es: 'Cambia cada ${_intervalLabel(_intervalMinutes)}',
                              en: 'Changes every ${_intervalLabel(_intervalMinutes)}',
                            )
                          : LocaleHelper.pick(
                              es: 'Wallpapers aleatorios',
                              en: 'Random wallpapers',
                            ),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 22,
              ),
            ],
          ),
        ),
        // Orbit overlay — particles + dashed ring rotating around the icon.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: radius,
              child: AnimatedBuilder(
                animation: _orbitCtrl,
                builder: (_, __) {
                  return CustomPaint(
                    painter: _OrbitPainter(
                      progress: _orbitCtrl.value,
                      iconCenterX: 14 + 22, // padding + half icon width
                      color1: cyan,
                      color2: mint,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Black & Gold theme — Concept #01 "Strict Black & Gold" base (2026-05-15)
  /// + Concept #03 "Star Field Drift" overlay (2026-05-18). Gold star field
  /// drifts horizontally behind the content while a subset twinkles.
  Widget _buildDarkTheme() {
    const goldDeep = Color(0xFFD9B14A);
    const goldBright = Color(0xFFF5D676);
    const goldPale = Color(0xFFFBE9B6);
    final radius = BorderRadius.circular(16);
    return Stack(
      children: [
        // Star field layer — sits underneath everything, clipped to the card.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: radius,
              child: AnimatedBuilder(
                animation: Listenable.merge([_starsCtrl, _scanCtrl]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _StarFieldPainter(
                      drift: _starsCtrl.value,
                      twinkle: _scanCtrl.value,
                      starColor: goldBright,
                      glowColor: goldPale,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Content layer (original B&G card body).
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                goldDeep.withValues(alpha: 0.18),
                const Color(0xFF8A7A56).withValues(alpha: 0.08),
              ],
            ),
            borderRadius: radius,
            border: Border.all(
              color: goldDeep.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [goldDeep, goldBright],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: goldDeep.withValues(alpha: 0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.autorenew_rounded,
                  color: Color(0xFF070710),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Pixora Daily',
                          style: GoogleFonts.fraunces(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: goldDeep.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                            border: _enabled
                                ? Border.all(
                                    color: goldBright.withValues(alpha: 0.6),
                                    width: 0.5,
                                  )
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_enabled) ...[
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: goldBright,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: goldBright,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                _enabled ? 'ACTIVO' : 'NUEVO',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: goldBright,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _enabled
                          ? LocaleHelper.pick(
                              es: 'Cambia cada ${_intervalLabel(_intervalMinutes)}',
                              en: 'Changes every ${_intervalLabel(_intervalMinutes)}',
                            )
                          : LocaleHelper.pick(
                              es: 'Wallpapers aleatorios',
                              en: 'Random wallpapers',
                            ),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: goldBright.withValues(alpha: 0.7),
                size: 22,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// CustomPainter for B&G concept #03 "Star Field Drift" (2026-05-18).
///
/// Draws a fixed set of golden "stars" (small circles + halo) that drift
/// horizontally and twinkle. Positions are precomputed (not random per
/// paint) so they look like a real constellation, not noise.
///
/// [drift] 0..1 wraps the horizontal position.
/// [twinkle] 0..1 drives a sine phase per star (each star has its own offset).
class _StarFieldPainter extends CustomPainter {
  _StarFieldPainter({
    required this.drift,
    required this.twinkle,
    required this.starColor,
    required this.glowColor,
  });

  final double drift;
  final double twinkle;
  final Color starColor;
  final Color glowColor;

  // [xNormalized, yNormalized, radius, twinklePhaseOffset]
  // Hand-tuned constellation — feels intentional, not random.
  static const _stars = <List<double>>[
    [0.06, 0.22, 0.9, 0.00],
    [0.16, 0.68, 1.1, 0.32],
    [0.27, 0.40, 0.7, 0.61],
    [0.42, 0.16, 1.0, 0.12],
    [0.55, 0.78, 1.2, 0.50],
    [0.66, 0.32, 0.8, 0.81],
    [0.77, 0.86, 1.0, 0.24],
    [0.85, 0.48, 1.1, 0.41],
    [0.93, 0.22, 0.9, 0.73],
    [0.20, 0.92, 0.7, 0.93],
    [0.49, 0.52, 0.6, 0.18],
    [0.72, 0.10, 0.9, 0.57],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final s in _stars) {
      // Horizontal drift, wraps 0..1
      final xRaw = s[0] + drift * 0.55;
      final xWrapped = xRaw - xRaw.floorToDouble();
      final cx = xWrapped * size.width;
      final cy = s[1] * size.height;
      final r = s[2];

      // Per-star twinkle phase
      final phase = (twinkle + s[3]) % 1.0;
      final twk = (math.sin(phase * 2 * math.pi) + 1) / 2; // 0..1
      final brightness = 0.35 + (twk * 0.65);

      // Halo (soft glow)
      paint.color = glowColor.withValues(alpha: brightness * 0.28);
      canvas.drawCircle(Offset(cx, cy), r * 3.2, paint);
      // Star core
      paint.color = starColor.withValues(alpha: brightness * 0.95);
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_StarFieldPainter old) =>
      old.drift != drift ||
      old.twinkle != twinkle ||
      old.starColor != starColor ||
      old.glowColor != glowColor;
}

/// CustomPainter for iOS concept #04 "Particle Orbit" (2026-05-18).
///
/// Draws two glowing particles ([color1] + [color2]) on an elliptical orbit
/// around the icon, plus a slowly rotating dashed ring at a slightly bigger
/// radius. The two particles are 180° out of phase so one is always visible
/// when the other passes behind the icon.
///
/// [progress] 0..1 = one full revolution. [iconCenterX] is the X coord
/// (in painter space) of the icon center; Y is derived from size.height/2.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.progress,
    required this.iconCenterX,
    required this.color1,
    required this.color2,
  });

  final double progress;
  final double iconCenterX;
  final Color color1;
  final Color color2;

  // Elliptical orbit — wider than tall because the banner is short.
  static const _orbitRx = 32.0;
  static const _orbitRy = 22.0;
  // Dashed ring outside the orbit.
  static const _ringRadius = 30.0;
  static const _ringDashes = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = iconCenterX;
    final cy = size.height / 2;

    // 1. Dashed ring rotating slowly (counter-clockwise feels less aggressive)
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-progress * 2 * math.pi);
    final ringPaint = Paint()
      ..color = color1.withValues(alpha: 0.45)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _ringDashes; i++) {
      if (i.isOdd) continue; // alternate dashes
      final a1 = (i / _ringDashes) * 2 * math.pi;
      final a2 = ((i + 1) / _ringDashes) * 2 * math.pi;
      final p1 = Offset(
        math.cos(a1) * _ringRadius,
        math.sin(a1) * _ringRadius,
      );
      final p2 = Offset(
        math.cos(a2) * _ringRadius,
        math.sin(a2) * _ringRadius,
      );
      canvas.drawLine(p1, p2, ringPaint);
    }
    canvas.restore();

    // 2. Orbiting particles (cyan + mint, 180° apart)
    _drawParticle(canvas, cx, cy, progress, color1);
    _drawParticle(canvas, cx, cy, (progress + 0.5) % 1.0, color2);
  }

  void _drawParticle(
    Canvas canvas,
    double cx,
    double cy,
    double t,
    Color color,
  ) {
    final angle = t * 2 * math.pi;
    final px = cx + math.cos(angle) * _orbitRx;
    final py = cy + math.sin(angle) * _orbitRy;
    // Particles behind icon (top half) dim slightly for depth
    final depth = (math.sin(angle) + 1) / 2; // 0 top, 1 bottom
    final alpha = 0.55 + depth * 0.45;

    // Soft halo
    canvas.drawCircle(
      Offset(px, py),
      6.5,
      Paint()..color = color.withValues(alpha: alpha * 0.35),
    );
    // Bright core
    canvas.drawCircle(
      Offset(px, py),
      2.8,
      Paint()..color = color.withValues(alpha: alpha),
    );
    // White hot center
    canvas.drawCircle(
      Offset(px, py),
      1.2,
      Paint()..color = Colors.white.withValues(alpha: alpha * 0.95),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.progress != progress ||
      old.iconCenterX != iconCenterX ||
      old.color1 != color1 ||
      old.color2 != color2;
}
