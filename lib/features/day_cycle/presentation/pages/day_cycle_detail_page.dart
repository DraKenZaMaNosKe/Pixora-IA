import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/ad_service.dart';
import '../../../../core/services/day_cycle_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../../core/widgets/watch_card_pieces.dart';
import '../../data/models/day_cycle_theme.dart';
import '../../providers/day_cycle_providers.dart';

/// DAY CYCLE Detail — Astronomical Almanac (concept #01, picked by
/// Eduardo 2026-05-16). 19th-century observatory journal aesthetic:
/// dark cosmic bg + starfield drift, brass compass rose rotating over
/// the current phase hero, continuous panorama strip of the 4 phases,
/// 4 almanac entries with Roman numeral chapter markers (I. AURORA,
/// II. MERIDIANO, III. CREPÚSCULO, IV. NOCTURNO), brass-gold sticky
/// APPLY CTA.
class DayCycleDetailPage extends ConsumerStatefulWidget {
  final DayCycleTheme theme;
  const DayCycleDetailPage({super.key, required this.theme});

  @override
  ConsumerState<DayCycleDetailPage> createState() => _DayCycleDetailPageState();
}

class _DayCycleDetailPageState extends ConsumerState<DayCycleDetailPage>
    with TickerProviderStateMixin {
  static const _bg = Color(0xFF050514);
  static const _bgMid = Color(0xFF0A0A1F);
  static const _surface = Color(0xFF12122A);
  static const _brass = Color(0xFFD4AF37);
  static const _brassBright = Color(0xFFF5D676);
  static const _brassDim = Color(0xFF8B7228);
  static const _ivory = Color(0xFFE8DCC0);
  static const _ivoryDim = Color(0xFF9A988E);

  bool _isActivating = false;
  String _progressText = '';
  double _downloadFraction = 0.0;
  LoadingPhase _loadingPhase = LoadingPhase.downloading;

  late final AnimationController _compassCtrl;
  late final AnimationController _starCtrl;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _compassCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
    _starCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    WallpaperStatsService.instance.trackView('daycycle_${widget.theme.id}');
  }

  @override
  void dispose() {
    _compassCtrl.dispose();
    _starCtrl.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _isActivating = true;
      _progressText = LocaleHelper.pick(es: 'Preparando…', en: 'Preparing…');
    });
    AdService.instance.showInterstitialAd(
      placement: 'day_cycle_apply',
      onAdDismissed: () {
        if (mounted) _doActivate();
      },
    );
  }

  Future<void> _doActivate() async {
    WallpaperStatsService.instance.trackDownload('daycycle_${widget.theme.id}');
    if (mounted) {
      setState(() {
        _loadingPhase = LoadingPhase.downloading;
        _progressText =
            LocaleHelper.pick(es: 'Descargando…', en: 'Downloading…');
        _downloadFraction = 0.0;
      });
    }
    final success = await DayCycleService.instance.activate(
      widget.theme,
      target: 0,
      onProgress: (current, total) {
        if (mounted) {
          setState(() {
            _progressText = LocaleHelper.pick(
              es: 'Descargando $current/$total…',
              en: 'Downloading $current/$total…',
            );
            _downloadFraction = current / total;
          });
        }
      },
    );
    if (!mounted) return;
    if (success) {
      WallpaperStatsService.instance
          .trackInstall('daycycle_${widget.theme.id}');
      ref.read(activeDayCycleIdProvider.notifier).state = widget.theme.id;
      setState(() {
        _loadingPhase = LoadingPhase.done;
        _progressText = LocaleHelper.pick(
          es: '${widget.theme.name} activado',
          en: '${widget.theme.name} activated',
        );
      });
    } else {
      setState(() {
        _loadingPhase = LoadingPhase.error;
        _progressText = LocaleHelper.pick(
          es: 'No se pudo activar. Revisa tu conexión.',
          en: 'Failed to activate. Check your connection.',
        );
      });
    }
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      setState(() {
        _isActivating = false;
        _progressText = '';
      });
    }
  }

  Future<void> _deactivate() async {
    await DayCycleService.instance.deactivate();
    if (mounted) {
      ref.read(activeDayCycleIdProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocaleHelper.pick(
            es: 'Day cycle desactivado',
            en: 'Day cycle deactivated',
          )),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final isActive = ref.watch(activeDayCycleIdProvider) == t.id;
    final phaseIdx = _currentPhaseIndex(_now);
    final phaseUrl = _phaseUrl(phaseIdx);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Background gradient
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.8),
                  radius: 1.3,
                  colors: [_bgMid, _bg],
                ),
              ),
            ),
          ),
          // Starfield drift
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _starCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _AlmanacStarPainter(progress: _starCtrl.value),
                ),
              ),
            ),
          ),
          // Content
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _heroWithCompass(phaseUrl, phaseIdx)),
              SliverToBoxAdapter(child: _titleBlock()),
              SliverToBoxAdapter(child: _panoramaStrip()),
              SliverToBoxAdapter(child: _description()),
              SliverToBoxAdapter(child: _almanacHeader()),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _almanacEntry(i, phaseIdx == i),
                  childCount: 4,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
          // Sticky bottom CTA
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottomCta(isActive),
          ),
          // Loading overlay
          LoadingOverlay(
            visible: _isActivating,
            progress: _downloadFraction > 0 ? _downloadFraction : null,
            status: _progressText,
            accentColor: _brassBright,
            phase: _loadingPhase,
          ),
        ],
      ),
    );
  }

  // ── Hero with compass rose overlay ─────────────────────────────────
  Widget _heroWithCompass(String phaseUrl, int phaseIdx) {
    return SizedBox(
      height: 320,
      child: Stack(
        children: [
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: phaseUrl,
              fit: BoxFit.cover,
              memCacheWidth: 800,
              placeholder: (_, __) => Container(color: _surface),
              errorWidget: (_, __, ___) => Container(color: _surface),
            ),
          ),
          // Cosmic gradient overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    _bg.withValues(alpha: 0.85),
                    _bg,
                  ],
                  stops: const [0.0, 0.35, 0.85, 1.0],
                ),
              ),
            ),
          ),
          // Back arrow top-left
          Positioned(
            top: 50,
            left: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(
                  side: BorderSide(color: _brassDim, width: 0.8)),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: _brassBright),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          // Top-right: mono eyebrow + activity rings
          Positioned(
            top: 56,
            right: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '// ALMANAC · DOC-VII',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _brassDim,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                ActivityRings(wallpaperId: 'daycycle_${widget.theme.id}'),
              ],
            ),
          ),
          // Compass rose centered, rotating
          Center(
            child: AnimatedBuilder(
              animation: _compassCtrl,
              builder: (_, __) => CustomPaint(
                size: const Size(160, 160),
                painter: _CompassRosePainter(
                  rotation: _compassCtrl.value * 2 * math.pi,
                  activeIndex: phaseIdx,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Title block (Cinzel + brass) ───────────────────────────────────
  Widget _titleBlock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleHelper.pick(es: 'CICLO N.º VII', en: 'CYCLE N.º VII'),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _brass,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.theme.name.toUpperCase(),
            style: GoogleFonts.cinzel(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: _ivory,
              letterSpacing: 2,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: _brass.withValues(alpha: 0.5)),
        ],
      ),
    );
  }

  // ── Continuous panorama strip of the 4 phases stitched ─────────────
  Widget _panoramaStrip() {
    final urls = _allPhaseUrls();
    final markerLeft = _dayFraction(_now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 60,
              child: LayoutBuilder(
                builder: (ctx, c) {
                  final w = c.maxWidth;
                  return Stack(
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < urls.length; i++)
                            Expanded(
                              child: ClipRect(
                                child: CachedNetworkImage(
                                  imageUrl: urls[i],
                                  fit: BoxFit.cover,
                                  memCacheWidth: 400,
                                  placeholder: (_, __) =>
                                      Container(color: _surface),
                                  errorWidget: (_, __, ___) =>
                                      Container(color: _surface),
                                ),
                              ),
                            ),
                        ],
                      ),
                      // Brass border frame
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: _brass, width: 1),
                            ),
                          ),
                        ),
                      ),
                      // Gold marker at current time fraction
                      Positioned(
                        left: (markerLeft * w).clamp(0.0, w - 2),
                        top: -3,
                        bottom: -3,
                        width: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _brassBright,
                            boxShadow: [
                              BoxShadow(
                                color: _brassBright.withValues(alpha: 0.8),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final h in ['06', '12', '18', '24'])
                Text(
                  h,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: _ivoryDim,
                    letterSpacing: 0.4,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Description (Cormorant italic) ─────────────────────────────────
  Widget _description() {
    if (widget.theme.description.isEmpty) {
      return const SizedBox(height: 12);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      child: Text(
        widget.theme.description,
        style: GoogleFonts.cormorantGaramond(
          fontSize: 16,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          color: _ivory.withValues(alpha: 0.82),
          height: 1.55,
        ),
      ),
    );
  }

  // ── "ENTRADAS DEL ALMANAQUE" header ───────────────────────────────
  Widget _almanacHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 1,
            color: _brass.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 10),
          Text(
            LocaleHelper.pick(
              es: 'ENTRADAS DEL ALMANAQUE',
              en: 'ALMANAC ENTRIES',
            ),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _brass,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: _brass.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  // ── Single almanac entry (one of the 4 phases) ────────────────────
  Widget _almanacEntry(int idx, bool isCurrent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.55),
          border: Border.all(
            color: isCurrent ? _brassBright : _brass.withValues(alpha: 0.2),
            width: isCurrent ? 1.4 : 0.8,
          ),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: _brassBright.withValues(alpha: 0.25),
                    blurRadius: 18,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Gold spine if current
              Container(
                width: isCurrent ? 3 : 0,
                color: isCurrent ? _brassBright : Colors.transparent,
              ),
              // Phase image
              SizedBox(
                width: 110,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedNetworkImage(
                    imageUrl: _phaseUrl(idx),
                    fit: BoxFit.cover,
                    memCacheWidth: 300,
                    placeholder: (_, __) => Container(color: _bg),
                    errorWidget: (_, __, ___) => Container(color: _bg),
                  ),
                ),
              ),
              // Text content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Text(
                            _chapterRoman(idx),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: _brass,
                              letterSpacing: 2,
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: _brassBright,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                'NOW',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: _bg,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _phaseLabelEs(idx),
                        style: GoogleFonts.cinzel(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isCurrent
                              ? _ivory
                              : _ivory.withValues(alpha: 0.85),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _phaseTimeRange(idx),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _ivoryDim,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom sticky brass CTA ───────────────────────────────────────
  Widget _bottomCta(bool isActive) {
    return Container(
      decoration: BoxDecoration(
        color: _bg.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: _brass.withValues(alpha: 0.4))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isActivating
                ? null
                : isActive
                    ? _deactivate
                    : _activate,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? _bg : _brass,
              foregroundColor: _bg,
              side: BorderSide(
                color: isActive ? _brassBright : _brassDim,
                width: 1.2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              elevation: 0,
            ),
            child: Text(
              isActive
                  ? LocaleHelper.pick(es: 'DESACTIVAR CICLO', en: 'DEACTIVATE')
                  : LocaleHelper.pick(es: 'APLICAR CICLO', en: 'APPLY CYCLE'),
              style: GoogleFonts.cinzel(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isActive ? _brassBright : _bg,
                letterSpacing: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Phase helpers ─────────────────────────────────────────────────
  List<String> _allPhaseUrls() => [
        widget.theme.morningUrl,
        widget.theme.afternoonUrl,
        widget.theme.eveningUrl,
        widget.theme.nightUrl,
      ];
  String _phaseUrl(int idx) => _allPhaseUrls()[idx];

  String _phaseLabelEs(int idx) {
    switch (idx) {
      case 0:
        return 'AURORA';
      case 1:
        return 'MERIDIANO';
      case 2:
        return 'CREPÚSCULO';
      default:
        return 'NOCTURNO';
    }
  }

  String _chapterRoman(int idx) {
    switch (idx) {
      case 0:
        return 'CAPÍTULO I';
      case 1:
        return 'CAPÍTULO II';
      case 2:
        return 'CAPÍTULO III';
      default:
        return 'CAPÍTULO IV';
    }
  }

  String _phaseTimeRange(int idx) {
    switch (idx) {
      case 0:
        return '06:00 — 12:00';
      case 1:
        return '12:00 — 18:00';
      case 2:
        return '18:00 — 21:00';
      default:
        return '21:00 — 06:00';
    }
  }
}

int _currentPhaseIndex(DateTime now) {
  final h = now.hour;
  if (h >= 6 && h < 12) return 0;
  if (h >= 12 && h < 18) return 1;
  if (h >= 18 && h < 21) return 2;
  return 3;
}

double _dayFraction(DateTime now) {
  final secs = now.hour * 3600 + now.minute * 60 + now.second;
  return secs / 86400;
}

// ─────────────────────────────────────────────────────────────────────
//  Compass rose painter — circular brass dial with 4 cardinal markers
//  (N=midnight, E=morning, S=noon, W=evening). A gold pointer rotates
//  to indicate the active phase. The whole dial rotates very slowly
//  (120s) for a sense of celestial motion.
// ─────────────────────────────────────────────────────────────────────
class _CompassRosePainter extends CustomPainter {
  final double rotation;
  final int activeIndex; // 0=morning, 1=noon, 2=evening, 3=night

  _CompassRosePainter({required this.rotation, required this.activeIndex});

  static const _brass = Color(0xFFD4AF37);
  static const _brassBright = Color(0xFFF5D676);
  static const _bg = Color(0xFF050514);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Outer brass ring + soft gold glow
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = _brassBright.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = _bg.withValues(alpha: 0.55)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = _brass
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      c,
      r - 8,
      Paint()
        ..color = _brass.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );

    // Hour ticks — 24 short marks around the inner ring
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotation);
    final tickPaint = Paint()
      ..color = _brass
      ..strokeWidth = 1;
    for (var i = 0; i < 24; i++) {
      final a = (i / 24) * 2 * math.pi;
      final long = i % 6 == 0;
      final inner = long ? r - 18 : r - 12;
      canvas.drawLine(
        Offset(math.cos(a) * inner, math.sin(a) * inner),
        Offset(math.cos(a) * (r - 4), math.sin(a) * (r - 4)),
        tickPaint..color = _brass.withValues(alpha: long ? 0.9 : 0.4),
      );
    }
    canvas.restore();

    // 4 cardinal phase markers (compass points) — small filled circles
    // Position angles: midnight=top(-π/2), morning=right(0), noon=bottom(π/2), evening=left(π)
    // Indices: 0=morning, 1=noon, 2=evening, 3=night
    final phaseAngles = [
      0.0, // morning E
      math.pi / 2, // noon S
      math.pi, // evening W
      -math.pi / 2, // night N
    ];
    for (var i = 0; i < 4; i++) {
      final a = phaseAngles[i];
      final pos =
          Offset(c.dx + math.cos(a) * (r - 12), c.dy + math.sin(a) * (r - 12));
      final active = i == activeIndex;
      canvas.drawCircle(
        pos,
        active ? 6 : 3.5,
        Paint()..color = active ? _brassBright : _brass,
      );
      if (active) {
        canvas.drawCircle(
          pos,
          10,
          Paint()
            ..color = _brassBright.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
    }

    // Pointer from center to active phase
    final pa = phaseAngles[activeIndex];
    final tipPath = Path()
      ..moveTo(c.dx + math.cos(pa) * (r - 18), c.dy + math.sin(pa) * (r - 18))
      ..lineTo(c.dx + math.cos(pa + 0.18) * 8, c.dy + math.sin(pa + 0.18) * 8)
      ..lineTo(c.dx + math.cos(pa - 0.18) * 8, c.dy + math.sin(pa - 0.18) * 8)
      ..close();
    canvas.drawPath(tipPath, Paint()..color = _brassBright);

    // Center hub
    canvas.drawCircle(c, 6, Paint()..color = _bg);
    canvas.drawCircle(
      c,
      6,
      Paint()
        ..color = _brass
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _CompassRosePainter old) =>
      old.rotation != rotation || old.activeIndex != activeIndex;
}

// ─────────────────────────────────────────────────────────────────────
//  Starfield drift — small twinkling dots across the cosmic bg
// ─────────────────────────────────────────────────────────────────────
class _AlmanacStarPainter extends CustomPainter {
  final double progress;
  static final _stars = List.generate(40, (i) {
    final r = math.Random(i * 1013 + 17);
    return _Star(
      x: r.nextDouble(),
      y: r.nextDouble(),
      radius: 0.5 + r.nextDouble() * 1.0,
      hueOffset: r.nextDouble(),
    );
  });

  _AlmanacStarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final dx = -progress * 15 % size.width;
    final dy = progress * 6 % size.height;
    for (final s in _stars) {
      final x = (s.x * size.width + dx) % size.width;
      final y = (s.y * size.height + dy) % size.height;
      final twinkle =
          (math.sin((progress + s.hueOffset) * math.pi * 2) + 1) / 2;
      final alpha = 0.25 + twinkle * 0.45;
      canvas.drawCircle(
        Offset(x, y),
        s.radius,
        Paint()..color = Colors.white.withValues(alpha: alpha * 0.65),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AlmanacStarPainter old) =>
      old.progress != progress;
}

class _Star {
  final double x, y, radius, hueOffset;
  _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.hueOffset,
  });
}
