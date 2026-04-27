import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../../favorites/providers/favorites_provider.dart';
import '../../data/models/wallpaper.dart';
import '../pages/wallpaper_preview_page.dart';

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
                  // PANO/NEW pill (rounded iOS style)
                  if (wallpaper.badge != null ||
                      wallpaper.category == 'PANORAMIC')
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Row(
                        children: [
                          if (wallpaper.category == 'PANORAMIC')
                            _IosPill(label: 'PANO', color: h.accent),
                          if (wallpaper.category == 'PANORAMIC' &&
                              wallpaper.badge != null)
                            const SizedBox(width: 6),
                          if (wallpaper.badge != null)
                            _IosPill(
                                label: wallpaper.badge!.toUpperCase(),
                                color: h.accent),
                        ],
                      ),
                    ),
                  // Heart on circular blurred bg (iOS-style)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: GestureDetector(
                      onTap: onToggleFav,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.85),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          size: 16,
                          color: isFav ? const Color(0xFFFF3B30) : h.textDim,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Title + meta in iOS style
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallpaper.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(
              h.bodyFontFamily.isEmpty ? 'Inter' : h.bodyFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: h.text,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  wallpaper.category.isEmpty
                      ? 'Pixora'
                      : wallpaper.category.toLowerCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(
              h.monoFontFamily.isEmpty ? 'Inter' : h.monoFontFamily,
                    fontSize: 10,
                    color: h.textDim,
                    letterSpacing: 0.2,
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

class _IosPill extends StatelessWidget {
  const _IosPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.getFont(
          'Geist',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
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
                      wallpaper.category == 'PANORAMIC')
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Row(
                        children: [
                          if (wallpaper.category == 'PANORAMIC')
                            _tag('PANO', h.goldBright, h.bg),
                          if (wallpaper.category == 'PANORAMIC' &&
                              wallpaper.badge != null)
                            const SizedBox(width: 4),
                          if (wallpaper.badge != null)
                            _tag(wallpaper.badge!.toUpperCase(), h.accent,
                                Colors.black),
                        ],
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        wallpaper.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HudTokens.serif(
                          size: 14,
                          color: h.text,
                          fontStyle: FontStyle.italic,
                          weight: FontWeight.w500,
                          letterSpacing: 0.02,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      serial,
                      style: HudTokens.mono(
                        size: 9,
                        weight: FontWeight.w700,
                        color: h.accent,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  seatLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HudTokens.mono(
                    size: 7.5,
                    weight: FontWeight.w500,
                    color: h.textDim,
                    letterSpacing: 0.25,
                  ),
                ),
              ],
            ),
          ),
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
