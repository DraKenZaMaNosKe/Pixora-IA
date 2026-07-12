import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/supabase_config.dart';
import '../../../core/services/wallpaper_service.dart';
import '../../../core/services/wallpaper_stats_service.dart';
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

/// Cosmic palette — used for BOTH iOS and B&G themes, just like the
/// onboarding modal. The section needs a unified dark cosmic identity.
class _ArcanoPalette {
  static const ink = Color(0xFF020617);
  static const inkMid = Color(0xFF060B1A);
  static const inkTop = Color(0xFF0F172A);
  static const cyan = Color(0xFF7DD3FC);
  static const silver = Color(0xFFE2E8F0);
  static const textDim = Color(0x99E2E8F0);
  static const textFaint = Color(0x66E2E8F0);
  static const cyan25 = Color(0x407DD3FC);
  static const cyan10 = Color(0x1A7DD3FC);
  static const cyan05 = Color(0x0D7DD3FC);
}

class _ArcanoPageState extends ConsumerState<ArcanoPage>
    with TickerProviderStateMixin {
  bool _installing = false;
  String? _installingId;

  late final AnimationController _glowCtrl;
  late final AnimationController _irisCtrl;
  late final AnimationController _starCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _irisCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _starCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
    UserProfileService.instance.addListener(_onProfileChange);
    _bootstrap();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _irisCtrl.dispose();
    _starCtrl.dispose();
    UserProfileService.instance.removeListener(_onProfileChange);
    super.dispose();
  }

  void _onProfileChange() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await UserProfileService.instance.init();
    if (!mounted) return;
    // 2026-07-04 — Eduardo: el onboarding NO debe salir al entrar a
    // Arcano. Solo se abre cuando el usuario toca el botón "+" del
    // header (llama a _openOnboarding). Si algún día se quiere
    // reactivar el auto-prompt, agregar aquí _maybeShowOnboarding().
  }

  @override
  Widget build(BuildContext context) {
    final phase = _MoonPhase.today();
    final dateLabel = _formatDate(DateTime.now());
    final profile = UserProfileService.instance;
    final userName = profile.hasProfile ? profile.name : 'Viajero';
    final userZodiac = profile.zodiacSign;
    final userFreq = profile.personalFrequency ?? 528;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _ArcanoPalette.inkTop,
            _ArcanoPalette.inkMid,
            _ArcanoPalette.ink,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Cyan halo top — observatory dome glow
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.85),
                    radius: 1.1,
                    colors: [
                      _ArcanoPalette.cyan.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Parallax starfield
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _starCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _StarfieldPainter(progress: _starCtrl.value),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topRow(dateLabel, profile.hasProfile),
                  const SizedBox(height: 14),
                  _moonHero(phase),
                  const SizedBox(height: 14),
                  _statRow(phase, userZodiac),
                  const SizedBox(height: 14),
                  _readingCard(phase, userName, userFreq),
                  const SizedBox(height: 26),
                  _calendarsSection(phase),
                  const SizedBox(height: 14),
                  _footerNote(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header row: date + edit-profile icon ─────────────────────────────
  Widget _topRow(String dateLabel, bool hasProfile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          dateLabel,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            letterSpacing: 2.4,
            color: _ArcanoPalette.cyan.withValues(alpha: 0.75),
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: _ArcanoPalette.cyan.withValues(alpha: 0.4),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        InkWell(
          // The "+" icon (no profile yet) opens the same onboarding sheet
          // as the "tune" icon (has profile). Both must be tappable —
          // previously `null` when no profile, which made the entry-point
          // dead for first-time users. 2026-05-16 fix.
          onTap: _openOnboarding,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _ArcanoPalette.cyan10,
              border: Border.all(color: _ArcanoPalette.cyan25),
            ),
            child: Icon(
              hasProfile ? Icons.tune_rounded : Icons.add,
              size: 16,
              color: _ArcanoPalette.cyan,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openOnboarding() async {
    await ArcanoOnboardingSheet.show(context);
  }

  // ── Hero moon card — Deep Cosmos Observatory orb with pulsing halo ──
  Widget _moonHero(_MoonPhase phase) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x990F172A),
            Color(0xD9020617),
          ],
        ),
        border: Border.all(color: _ArcanoPalette.cyan.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: _ArcanoPalette.cyan.withValues(alpha: 0.12),
            blurRadius: 60,
            spreadRadius: -10,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _glowCtrl,
            builder: (_, __) => _DeepCosmosMoonOrb(
              illuminationFraction: phase.illumination,
              isWaxing: phase.isWaxing,
              glowPulse: _glowCtrl.value,
            ),
          ),
          const SizedBox(height: 22),
          AnimatedBuilder(
            animation: _irisCtrl,
            builder: (_, __) {
              final shift = _irisCtrl.value;
              return ShaderMask(
                shaderCallback: (rect) {
                  return LinearGradient(
                    begin: Alignment(-1 + 2 * shift, 0),
                    end: Alignment(1 + 2 * shift, 0),
                    colors: const [
                      _ArcanoPalette.silver,
                      _ArcanoPalette.cyan,
                      _ArcanoPalette.silver,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.srcIn,
                child: Text(
                  phase.spanishName,
                  style: GoogleFonts.fraunces(
                    fontSize: 24,
                    fontStyle: FontStyle.italic,
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.3,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            '${(phase.illumination * 100).toStringAsFixed(0)}% · ILUMINADA',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              letterSpacing: 2.4,
              color: _ArcanoPalette.cyan.withValues(alpha: 0.65),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── 2 stat pills: next phase + zodiac sign ───────────────────────────
  Widget _statRow(_MoonPhase phase, ZodiacSign? zodiac) {
    final zodiacLabel =
        zodiac == null ? '— · ?' : '${zodiac.label} ${zodiac.glyph}';
    return Row(
      children: [
        Expanded(
            child: _statPill('Próximo',
                '${phase.nextMajorPhaseName} · ${phase.daysToNextMajor}d')),
        const SizedBox(width: 8),
        Expanded(child: _statPill('Tu signo', zodiacLabel)),
      ],
    );
  }

  Widget _statPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: _ArcanoPalette.cyan05,
        border: Border.all(color: _ArcanoPalette.cyan.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              letterSpacing: 2,
              color: _ArcanoPalette.cyan.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.fraunces(
              fontSize: 16,
              color: _ArcanoPalette.silver,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Personalised reading card (Cormorant italic body) ────────────────
  Widget _readingCard(_MoonPhase phase, String userName, int freq) {
    final reading = _composeReading(phase, freq);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0x8C0F172A),
        border: Border.all(color: _ArcanoPalette.cyan.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: _ArcanoPalette.cyan.withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LECTURA · $userName'.toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              letterSpacing: 2.4,
              color: _ArcanoPalette.cyan.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: GoogleFonts.cormorantGaramond(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: _ArcanoPalette.silver.withValues(alpha: 0.85),
                height: 1.45,
              ),
              children: reading.spans
                  .map((s) => TextSpan(
                        text: s.text,
                        style: s.emphasis
                            ? GoogleFonts.cormorantGaramond(
                                fontStyle: FontStyle.italic,
                                color: _ArcanoPalette.cyan,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                height: 1.45,
                                shadows: [
                                  Shadow(
                                    color: _ArcanoPalette.cyan
                                        .withValues(alpha: 0.4),
                                    blurRadius: 8,
                                  ),
                                ],
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
  /// Carousel of all ARCANO wallpapers — the lunar calendar collection.
  /// Each card represents a different cultural calendar (Iah Egipcia today;
  /// Maya Tzolkin, Aztec Sun, Chinese Zodiac in the future). Tap any card
  /// to install it as your wallpaper, with the right phase + sign variant
  /// auto-picked based on today's sky and the user's Hive profile.
  ///
  /// Adding a new calendar requires ZERO app rebuild — just upload its
  /// 96 phase×sign variants to Supabase and INSERT a row in the wallpapers
  /// table with category='ARCANO'. The carousel picks it up automatically.
  Widget _calendarsSection(_MoonPhase phase) {
    final calendarsAsync = ref.watch(arcanoCatalogProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'EXPLORA',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                letterSpacing: 2.4,
                color: _ArcanoPalette.cyan.withValues(alpha: 0.55),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _ArcanoPalette.cyan.withValues(alpha: 0.25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Calendarios Lunares',
          style: GoogleFonts.fraunces(
            fontSize: 22,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            color: _ArcanoPalette.silver,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tu mes completo — fases, eclipses y tu carta astral diaria.',
          style: GoogleFonts.cormorantGaramond(
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: _ArcanoPalette.silver.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 244,
          child: calendarsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: _ArcanoPalette.cyan),
            ),
            error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(
                      color: _ArcanoPalette.textDim, fontSize: 12)),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const Center(
                  child: Text('No hay calendarios disponibles',
                      style: TextStyle(
                          color: _ArcanoPalette.textDim, fontSize: 13)),
                );
              }
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                itemBuilder: (ctx, i) => _calendarCard(list[i], phase),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _calendarCard(Wallpaper w, _MoonPhase phase) {
    final canInstall = Platform.isAndroid && w.id.isNotEmpty;
    final isInstallingThis = _installing && _installingId == w.id;

    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap:
              canInstall && !_installing ? () => _onInstallTap(w, phase) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 9 / 12,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _ArcanoPalette.inkTop,
                          border: Border.all(
                            color: _ArcanoPalette.cyan.withValues(alpha: 0.2),
                            width: 0.5,
                          ),
                        ),
                        child: w.previewUrl.isNotEmpty
                            ? Image.network(
                                w.previewUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.image_not_supported,
                                      color: _ArcanoPalette.textDim),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  // Cyan glow ring around card
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  _ArcanoPalette.cyan.withValues(alpha: 0.15),
                              blurRadius: 18,
                              spreadRadius: -4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Phase chip top-right — cyan tinted
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xCC020617),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _ArcanoPalette.cyan25),
                      ),
                      child: Text(
                        phase.spanishName,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: _ArcanoPalette.cyan,
                        ),
                      ),
                    ),
                  ),
                  if (isInstallingThis)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: _ArcanoPalette.cyan,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                w.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  color: _ArcanoPalette.silver,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'TAP PARA APLICAR',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 8,
                  letterSpacing: 1.4,
                  color: _ArcanoPalette.cyan.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerNote() {
    return Center(
      child: Text(
        '🔒 PERFIL SOLO EN ESTE DISPOSITIVO',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          letterSpacing: 2.4,
          color: _ArcanoPalette.textFaint,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Install flow: pick phase + sign variant → download → setLiveWallpaper
  Future<void> _onInstallTap(Wallpaper iah, _MoonPhase phase) async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _installingId = iah.id;
    });
    try {
      // Compose the variant filename from BOTH today's moon phase AND the
      // user's zodiac sign (so their sign is illuminated in the wheel).
      // Falls back to a generic suffix when no profile exists yet.
      final profile = UserProfileService.instance;
      final signIdx = profile.zodiacSign?.index;
      final suffix = signIdx == null
          ? '' // generic — no personalisation halo
          : '_${signIdx.toString().padLeft(2, '0')}';
      final phaseFileName =
          'pixora_iah_egyptian_giza_lunar_${phase.fileKey}$suffix.webp';
      final localPath = await _downloadPhase(phaseFileName);
      final ok = await WallpaperService.instance.setLiveWallpaper(
        localPath,
        iah.glowColor.isEmpty ? '#D4AF37' : iah.glowColor,
        contentId: iah.id,
      );
      // Track the install in analytics — this was previously missing, so
      // ARCANO installs never showed up in the admin dashboard. Fire-and-forget;
      // do not block the UI on the network round-trip.
      if (ok) {
        unawaited(WallpaperStatsService.instance.trackInstall(iah.id));
      }
      // After successful install, register the daily lunar phase updater so
      // the moon "follows" the real lunar cycle without the user having to
      // re-install. The native LunarPhaseWorker pre-caches the 8 phase
      // variants for this sign so future updates work offline.
      if (ok && signIdx != null) {
        try {
          await const MethodChannel('com.orbix.pixora/wallpaper')
              .invokeMethod<bool>('startLunarUpdater', {
            'signIndex': signIdx,
            'glowColor': iah.glowColor.isEmpty ? '#D4AF37' : iah.glowColor,
          });
        } catch (_) {
          // Non-fatal — wallpaper still applied, just won't auto-advance
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Calendario lunar aplicado · ${phase.spanishName}. '
                  'La luna se actualizará sola cada día. '
                  'Escoge "Live wallpaper" para scroll panorámico.'
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
      if (mounted) {
        setState(() {
          _installing = false;
          _installingId = null;
        });
      }
    }
  }

  /// Downloads a specific phase variant from the wallpaper-images bucket
  /// (keyed by filename). Each phase has its own file so the local cache
  /// can hold all 8 simultaneously and avoid redundant downloads after the
  /// first install of each phase.
  Future<String> _downloadPhase(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final wallpapersDir = Directory(p.join(dir.path, 'wallpapers'));
    if (!wallpapersDir.existsSync()) wallpapersDir.createSync(recursive: true);
    final localFile = File(p.join(wallpapersDir.path, fileName));
    if (localFile.existsSync()) {
      return localFile.path;
    }
    final url = SupabaseConfig.imageUrl(fileName);
    // Timeout 30s — los wallpapers pueden ser pesados (panorámicas ~500 KB)
    // y red lenta. Sin timeout, http.get cuelga indefinidamente.
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Download failed: HTTP ${res.statusCode}');
    }
    await localFile.writeAsBytes(res.bodyBytes);
    return localFile.path;
  }

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
//  Deep Cosmos Moon Orb — observatory-style 3D moon with cyan halo
// ═════════════════════════════════════════════════════════════════════
class _DeepCosmosMoonOrb extends StatelessWidget {
  final double illuminationFraction;
  final bool isWaxing;
  final double glowPulse; // 0..1 from AnimationController

  const _DeepCosmosMoonOrb({
    required this.illuminationFraction,
    required this.isWaxing,
    required this.glowPulse,
  });

  @override
  Widget build(BuildContext context) {
    final pulse = (math.sin(glowPulse * math.pi * 2) + 1) / 2;
    final ringAlpha = 0.5 + pulse * 0.2;
    final outerAlpha = 0.25 + pulse * 0.1;
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color:
                      _ArcanoPalette.cyan.withValues(alpha: outerAlpha * 0.5),
                  blurRadius: 60,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: _ArcanoPalette.cyan.withValues(alpha: ringAlpha * 0.6),
                  blurRadius: 28,
                  spreadRadius: -2,
                ),
              ],
            ),
          ),
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.36, -0.4),
                radius: 0.95,
                colors: [
                  Color(0xFFF8FAFC),
                  Color(0xFFCBD5E1),
                  Color(0xFF64748B),
                  Color(0xFF1E293B),
                ],
                stops: [0.0, 0.35, 0.75, 1.0],
              ),
              border: Border.all(
                color: _ArcanoPalette.cyan.withValues(alpha: ringAlpha),
                width: 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xD9020617),
                  blurRadius: 18,
                  spreadRadius: -8,
                  offset: Offset(8, 8),
                ),
              ],
            ),
            child: CustomPaint(
              painter: _MoonCratersPainter(
                illumination: illuminationFraction,
                isWaxing: isWaxing,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoonCratersPainter extends CustomPainter {
  final double illumination;
  final bool isWaxing;
  _MoonCratersPainter({required this.illumination, required this.isWaxing});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    // Crater dimples — subtle inner shadows to give 3D feel
    final craterPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.35);
    canvas.drawCircle(
        Offset(c.dx + r * 0.18, c.dy - r * 0.22), r * 0.10, craterPaint);
    canvas.drawCircle(
        Offset(c.dx - r * 0.28, c.dy + r * 0.05), r * 0.07, craterPaint);
    canvas.drawCircle(
        Offset(c.dx + r * 0.05, c.dy + r * 0.30), r * 0.09, craterPaint);
    canvas.drawCircle(
        Offset(c.dx - r * 0.05, c.dy - r * 0.42), r * 0.05, craterPaint);
    canvas.drawCircle(
        Offset(c.dx + r * 0.40, c.dy + r * 0.18), r * 0.06, craterPaint);

    // Terminator shadow — partial cover for phases other than full
    if (illumination < 0.95) {
      final shadowSide = isWaxing ? -1.0 : 1.0;
      final shadowAlpha = (1 - illumination).clamp(0.35, 0.85);
      final shadow = Paint()
        ..color = const Color(0xFF020617).withValues(alpha: shadowAlpha);
      final path = Path()..addOval(Rect.fromCircle(center: c, radius: r));
      canvas.save();
      canvas.clipPath(path);
      final coverWidth = r * (1.6 - illumination * 1.3).clamp(0.3, 1.6);
      canvas.drawRect(
        Rect.fromLTRB(
          shadowSide < 0 ? c.dx - r : c.dx + r - coverWidth,
          c.dy - r,
          shadowSide < 0 ? c.dx - r + coverWidth : c.dx + r,
          c.dy + r,
        ),
        shadow,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MoonCratersPainter old) =>
      old.illumination != illumination || old.isWaxing != isWaxing;
}

// ═════════════════════════════════════════════════════════════════════
//  Starfield — animated cosmic dust across the whole page
// ═════════════════════════════════════════════════════════════════════
class _StarfieldPainter extends CustomPainter {
  final double progress; // 0..1
  _StarfieldPainter({required this.progress});

  // 60 stars at fixed pseudo-random positions — deterministic per session
  static final _stars = List.generate(60, (i) {
    final r = math.Random(i * 7919 + 13);
    return _Star(
      x: r.nextDouble(),
      y: r.nextDouble(),
      radius: 0.6 + r.nextDouble() * 1.4,
      hue: r.nextDouble(),
      twinkleOffset: r.nextDouble(),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Slow parallax drift — wraps around
    final driftX = -progress * 24 % size.width;
    final driftY = progress * 12 % size.height;
    for (final s in _stars) {
      final x = (s.x * size.width + driftX) % size.width;
      final y = (s.y * size.height + driftY) % size.height;
      // Twinkle: per-star phase, oscillates between 0.35 and 1.0 alpha
      final twinkle = (math.sin(
                    (progress + s.twinkleOffset) * math.pi * 2,
                  ) +
                  1) /
              2 *
              0.55 +
          0.35;
      final color = s.hue < 0.6
          ? Colors.white.withValues(alpha: twinkle * 0.8)
          : (s.hue < 0.85
              ? _ArcanoPalette.cyan.withValues(alpha: twinkle * 0.75)
              : const Color(0xFFA78BFA).withValues(alpha: twinkle * 0.7));
      canvas.drawCircle(Offset(x, y), s.radius, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) =>
      old.progress != progress;
}

class _Star {
  final double x, y, radius, hue, twinkleOffset;
  _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.hue,
    required this.twinkleOffset,
  });
}

// ═════════════════════════════════════════════════════════════════════
//  Moon phase calculation — simple synodic month approximation
// ═════════════════════════════════════════════════════════════════════
class _MoonPhase {
  final double illumination; // 0..1
  final bool isWaxing; // true between new and full
  final String spanishName; // e.g. "Cuarto Creciente"
  final String fileKey; // e.g. "first_quarter" — matches uploaded variant
  final String nextMajorPhaseName;
  final int daysToNextMajor;

  _MoonPhase({
    required this.illumination,
    required this.isWaxing,
    required this.spanishName,
    required this.fileKey,
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
      fileKey: _fileKey(phase),
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

  /// Maps the same phase boundaries used by `_phaseName` to the uploaded
  /// Supabase filename suffix (matches build_iah_lunar_phases.py PHASES).
  static String _fileKey(double p) {
    if (p < 0.03 || p > 0.97) return 'new';
    if (p < 0.22) return 'waxing_crescent';
    if (p < 0.28) return 'first_quarter';
    if (p < 0.47) return 'waxing_gibbous';
    if (p < 0.53) return 'full';
    if (p < 0.72) return 'waning_gibbous';
    if (p < 0.78) return 'third_quarter';
    return 'waning_crescent';
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
