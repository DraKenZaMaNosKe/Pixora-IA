import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../../favorites/providers/favorites_provider.dart';
import 'grid_card_animations.dart';
import '../../data/models/wallpaper.dart';
import '../pages/wallpaper_preview_page.dart';
import '../../../../core/widgets/watch_card_pieces.dart';

/// Wallpaper card — switches layout per active theme:
///   - Black & Gold / Cream Day → "Ticket Stub" (admit-one ticket metaphor)
///   - iOS White → clean iOS Photos-app card (rounded image + title)
///
/// The iOS variant prioritizes the IMAGE (rounded, big, no chrome around it),
/// matches the user's note that "tickets/cards have to look iOS, the images
/// are the main thing".
class WallpaperCard extends ConsumerWidget {
  const WallpaperCard({required this.wallpaper, super.key});

  final Wallpaper wallpaper;

  String _serial() {
    final h = wallpaper.id.hashCode.abs();
    final hex = h.toRadixString(16).toUpperCase().padLeft(6, '0');
    return '${hex.substring(0, 3)}-${hex.substring(3, 5)}';
  }

  String _lotNumber() {
    final n = wallpaper.id.hashCode.abs() % 1000;
    return n.toString().padLeft(3, '0');
  }

  String _seatLine() {
    final row = String.fromCharCode(
      65 + (wallpaper.id.hashCode.abs() % 26),
    );
    final seat = (wallpaper.id.hashCode.abs() % 30) + 1;
    return 'ROW $row · SEAT $seat · ${wallpaper.category.toUpperCase()}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = context.hud;
    final isFav = ref.watch(favoritesProvider).contains(wallpaper.id);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WallpaperPreviewPage(wallpaper: wallpaper),
          ),
        );
      },
      child: h.isIosStyle
          ? _IosCard(
              wallpaper: wallpaper,
              isFav: isFav,
              onToggleFav: () {
                ref.read(favoritesProvider.notifier).toggle(wallpaper.id);
              })
          : _TicketStubCard(
              wallpaper: wallpaper,
              isFav: isFav,
              serial: _serial(),
              lotNumber: _lotNumber(),
              seatLine: _seatLine(),
              onToggleFav: () {
                ref.read(favoritesProvider.notifier).toggle(wallpaper.id);
              },
            ),
    );
  }
}

/// iOS Photos-app inspired card. Rounded image, white bg, soft shadow,
/// title underneath in Geist body font. No ticket metaphor.
class _IosCard extends StatelessWidget {
  const _IosCard({
    required this.wallpaper,
    required this.isFav,
    required this.onToggleFav,
  });
  final Wallpaper wallpaper;
  final bool isFav;
  final VoidCallback onToggleFav;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Container(
      decoration: BoxDecoration(
        color: h.bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Image with rounded top corners
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedWallpaperImage(imageUrl: wallpaper.previewUrl),
                  // PANO/NEW/CÓDICE pill row (rounded iOS style).
                  // The CÓDICE pill flags wallpapers with editorial cultural
                  // content — encourages users to tap and discover the lore.
                  // Watch Cartouche pills (concept #04, Eduardo 2026-05-16)
                  // — para PANO/NEW/CÓDICE. Mismo recipe que LIVE cards.
                  if (wallpaper.badge != null ||
                      wallpaper.isPanoramic ||
                      wallpaper.cultural != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      right: 8,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (wallpaper.isPanoramic)
                            const WatchCartouchePill(label: 'PANO'),
                          if (wallpaper.badge != null)
                            WatchCartouchePill(
                                label: wallpaper.badge!.toUpperCase()),
                          if (wallpaper.cultural != null)
                            const WatchCartouchePill(label: '📜 CÓDICE'),
                        ],
                      ),
                    ),
                  // Activity Rings bottom-centered (likes/views/downloads
                  // como anillos Apple Watch — épico + social proof)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Center(
                      child: ActivityRings(wallpaperId: wallpaper.id),
                    ),
                  ),
                  // 2026-06-13 — Overlay reactivo para mostrar like/view de
                  // otros usuarios en tiempo real (Pulse Border + Magnetic
                  // Attract + Lightning para like; Scan Line + Viewport
                  // Corners + Number Ascend para view). Suscrito al
                  // statsEventStream — costo cero si no hay eventos.
                  Positioned.fill(
                    child: GridCardAnimationOverlay(
                      wallpaperId: wallpaper.id,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Title + meta intentionally hidden — user wants to explore by
          // image alone, no labels imposing a thought before they see it.
        ],
      ),
    );
  }
}

/// Original Ticket Stub design — kept for Black & Gold and Cream Day themes.
class _TicketStubCard extends StatelessWidget {
  const _TicketStubCard({
    required this.wallpaper,
    required this.isFav,
    required this.serial,
    required this.lotNumber,
    required this.seatLine,
    required this.onToggleFav,
  });
  final Wallpaper wallpaper;
  final bool isFav;
  final String serial;
  final String lotNumber;
  final String seatLine;
  final VoidCallback onToggleFav;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Container(
      decoration: BoxDecoration(
        color: h.surface,
        border: Border.all(color: h.accent.withValues(alpha: 0.55), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
            child: Row(
              children: [
                Text(
                  'ADMIT · ONE',
                  style: HudTokens.mono(
                    size: 8.5,
                    weight: FontWeight.w700,
                    color: h.accent,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  'N° $lotNumber',
                  style: HudTokens.mono(
                    size: 8.5,
                    weight: FontWeight.w700,
                    color: h.accent,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedWallpaperImage(imageUrl: wallpaper.previewUrl),
                  if (wallpaper.badge != null ||
                      wallpaper.isPanoramic ||
                      wallpaper.cultural != null)
                    Positioned(
                      left: 4,
                      top: 4,
                      right: 4,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (wallpaper.isPanoramic)
                            _tag('PANO', h.goldBright, h.bg),
                          if (wallpaper.badge != null)
                            _tag(wallpaper.badge!.toUpperCase(), h.accent,
                                Colors.black),
                          // Cultural badge — invites users to discover the
                          // mythological/historical lore of the wallpaper.
                          if (wallpaper.cultural != null)
                            _tag('📜 CÓDICE', h.accent, Colors.black),
                        ],
                      ),
                    ),
                  // 2026-06-13 — animaciones reactivas para likes y views
                  // entrantes via Realtime (mismo widget que la card iOS).
                  Positioned.fill(
                    child: GridCardAnimationOverlay(
                      wallpaperId: wallpaper.id,
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: GestureDetector(
                      onTap: onToggleFav,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        color: h.bg.withValues(alpha: 0.55),
                        child: Text(
                          isFav ? '♥' : '♡',
                          style: TextStyle(
                            color: isFav ? h.accent2 : Colors.white70,
                            fontSize: 14,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: CustomPaint(
              size: const Size(double.infinity, 1),
              painter: _DashedLinePainter(color: h.accent),
            ),
          ),
          // Title block (name + serial + seatLine) intentionally hidden —
          // user wants pure-image cards so the wallpaper speaks first, no
          // text imposing a thought before the eye lands on it.
        ],
      ),
    );
  }

  Widget _tag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: bg,
      child: Text(
        text,
        style: HudTokens.mono(
          size: 9,
          weight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const dash = 5.0;
    const gap = 3.5;
    double x = 0;
    while (x < size.width) {
      final end = (x + dash).clamp(0, size.width).toDouble();
      canvas.drawLine(Offset(x, 0), Offset(end, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
