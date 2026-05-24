import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/design/hud_tokens.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/app_strings_service.dart';
import '../data/models/event.dart';
import '../providers/events_provider.dart';
import 'event_detail_page.dart';

/// "Eventos" section — Streetwear Lookbook layout (concept v2 #03, Eduardo
/// 2026-05-16). Each event is a "drop": huge Bebas Neue date is the visual
/// hero, edition serial number ("EDITION 003 / FW26"), per-event accent
/// color (Halloween orange, Muertos magenta, Independencia emerald, Madre
/// rose). Past drops get a "SOLD OUT" stripe — creates collection FOMO.
///
/// Vibe: Supreme / A24 / Off-White drop schedule. Drops drive subscription.
class EventosPage extends ConsumerWidget {
  const EventosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = context.hud;
    final async = ref.watch(eventsProvider);
    return Container(
      color: h.bg,
      child: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: h.accent, strokeWidth: 2),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No se pudo cargar el lineup de drops.\nIntenta de nuevo en un momento.',
                textAlign: TextAlign.center,
                style: TextStyle(color: h.textDim, fontSize: 14, height: 1.5),
              ),
            ),
          ),
          data: (events) {
            if (events.isEmpty) return _Empty(h: h);
            return RefreshIndicator(
              color: h.accent,
              onRefresh: () async {
                ref.invalidate(eventsProvider);
                await Future.wait([
                  ref.read(eventsProvider.future),
                  AppStringsService.instance.refresh(),
                ]);
              },
              child: _LookbookLayout(events: events, h: h),
            );
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.h});
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_outlined, size: 56, color: h.textDim),
          const SizedBox(height: 18),
          Text(
            '// LINEUP',
            textAlign: TextAlign.center,
            style: GoogleFonts.bebasNeue(
              fontSize: 14,
              color: h.accent,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pixora Drops',
            textAlign: TextAlign.center,
            style: GoogleFonts.bebasNeue(
              fontSize: 38,
              color: h.text,
              letterSpacing: 1,
              height: 1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Próximamente — drops limitados de wallpapers exclusivos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: h.textDim, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _LookbookLayout extends StatelessWidget {
  const _LookbookLayout({required this.events, required this.h});
  final List<PixoraEvent> events;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    final active = events.where((e) => e.isActive).toList();
    final upcoming = events.where((e) => e.isUpcoming).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = events.where((e) => e.isPast).toList()
      ..sort((a, b) => b.endsAt.compareTo(a.endsAt));

    final lineup = [...active, ...upcoming];

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 40),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _LineupHeading(count: lineup.length, h: h),
        const SizedBox(height: 14),
        if (lineup.isNotEmpty)
          for (int i = 0; i < lineup.length; i++) ...[
            _DropCard(
              event: lineup[i],
              h: h,
              edition: i + 1,
              isLive: lineup[i].isActive,
              onTap: () => _open(context, lineup[i]),
            ),
            if (i < lineup.length - 1) const SizedBox(height: 10),
          ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: 28),
          _PastLineupHeading(count: past.length, h: h),
          const SizedBox(height: 10),
          for (int i = 0; i < past.length; i++) ...[
            _PastDropCard(
              event: past[i],
              h: h,
              edition: i + 1,
              onTap: () => _open(context, past[i]),
            ),
            if (i < past.length - 1) const SizedBox(height: 6),
          ],
        ],
      ],
    );
  }

  void _open(BuildContext context, PixoraEvent event) {
    AnalyticsService.instance.trackEventOpened(event.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventDetailPage(event: event)),
    );
  }
}

