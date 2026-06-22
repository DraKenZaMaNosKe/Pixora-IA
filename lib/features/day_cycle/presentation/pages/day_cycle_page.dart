import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/design/hud_tokens.dart';
import '../../../../core/services/app_strings_service.dart';
import '../../../../core/services/day_cycle_catalog_service.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../../core/widgets/watch_card_pieces.dart';
import '../../providers/day_cycle_providers.dart';
import '../../data/models/day_cycle_theme.dart';
import 'day_cycle_detail_page.dart';

/// DAY CYCLE tab — Hour Slider / Time Scrubber (concept #05, picked by
/// Eduardo 2026-05-16). Each theme card shows a BIG hero of the current
/// phase (~210 px tall) above a slim horizontal gradient slider that
/// morphs morning → noon → evening → night. A gold scrubber marks the
/// live time on the gradient. Hour ticks below.
class DayCyclePage extends ConsumerWidget {
  const DayCyclePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(dayCycleCatalogProvider);

    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: context.hud.accent, size: 48),
            const SizedBox(height: 12),
            Text('Failed to load themes',
                style: TextStyle(color: context.hud.textDim)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(dayCycleCatalogProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (themes) {
        if (themes.isEmpty) {
          return Center(
            child: Text('No day cycle themes available yet',
                style: TextStyle(color: context.hud.textDim)),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            // 2026-06-21 — Fix: invalidar SOLO el provider de Riverpod no
            // alcanza, porque DayCycleCatalogService tiene su propio
            // cache interno (_themes + _isCacheValid) que se queda con
            // los datos viejos. Forzamos un fetch con forceRefresh: true
            // para bypass del cache del service y luego invalidamos el
            // provider para que el FutureBuilder rebuild con los nuevos.
            await DayCycleCatalogService.instance
                .fetchCatalog(forceRefresh: true);
            ref.invalidate(dayCycleCatalogProvider);
            await AppStringsService.instance.refresh();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              for (final t in themes) ...[
                _HourSliderCard(theme: t),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HourSliderCard extends ConsumerStatefulWidget {
  const _HourSliderCard({required this.theme});
  final DayCycleTheme theme;

  @override
  ConsumerState<_HourSliderCard> createState() => _HourSliderCardState();
}

class _HourSliderCardState extends ConsumerState<_HourSliderCard> {
  static const _cardBg = Color(0xFF1A1816);
  static const _borderDim = Color(0x1AFFFFFF);

  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final isActive = ref.watch(activeDayCycleIdProvider) == t.id;
    final phaseIdx = _currentPhaseIndex(_now);
    final phaseUrl = _phaseUrl(t, phaseIdx);
    final phaseName = _phaseName(phaseIdx);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DayCycleDetailPage(theme: t)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isActive ? HudTokens.gold.withValues(alpha: 0.55) : _borderDim,
            width: isActive ? 1.2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero: current phase image (BIG) ───────────────────────
            SizedBox(
              height: 210,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: phaseUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 800,
                      placeholder: (_, __) => Container(color: _cardBg),
                      errorWidget: (_, __, ___) => Container(color: _cardBg),
                    ),
                  ),
                  // Dark bottom gradient for legibility of overlays
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                          stops: const [0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Active pill top-left when wallpaper is currently running
                  if (isActive)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: HudTokens.gold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: HudTokens.goldBright,
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          LocaleHelper.pick(es: 'ACTIVO', en: 'ACTIVE'),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: HudTokens.goldBright,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                    ),
                  // Activity rings top-right
                  Positioned(
                    top: 8,
                    right: 8,
                    child: ActivityRings(wallpaperId: 'daycycle_${t.id}'),
                  ),
                  // Phase name + time overlay bottom-left
                  Positioned(
                    left: 14,
                    bottom: 10,
                    right: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phaseName,
                          style: GoogleFonts.fraunces(
                            fontSize: 22,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: -0.3,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 10,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatHHmm(_now)} · ${LocaleHelper.pick(es: "EN VIVO", en: "LIVE")}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: HudTokens.goldBright,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Title (above the slider) ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text(
                t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            // ── Hour slider — gradient + scrubber ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: _HourSlider(fraction: _dayFraction(_now)),
            ),
            // ── Hour ticks ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final h in ['06', '12', '18', '24'])
                    Text(
                      h,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.35),
                        letterSpacing: 0.6,
                      ),
                    ),
                ],
              ),
            ),
            // ── Action row ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 10, 12),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz, size: 12, color: Colors.white38),
                  const SizedBox(width: 4),
                  Text(
                    LocaleHelper.pick(
                        es: 'TAP PARA APLICAR', en: 'TAP TO APPLY'),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.55),
                      letterSpacing: 1.8,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          HudTokens.gold,
                          HudTokens.goldBright,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: HudTokens.gold.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      isActive
                          ? LocaleHelper.pick(es: 'ABRIR', en: 'OPEN')
                          : LocaleHelper.pick(es: 'APLICAR', en: 'APPLY'),
                      style: GoogleFonts.bangers(
                        fontSize: 13,
                        color: const Color(0xFF1A0F00),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _phaseUrl(DayCycleTheme t, int idx) {
    switch (idx) {
      case 0:
        return t.morningUrl;
      case 1:
        return t.afternoonUrl;
      case 2:
        return t.eveningUrl;
      default:
        return t.nightUrl;
    }
  }

  String _phaseName(int idx) {
    switch (idx) {
      case 0:
        return LocaleHelper.pick(es: 'Mañana', en: 'Morning');
      case 1:
        return LocaleHelper.pick(es: 'Tarde', en: 'Afternoon');
      case 2:
        return LocaleHelper.pick(es: 'Atardecer', en: 'Evening');
      default:
        return LocaleHelper.pick(es: 'Noche', en: 'Night');
    }
  }
}

/// Slim horizontal slider — gradient that flows morning→noon→evening→night
/// with a vertical gold scrubber marker at the current day fraction.
class _HourSlider extends StatelessWidget {
  const _HourSlider({required this.fraction});
  final double fraction; // 0..1

  // Day phase color palette — each "stop" maps to a representative hue
  static const _morning = Color(0xFFFEC089); // peach
  static const _noon = Color(0xFF7DD3FC); // sky cyan
  static const _evening = Color(0xFFC084FC); // violet
  static const _night = Color(0xFF1E1B4B); // deep indigo

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth;
          final scrubberLeft = (fraction * w).clamp(0.0, w - 2);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // The flowing gradient
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 22,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _night,
                        _morning,
                        _noon,
                        _evening,
                        _night,
                      ],
                      stops: [0.0, 0.25, 0.50, 0.75, 1.0],
                    ),
                  ),
                ),
              ),
              // Subtle dark overlay on inactive halves so the scrubber pops
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 22,
                  color: Colors.black.withValues(alpha: 0.08),
                ),
              ),
              // Scrubber — gold vertical line with shadow + cap on top
              Positioned(
                left: scrubberLeft - 1,
                top: -2,
                bottom: -2,
                width: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: HudTokens.goldBright,
                    boxShadow: [
                      BoxShadow(
                        color: HudTokens.goldBright.withValues(alpha: 0.7),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              // Scrubber cap (diamond) at top
              Positioned(
                left: scrubberLeft - 5,
                top: -4,
                child: Container(
                  width: 10,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: HudTokens.goldBright,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────

double _dayFraction(DateTime now) {
  final secondsOfDay = now.hour * 3600 + now.minute * 60 + now.second;
  return secondsOfDay / 86400;
}

int _currentPhaseIndex(DateTime now) {
  final h = now.hour;
  if (h >= 6 && h < 12) return 0; // morning
  if (h >= 12 && h < 18) return 1; // afternoon
  if (h >= 18 && h < 21) return 2; // evening
  return 3; // night
}

String _formatHHmm(DateTime now) =>
    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
