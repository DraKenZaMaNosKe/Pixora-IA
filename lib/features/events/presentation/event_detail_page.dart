import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/services/subscription_service.dart';
import '../data/models/event.dart';

/// Detail page when the user taps a polaroid in the EventosPage.
///
/// Layout:
///   - Big themed hero with the event icon + countdown
///   - Description paragraph (Fraunces italic)
///   - Wallpaper grid (placeholder until catalog wallpapers are linked)
///   - Sticky bottom CTA — "Ver colección" if Pro, "Suscribirse para acceder"
///     if not Pro. Past events show a soft "Recuerdo · finalizó hace X días".
class EventDetailPage extends StatelessWidget {
  const EventDetailPage({super.key, required this.event});
  final PixoraEvent event;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final hasAccess = SubscriptionService.instance.hasAccess;
    final lockedForUser = event.isProOnly && !hasAccess && !event.isPast;

    return Scaffold(
      backgroundColor: h.bg,
      body: Stack(
        children: [
          // Scrollable content
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(event: event),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                    child: _Body(event: event, h: h, locked: lockedForUser),
                  ),
                ],
              ),
            ),
          ),

          // Status bar — back button + share
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: Colors.white,
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),

          // Sticky CTA at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _StickyCta(
              event: event,
              h: h,
              locked: lockedForUser,
              hasAccess: hasAccess,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.event});
  final PixoraEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [event.themeColor, event.themeColorDark],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Giant icon, soft and offset
          Positioned(
            right: -40,
            bottom: -30,
            child: Opacity(
              opacity: 0.18,
              child: Text(
                event.icon,
                style: const TextStyle(fontSize: 320, height: 1),
              ),
            ),
          ),
          // Bottom dim for legibility
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.18),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                  ],
                  stops: const [0.0, 0.25, 0.6, 1.0],
                ),
              ),
            ),
          ),
          // Meta block
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (event.isActive)
                  _StatusPill(
                    text: 'EN VIVO · TERMINA EN ${event.daysUntil} DÍAS',
                    background: Colors.white,
                    color: event.themeColorDark,
                  )
                else if (event.isUpcoming)
                  _StatusPill(
                    text: 'PRÓXIMO · EN ${event.daysUntil} DÍAS',
                    background: Colors.white.withValues(alpha: 0.25),
                    color: Colors.white,
                  )
                else
                  _StatusPill(
                    text: 'RECUERDO · ${event.startsAt.year}',
                    background: Colors.white.withValues(alpha: 0.18),
                    color: Colors.white,
                  ),
                const SizedBox(height: 14),
                Text(
                  event.name,
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontStyle: FontStyle.italic,
                    fontSize: 42,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 0.95,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  event.formattedDateRange,
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 11,
                    letterSpacing: 1.4,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.background,
    required this.color,
  });
  final String text;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: color,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.event, required this.h, required this.locked});
  final PixoraEvent event;
  final HudTheme h;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Description with drop cap
        if (event.description.isNotEmpty)
          _DropCap(text: event.description, h: h, accent: event.themeColor),
        const SizedBox(height: 24),

        // Stats row
        Row(
          children: [
            _Stat(
              label: 'Wallpapers',
              value: '${event.wallpaperCount}',
              h: h,
              accent: event.themeColor,
            ),
            const SizedBox(width: 30),
            _Stat(
              label: 'Acceso',
              value: event.isProOnly ? 'PRO' : 'Libre',
              h: h,
              accent: event.themeColor,
            ),
            const SizedBox(width: 30),
            _Stat(
              label: event.isActive
                  ? 'Termina en'
                  : (event.isUpcoming ? 'Empieza en' : 'Hace'),
              value: event.isPast
                  ? '${DateTime.now().toUtc().difference(event.endsAt).inDays}d'
                  : '${event.daysUntil}d',
              h: h,
              accent: event.themeColor,
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Tags
        if (event.tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: event.tags
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: event.themeColor.withValues(alpha: 0.12),
                        border: Border.all(
                            color: event.themeColor.withValues(alpha: 0.35)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: event.themeColor,
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 28),
        ],

        // Wallpapers grid placeholder (real items come once event_wallpapers
        // is populated server-side — for now we show themed placeholder tiles)
        Text(
          'Vista previa de la colección',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 11,
            letterSpacing: 2,
            color: h.textDim,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 9 / 16,
          ),
          itemCount: event.wallpaperCount.clamp(0, 9),
          itemBuilder: (_, i) => _PlaceholderTile(
            event: event,
            locked: locked,
            index: i,
          ),
        ),
      ],
    );
  }
}

class _DropCap extends StatelessWidget {
  const _DropCap({required this.text, required this.h, required this.accent});
  final String text;
  final HudTheme h;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final first = text.substring(0, 1);
    final rest = text.substring(1);
    return Container(
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 2)),
      ),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontStyle: FontStyle.italic,
            fontSize: 16,
            height: 1.55,
            color: h.text.withValues(alpha: 0.88),
          ),
          children: [
            TextSpan(
              text: first,
              style: TextStyle(
                fontSize: 50,
                height: 0.85,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.normal,
                color: accent,
              ),
            ),
            TextSpan(text: rest),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.h,
    required this.accent,
  });
  final String label;
  final String value;
  final HudTheme h;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 9,
            letterSpacing: 1.6,
            color: h.textDim,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: accent,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _PlaceholderTile extends StatelessWidget {
  const _PlaceholderTile({
    required this.event,
    required this.locked,
    required this.index,
  });
  final PixoraEvent event;
  final bool locked;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            event.themeColor.withValues(alpha: locked ? 0.35 : 0.65),
            event.themeColorDark.withValues(alpha: locked ? 0.45 : 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: locked
          ? const Icon(Icons.lock, color: Colors.white70, size: 22)
          : Text(event.icon, style: const TextStyle(fontSize: 36)),
    );
  }
}

class _StickyCta extends StatelessWidget {
  const _StickyCta({
    required this.event,
    required this.h,
    required this.locked,
    required this.hasAccess,
  });
  final PixoraEvent event;
  final HudTheme h;
  final bool locked;
  final bool hasAccess;

  @override
  Widget build(BuildContext context) {
    String label;
    if (event.isPast) {
      label = hasAccess ? 'Revivir el recuerdo' : 'Ver wallpapers (Pro)';
    } else if (locked) {
      label = '🔒  Hazte Pro · \$49 / mes';
    } else if (event.isUpcoming) {
      label = 'Recuérdamelo cuando empiece';
    } else {
      label = 'Ver colección completa';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      decoration: BoxDecoration(
        color: h.bg,
        boxShadow: [
          BoxShadow(
            color: h.bg.withValues(alpha: 0.95),
            offset: const Offset(0, -10),
            blurRadius: 20,
          ),
        ],
        border: Border(top: BorderSide(color: h.divider, width: 0.5)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: () => _onCta(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: event.themeColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onCta(BuildContext context) async {
    if (locked) {
      // Trigger Google Play subscription purchase sheet
      final ok = await SubscriptionService.instance.buyMonthly();
      if (ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Bienvenido a Pixora Pro!')),
        );
      }
      return;
    }
    if (event.isUpcoming) {
      // TODO: hook into local notifications when reminder service is available
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Te avisaremos cuando arranque ${event.name}.'),
        ),
      );
      return;
    }
    // For active / past unlocked: scroll to wallpapers section once they're
    // wired into the catalog. For now, just inform.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wallpapers de este evento próximamente.')),
    );
  }
}
