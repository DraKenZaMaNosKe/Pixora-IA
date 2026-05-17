import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/hud_tokens.dart';

/// Stamped Foil section header — concept #01 (Eduardo 2026-05-16).
///
/// Sello metálico con outline fino + glifo ★ + shimmer suave cada 4.5s.
/// Shared across WALLPAPERS carousel rows and the LIVE page section titles
/// so the entire app speaks one section-header language.
///
/// * **iOS White**: light foil gradient, dark text, hairline border, Apple
///   Blue glyph.
/// * **Black & Gold**: gold foil tint, gold-bright text, gold-deep border,
///   soft gold glow.
///
/// Pass [trailing] to render a "SEE ALL" action on the right side (kept on
/// the same baseline so the header still reads as one editorial unit).
class StampedFoilHeader extends StatefulWidget {
  const StampedFoilHeader({
    super.key,
    required this.label,
    this.glyph = '★',
    this.trailing,
  });

  final String label;
  final String glyph;
  final Widget? trailing;

  @override
  State<StampedFoilHeader> createState() => _StampedFoilHeaderState();
}

class _StampedFoilHeaderState extends State<StampedFoilHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    const iosBlue = Color(0xFF0A84FF);

    final List<Color> bgGradient;
    final Color borderColor;
    final Color textColor;
    final Color glyphColor;
    final List<BoxShadow>? boxShadows;
    final Shadow? textShadow;
    final Shadow? glyphShadow;

    if (isIos) {
      bgGradient = const [Color(0xFFFAFAFD), Color(0xFFECECF2)];
      borderColor = const Color(0xFF1C1C1E).withValues(alpha: 0.55);
      textColor = const Color(0xFF1C1C1E);
      glyphColor = iosBlue;
      boxShadows = null;
      textShadow = null;
      glyphShadow = null;
    } else {
      bgGradient = [
        HudTokens.gold.withValues(alpha: 0.10),
        HudTokens.gold.withValues(alpha: 0.02),
      ];
      borderColor = HudTokens.goldDeep;
      textColor = HudTokens.goldBright;
      glyphColor = HudTokens.goldBright;
      boxShadows = [
        BoxShadow(
          color: HudTokens.gold.withValues(alpha: 0.18),
          blurRadius: 12,
        ),
      ];
      textShadow = Shadow(
        color: Colors.black.withValues(alpha: 0.5),
        offset: const Offset(0, 1),
      );
      glyphShadow = Shadow(
        color: HudTokens.goldBright.withValues(alpha: 0.6),
        blurRadius: 6,
      );
    }

    final stamp = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: bgGradient,
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: boxShadows,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.glyph,
                  style: TextStyle(
                    color: glyphColor,
                    fontSize: 11,
                    height: 1,
                    shadows: glyphShadow != null ? [glyphShadow] : null,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  widget.label.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: 1.4,
                    height: 1,
                    shadows: textShadow != null ? [textShadow] : null,
                  ),
                ),
              ],
            ),
          ),
          // Shimmer — sweeps across every 4.5s
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _shimmer,
                builder: (_, __) {
                  final v = _shimmer.value;
                  final double t;
                  if (v < 0.60) {
                    t = -1.0;
                  } else if (v < 0.80) {
                    t = -1.0 + ((v - 0.60) / 0.20) * 2.0;
                  } else {
                    t = 1.0;
                  }
                  return FractionalTranslation(
                    translation: Offset(t, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: const Alignment(-0.5, -1),
                          end: const Alignment(0.5, 1),
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(
                              alpha: isIos ? 0.55 : 0.28,
                            ),
                            Colors.transparent,
                          ],
                          stops: const [0.30, 0.50, 0.70],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );

    // Align(centerLeft) shrinks the ClipRRect/Stack to the stamp's intrinsic
    // size — without this, when a parent passes tight width constraints (e.g.
    // SliverToBoxAdapter → Padding) the Stack expands to full screen width
    // and the shimmer sweep escapes the pill (LIVE section bug, 2026-05-16).
    if (widget.trailing == null) {
      return Align(alignment: Alignment.centerLeft, child: stamp);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [stamp, widget.trailing!],
    );
  }
}
