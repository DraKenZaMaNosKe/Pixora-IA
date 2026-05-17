import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/hud_tokens.dart';

/// Glassmorph Mini Pill — concept #01 LIVE tags (Eduardo 2026-05-16).
///
/// Frosted glass pill that inherits the LIVE hero's aesthetic. Used for both
/// the hero category tag (size `hero`) and the wallpaper card NEW badges
/// (size `mini`). Sits over any wallpaper without breaking readability.
///
/// * **iOS White**: translucent white tint + Apple Blue text + Apple Blue
///   hairline border.
/// * **Black & Gold**: translucent ink tint + gold-bright text + gold
///   hairline border.
class GlassmorphPill extends StatelessWidget {
  const GlassmorphPill({
    super.key,
    required this.label,
    this.size = GlassmorphPillSize.hero,
  });

  final String label;
  final GlassmorphPillSize size;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    const iosBlue = Color(0xFF0A84FF);

    final isMini = size == GlassmorphPillSize.mini;

    final blurSigma = isMini ? 10.0 : 14.0;
    final padding = isMini
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 9, vertical: 4);
    final fontSize = isMini ? 7.5 : 9.0;
    final letterSpacing = isMini ? 1.0 : 1.6;

    final Color bg;
    final Color textColor;
    final Color borderColor;
    final List<BoxShadow> shadows;
    if (isIos) {
      bg = Colors.white.withValues(alpha: 0.32);
      textColor = iosBlue;
      borderColor = iosBlue.withValues(alpha: isMini ? 0.50 : 0.55);
      shadows = isMini
          ? const []
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ];
    } else {
      bg = const Color(0xFF14141F).withValues(alpha: isMini ? 0.50 : 0.45);
      textColor = HudTokens.goldBright;
      borderColor = HudTokens.goldBright.withValues(alpha: 0.45);
      shadows = isMini
          ? const []
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ];
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.jetBrainsMono(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: letterSpacing,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum GlassmorphPillSize { hero, mini }
