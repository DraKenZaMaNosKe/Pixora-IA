import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/design/hud_tokens.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
import '../../providers/day_cycle_providers.dart';
import '../../data/models/day_cycle_theme.dart';
import 'day_cycle_detail_page.dart';

/// DAY CYCLE tab — Day Strip Timeline (concept #03, picked by Eduardo
/// 2026-05-15). Tira horizontal con 4 segmentos (morning/noon/evening/night)
/// y marker dorado que se desliza con el reloj real. Cada pack expone su
/// propia mini-strip de las 4 fases.
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
        final featured = themes.first;
        final rest = themes.skip(1).toList();
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(dayCycleCatalogProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _DayCycleFeatured(theme: featured),
              const SizedBox(height: 24),
              if (rest.isNotEmpty) ...[
                _SectionHeading(
                  text: LocaleHelper.pick(
                    es: 'OTROS CICLOS',
                    en: 'OTHER CYCLES',
                  ),
                ),
                const SizedBox(height: 10),
                for (final t in rest) ...[
                  _DayCycleStripCard(theme: t),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Featured card — full strip of 4 segments + live time marker + axis labels.
class _DayCycleFeatured extends ConsumerStatefulWidget {
  const _DayCycleFeatured({required this.theme});
  final DayCycleTheme theme;

  @override
  ConsumerState<_DayCycleFeatured> createState() => _DayCycleFeaturedState();
}

class _DayCycleFeaturedState extends ConsumerState<_DayCycleFeatured> {
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
    final h = context.hud;
    final t = widget.theme;
    final activeId = ref.watch(activeDayCycleIdProvider);
    final isActive = activeId == t.id;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DayCycleDetailPage(theme: t)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: h.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: HudTokens.gold.withValues(alpha: isActive ? 0.45 : 0.18),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: HudTokens.gold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: HudTokens.gold.withValues(alpha: 0.4),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      isActive
                          ? LocaleHelper.pick(
                              es: 'DAY CYCLE · ACTIVO',
                              en: 'DAY CYCLE · ACTIVE',
                            )
                          : LocaleHelper.pick(
                              es: 'DAY CYCLE · DESTACADO',
                              en: 'DAY CYCLE · FEATURED',
                            ),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: HudTokens.goldBright,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Stack(
                    children: [
                      WallpaperStatsBar(
                        wallpaperId: 'daycycle_${t.id}',
                        glowColor: HudTokens.gold,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                t.name,
                style: GoogleFonts.fraunces(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  color: Colors.white,
                  height: 1.15,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Strip with 4 image segments + live marker overlaid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _StripWithMarker(theme: t, now: _now, height: 96),
            ),
            // Axis labels
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: _AxisLabels(),
            ),
            // Live time + countdown to next phase
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatHHmm(_now),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: HudTokens.goldBright,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      _phaseAndCountdown(_now),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.55),
                        letterSpacing: 1.0,
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
}

/// Mini card for the rest of the catalog. Name on left, 4-segment strip on
/// right with the live marker.
class _DayCycleStripCard extends ConsumerStatefulWidget {
  const _DayCycleStripCard({required this.theme});
  final DayCycleTheme theme;

  @override
  ConsumerState<_DayCycleStripCard> createState() => _DayCycleStripCardState();
}

class _DayCycleStripCardState extends ConsumerState<_DayCycleStripCard> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
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
    final h = context.hud;
    final t = widget.theme;
    final activeId = ref.watch(activeDayCycleIdProvider);
    final isActive = activeId == t.id;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DayCycleDetailPage(theme: t)),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: h.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? HudTokens.gold.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.name,
                    style: GoogleFonts.fraunces(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: HudTokens.gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      LocaleHelper.pick(es: 'ACTIVO', en: 'ACTIVE'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                        color: HudTokens.goldBright,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _StripWithMarker(theme: t, now: _now, height: 36),
          ],
        ),
      ),
    );
  }
}

