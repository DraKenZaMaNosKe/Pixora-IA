import 'package:flutter/material.dart';

import '../design/hud_tokens.dart';

/// Reusable Ticket Stub card — the signature Pixora Black & Gold layout.
///
/// Used everywhere cards appear: Wallpapers, LIVE, Stories, Day Cycle, Tones.
/// Keeps all sections visually coherent.
///
///   ┌──────────────────────────┐
///   │ ADMIT          N° 007    │  top stub
///   │                          │
///   │   [child content]        │  image / video / audio art
///   │                          │
///   ├ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┤  torn perforation
///   │ Title italic    SERIAL   │
///   │ CATEGORY · EXTRA          │
///   └──────────────────────────┘
class TicketStubCard extends StatelessWidget {
  const TicketStubCard({
    super.key,
    required this.child,
    required this.title,
    required this.category,
    this.lotNumber,
    this.serial,
    this.extraSeatLine,
    this.admitLabel = 'ADMIT',
    this.onTap,
    this.overlayTopLeft,
    this.overlayTopRight,
    this.width,
    this.height,
    this.isHighlighted = false,
  });

  /// Content inside the image panel (usually a CachedWallpaperImage + overlays).
  final Widget child;

  /// Main title shown in the bottom stub (italic serif).
  final String title;

  /// Category / classification line under the title (small caps).
  final String category;

  /// Lot "N°" — any stringifiable id. Defaults to auto-derived from title hash.
  final String? lotNumber;

  /// Serial number "X27-AA" — auto-derived from title if null.
  final String? serial;

  /// Extra seat line — e.g. "ROW D · SEAT 7 · MMXXVI". Null = not shown.
  final String? extraSeatLine;

  /// Top-left label — "ADMIT" by default. "LIVE", "STORY", "SOUND", etc.
  final String admitLabel;

  /// Tap action.
  final VoidCallback? onTap;

  /// Badges / stats overlays on the image (e.g. NEW badge, heart, play).
  final Widget? overlayTopLeft;
  final Widget? overlayTopRight;

  /// Explicit sizing. When both null, the card fills its parent.
  final double? width;
  final double? height;

  /// When true, the gold border is thicker and glows. Used for "playing" state.
  final bool isHighlighted;

  String _autoSerial() {
    final h = title.hashCode.abs();
    final hex = h.toRadixString(16).toUpperCase().padLeft(6, '0');
    return '${hex.substring(0, 3)}-${hex.substring(3, 5)}';
  }

  String _autoLot() {
    final n = title.hashCode.abs() % 1000;
    return n.toString().padLeft(3, '0');
  }

  @override
  Widget build(BuildContext context) {
    final lot = lotNumber ?? _autoLot();
    final ser = serial ?? _autoSerial();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: HudTokens.nightSurface,
          border: Border.all(
            color: isHighlighted
                ? HudTokens.goldBright
                : HudTokens.gold.withOpacity(0.55),
            width: isHighlighted ? 2 : 1,
          ),
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: HudTokens.gold.withOpacity(0.4),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top stub header ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
              child: Row(
                children: [
                  Text(
                    admitLabel,
                    style: HudTokens.mono(
                      size: 8,
                      weight: FontWeight.w700,
                      color: HudTokens.gold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'N° $lot',
                    style: HudTokens.mono(
                      size: 8,
                      weight: FontWeight.w700,
                      color: HudTokens.gold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            // ── Image / content panel ──────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      child,
                      if (overlayTopLeft != null)
                        Positioned(top: 4, left: 4, child: overlayTopLeft!),
                      if (overlayTopRight != null)
                        Positioned(top: 4, right: 4, child: overlayTopRight!),
                    ],
                  ),
                ),
              ),
            ),
            // ── Perforation ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: CustomPaint(
                size: const Size(double.infinity, 1),
                painter: _TicketDashPainter(),
              ),
            ),
            // ── Bottom stub ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HudTokens.serif(
                            size: 12,
                            color: HudTokens.nightText,
                            fontStyle: FontStyle.italic,
                            weight: FontWeight.w500,
                            letterSpacing: 0.02,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        ser,
                        style: HudTokens.mono(
                          size: 7.5,
                          weight: FontWeight.w700,
                          color: HudTokens.gold,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    extraSeatLine ?? category.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HudTokens.mono(
                      size: 7,
                      weight: FontWeight.w500,
                      color: HudTokens.nightTextDim,
                      letterSpacing: 0.3,
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

class _TicketDashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = HudTokens.gold
      ..strokeWidth = 1.0;
    const dash = 4.0;
    const gap = 3.0;
    double x = 0;
    while (x < size.width) {
      final end = (x + dash).clamp(0, size.width).toDouble();
      canvas.drawLine(Offset(x, 0), Offset(end, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TicketDashPainter old) => false;
}
