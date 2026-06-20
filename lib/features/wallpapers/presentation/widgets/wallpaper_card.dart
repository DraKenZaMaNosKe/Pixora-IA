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
    // Type label: Eduardo elegido Propuesta 3 (halo glow + corner icon)
    // del mockup `docs/design/card_top_label_finalists.html`. Por ahora
    // solo distingue static vs panoramic — LIVE y 3D viven en otros
    // grids con su propio card.
    final type = wallpaper.isPanoramic
        ? PixoraCardKind.panoramic
        : PixoraCardKind.staticImage;

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
              cardKind: type,
              onToggleFav: () {
                ref.read(favoritesProvider.notifier).toggle(wallpaper.id);
              })
          : _TicketStubCard(
              wallpaper: wallpaper,
              isFav: isFav,
              cardKind: type,
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

/// Propuesta 3 — kind del contenido para halo glow + corner icon.
/// Live y canvasScene reservados; sus grids viven aparte y los aplicarán
/// en una segunda pasada cuando Eduardo apruebe la primera.
enum PixoraCardKind { staticImage, panoramic, live, canvasScene }

extension PixoraCardKindUI on PixoraCardKind {
  Color get color {
    switch (this) {
      case PixoraCardKind.staticImage:
        return const Color(0xFFE6B655); // gold
      case PixoraCardKind.panoramic:
        return const Color(0xFFFF2BD6); // magenta
      case PixoraCardKind.live:
        return const Color(0xFFFF6B9B); // hot pink
      case PixoraCardKind.canvasScene:
        return const Color(0xFF00F0FF); // cyan
    }
  }

  Color get glowColor {
    switch (this) {
      case PixoraCardKind.staticImage:
        return const Color(0xFFF5C766); // gold bright
      default:
        return color;
    }
  }

  String get cornerGlyph {
    switch (this) {
      case PixoraCardKind.staticImage:
        return '🖼';
      case PixoraCardKind.panoramic:
        return '⟷';
      case PixoraCardKind.live:
        return '▶';
      case PixoraCardKind.canvasScene:
        return '⬢';
    }
  }
}

/// Corner icon Propuesta 3 — 28×28 bg negra translúcida + glyph del color
/// del kind. Va en bottom-right por convención (top-right está reservado
/// para el ♥ favorito / HoloFoilPill en cards LIVE).
class PixoraCornerIcon extends StatelessWidget {
  const PixoraCornerIcon({super.key, required this.kind});
  final PixoraCardKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        kind.cornerGlyph,
        style: TextStyle(
          fontSize: 18,
          color: kind.color,
          height: 1,
        ),
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
    required this.cardKind,
    required this.onToggleFav,
  });
  final Wallpaper wallpaper;
  final bool isFav;
  final PixoraCardKind cardKind;
  final VoidCallback onToggleFav;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Container(
      decoration: BoxDecoration(
        color: h.bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          // Halo glow del tipo (Propuesta 3) — más sutil en iOS para no
          // romper el look limpio. Sombra negra base preserved para depth.
          BoxShadow(
            color: cardKind.color.withValues(alpha: 0.35),
            blurRadius: 14,
            spreadRadius: -1,
          ),
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
                  // Propuesta 3 — corner icon del tipo (bottom-right para
                  // no chocar con pills/badge superiores).
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: PixoraCornerIcon(kind: cardKind),
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
    required this.cardKind,
    required this.serial,
    required this.lotNumber,
    required this.seatLine,
    required this.onToggleFav,
  });
  final Wallpaper wallpaper;
  final bool isFav;
  final PixoraCardKind cardKind;
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
        // Propuesta 3 — el border del card adopta el color del tipo
        // (gold/static, magenta/pano). Mantiene la presencia del tema
        // pero comunica el kind sin perforar el image panel.
        border: Border.all(
          color: cardKind.color.withValues(alpha: 0.65),
          width: 1.2,
        ),
        boxShadow: [
          // Halo glow externo Propuesta 3 — replica el look del mockup
          // `box-shadow: 0 0 0 2px <color>, 0 0 22px -2px <color>`.
          BoxShadow(
            color: cardKind.glowColor.withValues(alpha: 0.55),
            blurRadius: 22,
            spreadRadius: -2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
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
                  // Propuesta 3 — corner icon kind. Bottom-right por
                  // convenio (top-right ocupado por el ♥).
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: PixoraCornerIcon(kind: cardKind),
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
