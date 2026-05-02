import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../../core/design/hud_tokens.dart';
import '../../../core/services/wallpaper_service.dart';
import '../../wallpapers/data/models/wallpaper.dart';
import '../../wallpapers/providers/wallpaper_providers.dart';
import '../data/user_profile_service.dart';
import 'widgets/onboarding_sheet.dart';

/// ARCANO · Observatorio Astral
///
/// New section dedicated to lunar wallpapers, tarot, and personalised
/// energy readings. Reads name + birth date from `UserProfileService`
/// (Hive, local-only). On first entry, shows the onboarding modal to
/// collect the profile; once saved, the page renders fully personal
/// readings (zodiac, life path, Solfeggio frequency).
class ArcanoPage extends ConsumerStatefulWidget {
  const ArcanoPage({super.key});

  @override
  ConsumerState<ArcanoPage> createState() => _ArcanoPageState();
}

class _ArcanoPageState extends ConsumerState<ArcanoPage> {
  bool _installing = false;
  bool _profileReady = false;
  bool _onboardingShown = false;

  @override
  void initState() {
    super.initState();
    UserProfileService.instance.addListener(_onProfileChange);
    _bootstrap();
  }

  @override
  void dispose() {
    UserProfileService.instance.removeListener(_onProfileChange);
    super.dispose();
  }

