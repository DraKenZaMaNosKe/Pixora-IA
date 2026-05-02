import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    this.title,
    this.category,
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
  final String? title;

  /// Category / classification line under the title (small caps).
  final String? category;

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
    final h = (title ?? '').hashCode.abs();
    final hex = h.toRadixString(16).toUpperCase().padLeft(6, '0');
    return '${hex.substring(0, 3)}-${hex.substring(3, 5)}';
  }

  String _autoLot() {
    final n = (title ?? '').hashCode.abs() % 1000;
    return n.toString().padLeft(3, '0');
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    if (h.isIosStyle) return _buildIosCard(context);
    return _buildTicketCard(context);
  }

  /// iOS Photos-app inspired card. Used when iOS White theme is active.
  /// Drops the ticket metaphor entirely — just a clean image card with title.
  Widget _buildIosCard(BuildContext context) {
    final h = context.hud;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: h.bg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: isHighlighted ? 0.16 : 0.06),
              blurRadius: isHighlighted ? 18 : 12,
              offset: const Offset(0, 2),
            ),
          ],
          border:
              isHighlighted ? Border.all(color: h.accent, width: 1.5) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image with rounded top corners
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child,
                    if (overlayTopLeft != null)
                      Positioned(top: 8, left: 8, child: overlayTopLeft!),
                    if (overlayTopRight != null)
                      Positioned(top: 8, right: 8, child: overlayTopRight!),
                  ],
                ),
              ),
            ),
            // Title + meta in iOS style — only when caller provided text.
            // Wallpaper / Live / 3D listings pass null so the card is pure
            // image, letting the user explore without imposed labels.
            if (title != null || category != null || extraSeatLine != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(
                          h.bodyFontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: h.text,
                          letterSpacing: -0.2,
                        ),
                      ),
                    if (extraSeatLine != null || category != null) ...[
                      if (title != null) const SizedBox(height: 2),
                      Text(
                        extraSeatLine ?? category!.toLowerCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(
                          h.monoFontFamily,
                          fontSize: 10,
                          color: h.textDim,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Original Pixora Black & Gold "Ticket Stub" card.
  Widget _buildTicketCard(BuildContext context) {
    final lot = lotNumber ?? _autoLot();
    final ser = serial ?? _autoSerial();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.hud.surface,
          border: Border.all(
            color: isHighlighted
                ? context.hud.accent2
                : context.hud.accent.withValues(alpha: 0.55),
            width: isHighlighted ? 2 : 1,
          ),
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: context.hud.accent.withValues(alpha: 0.4),
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
                      color: context.hud.accent,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'N° $lot',
                    style: HudTokens.mono(
                      size: 8,
                      weight: FontWeight.w700,
                      color: context.hud.accent,
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
            // Skip entirely when caller wants a title-less card.
            if (title != null || category != null || extraSeatLine != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HudTokens.serif(
                                size: 12,
                                color: context.hud.text,
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
                              color: context.hud.accent,
                              letterSpacing: 0.15,
                            ),
                          ),
                        ],
                      ),
                    if (extraSeatLine != null || category != null) ...[
                      if (title != null) const SizedBox(height: 2),
                      Text(
                        extraSeatLine ?? category!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HudTokens.mono(
                          size: 7,
                          weight: FontWeight.w500,
                          color: context.hud.textDim,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
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