class _LineupHeading extends StatelessWidget {
  const _LineupHeading({required this.count, required this.h});
  final int count;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '// LINEUP · PRÓXIMAMENTE',
            style: GoogleFonts.bebasNeue(
              fontSize: 14,
              color: h.text,
              letterSpacing: 2.4,
              height: 1,
            ),
          ),
          const Spacer(),
          Text(
            '${count.toString().padLeft(2, '0')} DROPS',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: h.textDim,
              letterSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _PastLineupHeading extends StatelessWidget {
  const _PastLineupHeading({required this.count, required this.h});
  final int count;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '// PAST LINEUP',
            style: GoogleFonts.bebasNeue(
              fontSize: 12,
              color: h.textDim,
              letterSpacing: 2.4,
              height: 1,
            ),
          ),
          const Spacer(),
          Text(
            '${count.toString().padLeft(2, '0')} SOLD OUT',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: h.textDim,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Main drop card — date-side (left) + pic-side (right). Per-event accent
/// color drives the date typography and gradient.
class _DropCard extends StatelessWidget {
  const _DropCard({
    required this.event,
    required this.h,
    required this.edition,
    required this.isLive,
    required this.onTap,
  });
  final PixoraEvent event;
  final HudTheme h;
  final int edition;
  final bool isLive;
  final VoidCallback onTap;

  String get _bigDate {
    final m = event.startsAt.month.toString().padLeft(2, '0');
    final d = event.startsAt.day.toString().padLeft(2, '0');
    return '$m.$d';
  }

  String get _monthLabel {
    const months = [
      'ENE',
      'FEB',
      'MAR',
      'ABR',
      'MAY',
      'JUN',
      'JUL',
      'AGO',
      'SEP',
      'OCT',
      'NOV',
      'DIC',
    ];
    return '${months[event.startsAt.month - 1]} ${event.startsAt.year}';
  }

  String get _serial =>
      'EDITION ${edition.toString().padLeft(3, '0')} / ${_seasonTag()}';

  String _seasonTag() {
    final m = event.startsAt.month;
    // FW = Sept-Feb, SS = Mar-Aug
    final season = (m >= 9 || m <= 2) ? 'FW' : 'SS';
    final yy = event.startsAt.year.toString().substring(2);
    return '$season$yy';
  }

  String get _releaseTag => isLive ? 'AVAILABLE NOW' : 'AVAILABLE $_bigDate';

  @override
  Widget build(BuildContext context) {
    final isIos = h.isIosStyle;
    final accent = event.themeColor;
    final accentDark = event.themeColorDark;
    final cardBg = isIos ? const Color(0xFF1A1A1A) : h.surface;
    final dateBig = isIos ? accent : HudTokens.goldBright;
    final monthDim = Colors.white.withValues(alpha: 0.55);
    final serialDim = Colors.white.withValues(alpha: 0.4);
    final releaseColor = isIos ? Colors.white : HudTokens.goldBright;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              border: isIos
                  ? null
                  : Border.all(
                      color: HudTokens.gold.withValues(alpha: 0.18),
                      width: 1,
                    ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Date-side
                  Expanded(
                    flex: 105,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _bigDate,
                                style: GoogleFonts.bebasNeue(
                                  fontSize: 48,
                                  color: dateBig,
                                  letterSpacing: -0.5,
                                  height: 0.85,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _monthLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: monthDim,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                event.name.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.bebasNeue(
                                  fontSize: 18,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _serial,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w600,
                                  color: serialDim,
                                  letterSpacing: 1.8,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _releaseTag,
                                style: GoogleFonts.bebasNeue(
                                  fontSize: 11,
                                  color: releaseColor,
                                  letterSpacing: 1.6,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Pic-side
                  Expanded(
                    flex: 100,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [accentDark, accent],
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Radial highlights
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(-0.3, -0.2),
                                  radius: 0.7,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.18),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Giant emoji icon (low opacity for depth)
                          Center(
                            child: Opacity(
                              opacity: 0.55,
                              child: Text(
                                event.icon,
                                style: const TextStyle(
                                  fontSize: 70,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                          // EN VIVO sticker if active
                          if (isLive)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFCC3333),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  'LIVE',
                                  style: GoogleFonts.bebasNeue(
                                    fontSize: 9,
                                    color: Colors.white,
                                    letterSpacing: 1.5,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          // White stripe with edition mini-tag bottom-right
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                              child: Text(
                                _seasonTag(),
                                style: GoogleFonts.inter(
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                  letterSpacing: 1.2,
                                ),
                              ),
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
        ),
      ),
    );
  }
}

/// Past drop — small archival card with "SOLD OUT" stripe.
class _PastDropCard extends StatelessWidget {
  const _PastDropCard({
    required this.event,
    required this.h,
    required this.edition,
    required this.onTap,
  });
  final PixoraEvent event;
  final HudTheme h;
  final int edition;
  final VoidCallback onTap;

  String get _shortDate {
    final m = event.startsAt.month.toString().padLeft(2, '0');
    final d = event.startsAt.day.toString().padLeft(2, '0');
    return '$m.$d';
  }

  @override
  Widget build(BuildContext context) {
    final isIos = h.isIosStyle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: isIos
                  ? const Color(0xFF2A2A2A)
                  : h.surface.withValues(alpha: 0.6),
              border: isIos
                  ? null
                  : Border.all(
                      color: HudTokens.gold.withValues(alpha: 0.10),
                      width: 1,
                    ),
            ),
            child: Row(
              children: [
                // Small thumb
                Container(
                  width: 56,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [event.themeColorDark, event.themeColor],
                    ),
                  ),
                  child: Center(
                    child: Opacity(
                      opacity: 0.55,
                      child: Text(
                        event.icon,
                        style: const TextStyle(fontSize: 24, height: 1),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        event.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.bebasNeue(
                          fontSize: 13,
                          color: Colors.white,
                          letterSpacing: 1.0,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$_shortDate · EDITION ${edition.toString().padLeft(3, '0')}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.5),
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                // SOLD OUT stripe
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                  ),
                  child: Text(
                    'SOLD OUT',
                    style: GoogleFonts.bebasNeue(
                      fontSize: 11,
                      color: isIos ? Colors.white : HudTokens.goldBright,
                      letterSpacing: 1.8,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