  void _onProfileChange() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await UserProfileService.instance.init();
    if (!mounted) return;
    setState(() => _profileReady = true);
    _maybeShowOnboarding();
  }

  void _maybeShowOnboarding() {
    if (_onboardingShown) return;
    if (UserProfileService.instance.hasProfile) return;
    _onboardingShown = true;
    // Defer until after first frame so the page paints behind the modal.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ArcanoOnboardingSheet.show(context);
      // hasProfile listener will refresh the page if they saved.
    });
  }

  @override
  Widget build(BuildContext context) {
    final hud = context.hud;
    final phase = _MoonPhase.today();
    final dateLabel = _formatDate(DateTime.now());
    final profile = UserProfileService.instance;
    // Generic fallbacks when the user dismissed onboarding without saving.
    // Page still renders something useful (no personalisation, no name).
    final userName = profile.hasProfile ? profile.name : 'Viajero';
    final userZodiac = profile.zodiacSign; // null = not personalised
    final userFreq = profile.personalFrequency ?? 528;

    return Container(
      decoration: BoxDecoration(
        gradient: hud.isDark
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF050308),
                  Color(0xFF0A0512),
                  Color(0xFF050308)
                ],
              )
            : null,
        color: hud.isDark ? null : hud.bg,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topRow(hud, dateLabel, profile.hasProfile),
              const SizedBox(height: 14),
              _moonHero(hud, phase),
              const SizedBox(height: 14),
              _statRow(hud, phase, userZodiac),
              const SizedBox(height: 14),
              _readingCard(hud, phase, userName, userFreq),
              const SizedBox(height: 18),
              _installCta(hud),
              const SizedBox(height: 14),
              _footerNote(hud),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header row: date + edit-profile icon ─────────────────────────────
  Widget _topRow(HudTheme hud, String dateLabel, bool hasProfile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          dateLabel,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            letterSpacing: 2.4,
            color: hud.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        InkWell(
          onTap: hasProfile ? _openOnboarding : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: hud.accent.withValues(alpha: 0.4)),
            ),
            child: Icon(
              hasProfile ? Icons.tune_rounded : Icons.add,
              size: 16,
              color: hud.accent,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openOnboarding() async {
    await ArcanoOnboardingSheet.show(context);
  }

  // ── Hero moon card (real-ish Meeus-approximated phase) ───────────────
  Widget _moonHero(HudTheme hud, _MoonPhase phase) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: hud.isDark
            ? const RadialGradient(
                center: Alignment.topCenter,
                radius: 1.6,
                colors: [Color(0xFF1A0F3A), Color(0xFF0A0512)],
              )
            : null,
        color: hud.isDark ? null : hud.surface,
        border: Border.all(
          color: hud.accent.withValues(alpha: hud.isDark ? 0.18 : 0.0),
        ),
        boxShadow: hud.isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 4))
              ],
      ),
      child: Column(
        children: [
          _MoonGraphic(
              illuminationFraction: phase.illumination,
              isWaxing: phase.isWaxing),
          const SizedBox(height: 14),
          Text(
            phase.spanishName,
            style: GoogleFonts.fraunces(
              fontSize: 22,
              fontStyle: FontStyle.italic,
              color: hud.text,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(phase.illumination * 100).toStringAsFixed(0)}% iluminada',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              letterSpacing: 2,
              color: hud.textDim,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── 2 stat pills: next phase + zodiac sign ───────────────────────────
  Widget _statRow(HudTheme hud, _MoonPhase phase, ZodiacSign? zodiac) {
    final zodiacLabel =
        zodiac == null ? '— · ?' : '${zodiac.label} ${zodiac.glyph}';
    return Row(
      children: [
        Expanded(
            child: _statPill(hud, 'Próximo',
                '${phase.nextMajorPhaseName} · ${phase.daysToNextMajor}d')),
        const SizedBox(width: 8),
        Expanded(child: _statPill(hud, 'Tu signo', zodiacLabel)),
      ],
    );
  }

  Widget _statPill(HudTheme hud, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: hud.isDark ? hud.text.withValues(alpha: 0.04) : hud.surface,
        border: Border.all(
          color: hud.accent.withValues(alpha: hud.isDark ? 0.15 : 0.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              letterSpacing: 2,
              color: hud.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.fraunces(
              fontSize: 16,
              color: hud.text,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Personalised reading card (Cormorant italic body) ────────────────
  Widget _readingCard(
      HudTheme hud, _MoonPhase phase, String userName, int freq) {
    final reading = _composeReading(phase, freq);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: hud.isDark
            ? hud.accent.withValues(alpha: 0.06)
            : Color.lerp(hud.bg, hud.accent, 0.05),
        border: Border.all(
          color: hud.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LECTURA · $userName'.toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              letterSpacing: 2.4,
              color: hud.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: GoogleFonts.cormorantGaramond(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: hud.text,
                height: 1.45,
              ),
              children: reading.spans
                  .map((s) => TextSpan(
                        text: s.text,
                        style: s.emphasis
                            ? GoogleFonts.cormorantGaramond(
                                fontStyle: FontStyle.italic,
                                color: hud.accent,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                height: 1.45,
                              )
                            : null,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Install CTA — downloads + applies the Iah panoramic ──────────────
  Widget _installCta(HudTheme hud) {
    final iahAsync = ref.watch(arcanoCatalogProvider);
    final iah = iahAsync.maybeWhen(
      data: (list) => list.firstWhere(
        (w) => w.id == 'iah_egyptian_giza',
        orElse: () => list.isNotEmpty ? list.first : _emptyWallpaper(),
      ),
      orElse: () => null,
    );

    final canInstall = iah != null && iah.id.isNotEmpty && Platform.isAndroid;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canInstall && !_installing ? () => _onInstallTap(iah) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [hud.accent, Color.lerp(hud.accent, Colors.black, 0.15)!],
            ),
            boxShadow: [
              BoxShadow(
                color: hud.accent.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_installing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              else
                const Icon(Icons.wallpaper_rounded,
                    color: Colors.black, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _installing ? 'APLICANDO...' : 'APLICAR WALLPAPER IAH',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerNote(HudTheme hud) {
    return Center(
      child: Text(
        '🔒 PERFIL SOLO EN ESTE DISPOSITIVO',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          letterSpacing: 2.4,
          color: hud.textDim,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Install flow: download webp → setLiveWallpaper ───────────────────
  Future<void> _onInstallTap(Wallpaper iah) async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      final localPath = await _downloadIfNeeded(iah);
      final ok = await WallpaperService.instance.setLiveWallpaper(
        localPath,
        iah.glowColor.isEmpty ? '#D4AF37' : iah.glowColor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Confirma "Live wallpaper" en el selector para scroll panorámico'
              : 'No pude aplicar el wallpaper'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<String> _downloadIfNeeded(Wallpaper iah) async {
    final dir = await getApplicationDocumentsDirectory();
    final wallpapersDir = Directory(p.join(dir.path, 'wallpapers'));
    if (!wallpapersDir.existsSync()) wallpapersDir.createSync(recursive: true);
    // imageFile is just the filename in the wallpaper-images bucket.
    final fileName = iah.imageFile;
    final localFile = File(p.join(wallpapersDir.path, fileName));
    if (localFile.existsSync()) {
      // Phase 2 (task #109): HEAD/ETag check before re-using cached file.
      // For now Iah is stable so the cache works; user can also manually
      // clear cache via system Settings to force re-download if needed.
      return localFile.path;
    }
    final res = await http.get(Uri.parse(iah.fullImageUrl));
    if (res.statusCode != 200) {
      throw Exception('Download failed: HTTP ${res.statusCode}');
    }
    await localFile.writeAsBytes(res.bodyBytes);
    return localFile.path;
  }

  Wallpaper _emptyWallpaper() => const Wallpaper(
        id: '',
        name: '',
        description: '',
        category: 'ARCANO',
        imageFile: '',
        previewFile: '',
        imageSize: 0,
        previewSize: 0,
        glowColor: '#D4AF37',
      );

  // ── Reading composition (future: pull from Supabase per zodiac+phase) ─
  _Reading _composeReading(_MoonPhase phase, int freq) {
    final greet = phase.illumination > 0.5
        ? 'crece sobre tu casa'
        : 'reposa sobre tu casa';
    return _Reading([
      _ReadingSpan('Hoy '),
      _ReadingSpan('Iah', emphasis: true),
      _ReadingSpan(' $greet. Las decisiones lentas pesarán mañana. '
          'Vibra a '),
      _ReadingSpan('$freq Hz', emphasis: true),
      _ReadingSpan(', ofrece algo dorado al amanecer.'),
    ]);
  }

  String _formatDate(DateTime d) {
    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    const days = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
    final dayName = days[d.weekday % 7];
    return '$dayName · ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ═════════════════════════════════════════════════════════════════════
//  Moon graphic — pure CustomPainter, no asset
// ═════════════════════════════════════════════════════════════════════
class _MoonGraphic extends StatelessWidget {
  final double illuminationFraction; // 0..1
  final bool isWaxing;
  const _MoonGraphic({
    required this.illuminationFraction,
    required this.isWaxing,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 86,
      child: CustomPaint(
        painter: _MoonPainter(
          illumination: illuminationFraction,
          isWaxing: isWaxing,
        ),
      ),
    );
  }
}

class _MoonPainter extends CustomPainter {
  final double illumination;
  final bool isWaxing;
  _MoonPainter({required this.illumination, required this.isWaxing});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    // Lit moon disc (warm gold)
    final lit = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0xFFF5E9C2), Color(0xFFD4AF37), Color(0xFF6E5418)],
        stops: const [0.0, 0.55, 1.0],
        center: const Alignment(-0.3, -0.3),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, lit);
    // Glow
    final glow = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(c, r * 1.05, glow);
    // Shadow (the un-illuminated portion)
    final shadow = Paint()..color = const Color(0xCC000000);
    final t = (1 - illumination); // 0=full, 1=new
    if (illumination < 0.99) {
      // Render the shadow as a partial cover. Simple model: for waxing phases
      // shadow is on the LEFT, for waning on the RIGHT.
      final isNewish = illumination < 0.05;
      if (isNewish) {
        canvas.drawCircle(c, r, Paint()..color = const Color(0xFF12090B));
      } else {
        // Build a clipping ellipse intersected with the disc.
        final shadowSide = isWaxing ? -1.0 : 1.0;
        final terminator =
            c.dx + shadowSide * (r * 2 * (1 - 2 * illumination)) / 2;
        final path = Path()..addOval(Rect.fromCircle(center: c, radius: r));
        canvas.save();
        canvas.clipPath(path);
        if (illumination < 0.5) {
          // Less than half: shadow is the bigger piece — draw a half-disc plus an inner ellipse.
          canvas.drawRect(
            Rect.fromLTRB(
              shadowSide < 0 ? c.dx - r : c.dx,
              c.dy - r,
              shadowSide < 0 ? c.dx : c.dx + r,
              c.dy + r,
            ),
            shadow,
          );
          final inner = Rect.fromCenter(
            center: c,
            width: 2 * (r - (terminator - c.dx).abs() * shadowSide),
            height: 2 * r,
          );
          canvas.drawOval(inner, Paint()..color = const Color(0xFF12090B));
          // Just draw a clean shadow by terminator instead — simpler:
        } else {
          canvas.drawRect(
            Rect.fromLTRB(
              shadowSide < 0 ? c.dx - r : c.dx,
              c.dy - r,
              shadowSide < 0 ? c.dx : c.dx + r,
              c.dy + r,
            ),
            shadow.copyWith()..color = const Color(0x66000000),
          );
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MoonPainter old) =>
      old.illumination != illumination || old.isWaxing != isWaxing;
}

extension _PaintCopy on Paint {
  Paint copyWith() => Paint()
    ..color = color
    ..style = style
    ..strokeWidth = strokeWidth;
}

// ═════════════════════════════════════════════════════════════════════
//  Moon phase calculation — simple synodic month approximation
// ═════════════════════════════════════════════════════════════════════
class _MoonPhase {
  final double illumination; // 0..1
  final bool isWaxing; // true between new and full
  final String spanishName; // e.g. "Cuarto Creciente"
  final String nextMajorPhaseName;
  final int daysToNextMajor;

  _MoonPhase({
    required this.illumination,
    required this.isWaxing,
    required this.spanishName,
    required this.nextMajorPhaseName,
    required this.daysToNextMajor,
  });

  // Reference new moon: 2000-01-06 18:14 UTC
  static final _refNewMoon = DateTime.utc(2000, 1, 6, 18, 14);
  // Mean synodic month
  static const _synodic = 29.530588853;

  static _MoonPhase today() {
    final now = DateTime.now().toUtc();
    final diffDays =
        now.difference(_refNewMoon).inSeconds / Duration.secondsPerDay;
    final age = (diffDays % _synodic + _synodic) % _synodic; // 0..29.53
    final phase = age / _synodic; // 0..1
    final illum = (1 - math.cos(2 * math.pi * phase)) / 2;
    final waxing = phase < 0.5;
    return _MoonPhase(
      illumination: illum,
      isWaxing: waxing,
      spanishName: _phaseName(phase),
      nextMajorPhaseName: _nextMajor(phase),
      daysToNextMajor: _daysToNextMajor(phase),
    );
  }

  static String _phaseName(double p) {
    if (p < 0.03 || p > 0.97) return 'Luna Nueva';
    if (p < 0.22) return 'Creciente';
    if (p < 0.28) return 'Cuarto Creciente';
    if (p < 0.47) return 'Gibosa Creciente';
    if (p < 0.53) return 'Luna Llena';
    if (p < 0.72) return 'Gibosa Menguante';
    if (p < 0.78) return 'Cuarto Menguante';
    return 'Menguante';
  }

  static String _nextMajor(double p) {
    if (p < 0.25) return 'C. Creciente';
    if (p < 0.5) return 'Llena';
    if (p < 0.75) return 'C. Menguante';
    return 'Nueva';
  }

  static int _daysToNextMajor(double p) {
    final nextAt = ((p * 4).ceil() / 4).clamp(0.0, 1.0);
    var fraction = nextAt - p;
    if (fraction <= 0) fraction = 0.25;
    return (fraction * _synodic).round().clamp(1, 30);
  }
}

// ═════════════════════════════════════════════════════════════════════
//  Reading composition helpers
// ═════════════════════════════════════════════════════════════════════
class _Reading {
  final List<_ReadingSpan> spans;
  _Reading(this.spans);
}

class _ReadingSpan {
  final String text;
  final bool emphasis;
  _ReadingSpan(this.text, {this.emphasis = false});
}
