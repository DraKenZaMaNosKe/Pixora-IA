import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/design/hud_tokens.dart';
import '../data/models/event.dart';
import '../providers/events_provider.dart';
import 'event_detail_page.dart';

/// Handwritten Caveat style helper used across polaroids. Fetched from
/// Google Fonts on first use, then cached locally — no asset declaration
/// needed. Falls back to system cursive if the font fails to load.
TextStyle _caveat({required double size, FontWeight? weight, Color? color}) {
  return GoogleFonts.caveat(
    fontSize: size,
    fontWeight: weight ?? FontWeight.w500,
    color: color,
    height: 1,
  );
}

/// "Eventos" section — Polaroid Album layout (design #09 from
/// pixora_events_concepts.html, picked by user 2026-05-04).
///
/// Header: handwritten "mi álbum" + serif title.
/// Active event(s): big polaroid with rotation + EN VIVO red pin.
/// Upcoming/past: smaller polaroids in a horizontal scrolling row.
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
                'No se pudo cargar el álbum de eventos.\nIntenta de nuevo en un momento.',
                textAlign: TextAlign.center,
                style: TextStyle(color: h.textDim, fontSize: 14, height: 1.5),
              ),
            ),
          ),
          data: (events) {
            if (events.isEmpty) {
              return _Empty(h: h);
            }
            return RefreshIndicator(
              color: h.accent,
              onRefresh: () async {
                ref.invalidate(eventsProvider);
                await ref.read(eventsProvider.future);
              },
              child: _PolaroidAlbum(events: events, h: h),
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
          Icon(Icons.event_note_outlined, size: 56, color: h.textDim),
          const SizedBox(height: 18),
          Text(
            'mi álbum',
            textAlign: TextAlign.center,
            style: _caveat(size: 28, color: h.accent),
          ),
          const SizedBox(height: 4),
          Text(
            'Eventos Pixora',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 26,
              color: h.text,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Próximamente — celebraciones de temporada con wallpapers exclusivos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: h.textDim, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _PolaroidAlbum extends StatelessWidget {
  const _PolaroidAlbum({required this.events, required this.h});
  final List<PixoraEvent> events;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    final active = events.where((e) => e.isActive).toList();
    final upcoming = events.where((e) => e.isUpcoming).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = events.where((e) => e.isPast).toList()
      ..sort((a, b) => b.endsAt.compareTo(a.endsAt));

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 32, 0, 40),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _Header(h: h),
        const SizedBox(height: 22),

        // Active polaroid(s) — featured big with EN VIVO pin
        if (active.isNotEmpty) ...[
          for (final e in active)
            _ActivePolaroid(event: e, h: h, onTap: () => _open(context, e)),
          const SizedBox(height: 26),
        ],

        // Upcoming row — horizontal scrollable polaroids
        if (upcoming.isNotEmpty) ...[
          _SectionHeading(text: 'Próximamente', h: h),
          const SizedBox(height: 12),
          _PolaroidRow(
              events: upcoming,
              h: h,
              isPast: false,
              onTap: (e) => _open(context, e)),
          const SizedBox(height: 24),
        ],

        // Past row — same row, slight desaturation/opacity
        if (past.isNotEmpty) ...[
          _SectionHeading(text: 'Recuerdos', h: h),
          const SizedBox(height: 12),
          _PolaroidRow(
              events: past,
              h: h,
              isPast: true,
              onTap: (e) => _open(context, e)),
        ],
      ],
    );
  }

  void _open(BuildContext context, PixoraEvent event) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventDetailPage(event: event)),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.h});
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '— mi álbum —',
            style: _caveat(size: 24, color: h.accent),
          ),
          const SizedBox(height: 6),
          Text(
            'Eventos Pixora',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 32,
              fontWeight: FontWeight.w500,
              color: h.text,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.text, required this.h});
  final String text;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontStyle: FontStyle.italic,
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: h.textDim,
        ),
      ),
    );
  }
}

/// Big featured polaroid for currently-active events.
/// Slight rotation, paper white background, polaroid bottom area for the title.
class _ActivePolaroid extends StatelessWidget {
  const _ActivePolaroid({
    required this.event,
    required this.h,
    required this.onTap,
  });
  final PixoraEvent event;
  final HudTheme h;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
      child: GestureDetector(
        onTap: onTap,
        child: Transform.rotate(
          angle: -0.026, // ~-1.5 degrees
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAF6), // paper white, theme-independent
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  child: Column(
                    children: [
                      // The "photo" — gradient with the event's theme + giant icon
                      AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(1),
                          child: _ThemeGradient(event: event, iconSize: 200),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        event.name,
                        textAlign: TextAlign.center,
                        style:
                            _caveat(size: 28, color: const Color(0xFF1A1A1A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.formattedDateRange,
                        textAlign: TextAlign.center,
                        style:
                            _caveat(size: 16, color: const Color(0xFF888888)),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
                // EN VIVO pin (rotated, looks taped on)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Transform.rotate(
                    angle: 0.14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCC3333),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Text(
                        'EN VIVO',
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PolaroidRow extends StatelessWidget {
  const _PolaroidRow({
    required this.events,
    required this.h,
    required this.isPast,
    required this.onTap,
  });
  final List<PixoraEvent> events;
  final HudTheme h;
  final bool isPast;
  final ValueChanged<PixoraEvent> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _MiniPolaroid(
          event: events[i],
          isPast: isPast,
          rotationIndex: i,
          onTap: () => onTap(events[i]),
        ),
      ),
    );
  }
}

class _MiniPolaroid extends StatelessWidget {
  const _MiniPolaroid({
    required this.event,
    required this.isPast,
    required this.rotationIndex,
    required this.onTap,
  });
  final PixoraEvent event;
  final bool isPast;
  final int rotationIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Vary rotation slightly so the row doesn't look mechanical
    final angles = [-0.035, 0.026, -0.018, 0.04, -0.022, 0.03];
    final angle = angles[rotationIndex % angles.length];

    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: angle,
        child: Opacity(
          opacity: isPast ? 0.65 : 1.0,
          child: Container(
            width: 130,
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAF6),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: _ThemeGradient(event: event, iconSize: 56),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _caveat(size: 16, color: const Color(0xFF1A1A1A)),
                  ),
                  Text(
                    event.formattedDateRange.split(' · ').first,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _caveat(size: 12, color: const Color(0xFF888888)),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Themed gradient "photo" with the event's color and giant icon (emoji).
/// Used inside polaroids — no real wallpaper image needed for the album view.
class _ThemeGradient extends StatelessWidget {
  const _ThemeGradient({required this.event, required this.iconSize});
  final PixoraEvent event;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [event.themeColor, event.themeColorDark],
        ),
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft inner shadow / vignette
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.18),
                ],
                stops: const [0.6, 1.0],
              ),
            ),
          ),
          // Giant icon (emoji) with subtle white tint background for readability
          Opacity(
            opacity: 0.42,
            child: Text(
              event.icon,
              style: TextStyle(fontSize: iconSize, height: 1),
            ),
          ),
        ],
      ),
    );
  }
}