/// Renders the 4 phase images side-by-side with the live time marker.
class _StripWithMarker extends StatelessWidget {
  const _StripWithMarker({
    required this.theme,
    required this.now,
    required this.height,
  });
  final DayCycleTheme theme;
  final DateTime now;
  final double height;

  @override
  Widget build(BuildContext context) {
    final urls = [
      theme.morningUrl,
      theme.afternoonUrl,
      theme.eveningUrl,
      theme.nightUrl,
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final markerLeft = (_dayFraction(now) * w).clamp(0.0, w - 2);
            return Stack(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < urls.length; i++) ...[
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: i > 0
                                ? Border(
                                    left: BorderSide(
                                      color:
                                          Colors.black.withValues(alpha: 0.4),
                                      width: 0.5,
                                    ),
                                  )
                                : null,
                          ),
                          child: CachedNetworkImage(
                            imageUrl: urls[i],
                            fit: BoxFit.cover,
                            memCacheWidth: 220,
                            placeholder: (_, __) =>
                                Container(color: const Color(0xFF1A1A2A)),
                            errorWidget: (_, __, ___) =>
                                Container(color: const Color(0xFF1A1A2A)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // Period labels overlaid on each segment (only on tall strips)
                if (height >= 64)
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (var i = 0; i < 4; i++)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.45),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.55],
                                ),
                              ),
                              alignment: Alignment.topLeft,
                              child: Text(
                                _periodTime(i),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                // Live marker — vertical gold line + dot at top
                Positioned(
                  left: markerLeft,
                  top: 0,
                  bottom: 0,
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
                // Marker head dot
                Positioned(
                  left: markerLeft - 4,
                  top: -1,
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
      ),
    );
  }
}

class _AxisLabels extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final labels = ['00', '06', '12', '18', '24'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Text(
            labels[i],
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.35),
              letterSpacing: 0.4,
            ),
          ),
          if (i < labels.length - 1) const Spacer(),
        ],
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 0),
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: HudTokens.gold,
          letterSpacing: 2.4,
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────

double _dayFraction(DateTime now) {
  final secondsOfDay = now.hour * 3600 + now.minute * 60 + now.second;
  return secondsOfDay / 86400;
}

String _formatHHmm(DateTime now) =>
    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

String _periodTime(int idx) {
  switch (idx) {
    case 0:
      return '06:00';
    case 1:
      return '12:00';
    case 2:
      return '18:00';
    default:
      return '21:00';
  }
}

String _phaseAndCountdown(DateTime now) {
  final h = now.hour;
  String phase;
  int nextHour;
  String nextLabel;
  if (h >= 6 && h < 12) {
    phase = LocaleHelper.pick(es: 'MAÑANA', en: 'MORNING');
    nextHour = 12;
    nextLabel = LocaleHelper.pick(es: 'tarde', en: 'afternoon');
  } else if (h >= 12 && h < 18) {
    phase = LocaleHelper.pick(es: 'TARDE', en: 'AFTERNOON');
    nextHour = 18;
    nextLabel = LocaleHelper.pick(es: 'atardecer', en: 'evening');
  } else if (h >= 18 && h < 21) {
    phase = LocaleHelper.pick(es: 'ATARDECER', en: 'EVENING');
    nextHour = 21;
    nextLabel = LocaleHelper.pick(es: 'noche', en: 'night');
  } else {
    phase = LocaleHelper.pick(es: 'NOCHE', en: 'NIGHT');
    nextHour = h >= 21 ? 30 : 6; // 30 = 6am tomorrow
    nextLabel = LocaleHelper.pick(es: 'mañana', en: 'morning');
  }
  final mins = (nextHour * 60) - (h * 60 + now.minute);
  final hh = mins ~/ 60;
  final mm = mins % 60;
  final countdown =
      '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  return LocaleHelper.pick(
    es: '$phase · $countdown hasta $nextLabel',
    en: '$phase · $countdown to $nextLabel',
  );
}
