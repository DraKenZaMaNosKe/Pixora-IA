import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../../favorites/providers/favorites_provider.dart';
import '../../data/models/wallpaper.dart';
import '../pages/wallpaper_preview_page.dart';

/// Ticket Stub wallpaper card — Black & Gold.
///
/// Layout (top-to-bottom):
///   ┌────────────────────────────┐  ← thin gold border
///   │  ADMIT · ONE     N° 007    │  ← small-caps mono meta
///   │                            │
///   │       [wallpaper image]    │  ← main art
///   │                            │
///   ├ — — — — — — — — — — — — — ┤  ← dashed gold perforation
///   │  2B Automata      X27-AA   │  ← title italic + serial
///   │  ROW D · SEAT 7 · MMXXVI   │  ← seat meta (small caps)
///   └────────────────────────────┘
class WallpaperCard extends ConsumerWidget {
  const WallpaperCard({required this.wallpaper, super.key});

  final Wallpaper wallpaper;

  /// Deterministic 6-char "serial number" from the wallpaper id. Looks like
  /// "X27-AA" style. Pretty much hex of hash, uppercased.
  String _serial() {
    final h = wallpaper.id.hashCode.abs();
    final hex = h.toRadixString(16).toUpperCase().padLeft(6, '0');
    return '${hex.substring(0, 3)}-${hex.substring(3, 5)}';
  }

  /// Lot number for the "N° XXX" — small deterministic int.
  String _lotNumber() {
    final n = wallpaper.id.hashCode.abs() % 1000;
    return n.toString().padLeft(3, '0');
  }

  /// Seat-style line. Uses category + a deterministic row letter.
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
      child: Container(
        decoration: BoxDecoration(
          color: h.surface,
          border: Border.all(color: h.accent.withOpacity(0.55), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top stub: ADMIT · ONE | N° XXX ────────────
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
                    'N° ${_lotNumber()}',
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
            // ── Image panel ───────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedWallpaperImage(imageUrl: wallpaper.previewUrl),
                    // NEW / PANORAMIC tags top-left.
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
                    // Heart favorite top-right — refined typographic glyph.
                    Positioned(
                      right: 4,
                      top: 4,
                      child: GestureDetector(
                        onTap: () => ref
                            .read(favoritesProvider.notifier)
                            .toggle(wallpaper.id),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          color: h.bg.withOpacity(0.55),
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
            // ── Dashed gold perforation (torn-ticket line) ─
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: CustomPaint(
                size: const Size(double.infinity, 1),
                painter: _DashedLinePainter(color: h.accent),
              ),
            ),
            // ── Bottom stub: title + serial + seat line ───
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
                        _serial(),
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
                    _seatLine(),
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

/// Flat dashed gold line — the "torn-ticket" perforation between the two stubs.
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
