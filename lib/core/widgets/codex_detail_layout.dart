import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/hud_tokens.dart';
import '../models/cultural_content.dart';

/// CULTURA detail layout — Cabinet of Curiosities (Wunderkammer) concept #04
/// picked by Eduardo on 2026-05-16. Replaces the previous "Códice Mexica"
/// greca layout with a 19th-century natural-history cabinet aesthetic:
/// gilded brass frame with corner medallions, latin specimen label, two
/// column body in Cormorant Garamond, monospace catalog table, rotated
/// provenance tag, ornamented Ofrenda panel, and a brass-stamped CTA.
///
/// One widget renders both iOS (light Victorian) and B&G (dark mahogany).
class CodexDetailLayout extends StatelessWidget {
  const CodexDetailLayout({
    super.key,
    required this.heroImage,
    required this.title,
    required this.cultural,
    required this.applyCta,
    required this.statusBar,
  });

  /// The wallpaper preview painted inside the gilded frame.
  final Widget heroImage;

  /// Wallpaper name (e.g. "Mictlantecuhtli · Señor del Mictlán"). Used to
  /// derive the cabinet specimen title.
  final String title;

  /// Editorial content from the catalog. Optional fields render conditionally.
  final CulturalContent cultural;

  /// CTA widget — the page provides the apply button. The layout wraps it in
  /// a brass-stamped container, but the inner button keeps its own logic.
  final Widget applyCta;

  /// Top bar / status overlay rendered above the scroll.
  final Widget statusBar;

  @override
  Widget build(BuildContext context) {
    final hud = context.hud;
    final isIos = hud.isIosStyle;

    // ── Cabinet palette (matches concept #04) ───────────────────────
    final bgGradient = isIos
        ? const [Color(0xFFF6EFDC), Color(0xFFEAD8B6)]
        : const [Color(0xFF1C0E08), Color(0xFF0E0805)];
    final parchInk = isIos ? const Color(0xFF3A2818) : const Color(0xFFE6D8B8);
    final filigree = isIos ? const Color(0xFF8E7B4E) : HudTokens.goldDeep;
    final brassBright = isIos ? const Color(0xFFD6AD6A) : HudTokens.goldBright;
    final brassDeep = isIos ? const Color(0xFFB88C4A) : HudTokens.gold;
    final medallionInner =
        isIos ? const Color(0xFFF0C474) : HudTokens.goldBright;
    final medallionOuter = isIos ? const Color(0xFF8C6224) : HudTokens.goldDeep;

    return Stack(
      children: [
        // ── Cosmic / parchment background ──────────────────────────
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: bgGradient,
              ),
            ),
          ),
        ),
        // ── Wood-grain striations overlay ──────────────────────────
        const Positioned.fill(
          child: IgnorePointer(child: _WoodGrainOverlay()),
        ),

        // ── Scrollable content ─────────────────────────────────────
        Positioned.fill(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 56, bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero inside gilded frame
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _GildedFrame(
                      child: heroImage,
                      brassBright: brassBright,
                      brassDeep: brassDeep,
                      medallionInner: medallionInner,
                      medallionOuter: medallionOuter,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Specimen label — serial, title, latin
                  _SpecimenLabel(
                    serial: _serial(),
                    title: _shortName(title),
                    latin: cultural.subtitle ?? '',
                    pronunciation: cultural.pronunciation ?? '',
                    parchInk: parchInk,
                    filigree: filigree,
                    accent: brassBright,
                    isIos: isIos,
                  ),
                  const SizedBox(height: 14),

                  // Two-column body (if lead present)
                  if ((cultural.lead ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _TwoColumnBody(
                        text: cultural.lead!,
                        color: parchInk,
                        rule: filigree,
                      ),
                    ),
                  const SizedBox(height: 14),

                  // Catalog table for facts
                  if (cultural.facts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _CatalogTable(
                        facts: cultural.facts,
                        keyColor: filigree,
                        valueColor: parchInk,
                        rule: filigree.withValues(alpha: 0.20),
                      ),
                    ),
                  const SizedBox(height: 14),

                  // Ofrenda panel
                  if (cultural.ofrenda != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _OfrendaPanel(
                        ofrenda: cultural.ofrenda!,
                        accent: brassBright,
                        parchInk: parchInk,
                        filigree: filigree,
                        isIos: isIos,
                      ),
                    ),
                  const SizedBox(height: 18),

                  // Brass-stamped CTA wrapper around the page's apply button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _BrassStampedCtaWrap(
                      brassBright: brassBright,
                      brassDeep: brassDeep,
                      child: applyCta,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Top status bar (back, lot, fav) ─────────────────────────
        Positioned(top: 0, left: 0, right: 0, child: statusBar),

        // ── Provenance tag floating on the right side ───────────────
        Positioned(
          top: 380,
          right: 8,
          child: _ProvenanceTag(
            year: _provYear(),
            label: cultural.chapter ?? 'MICTLÁN',
            accent: brassBright,
            filigree: filigree,
            parchInk: parchInk,
            isIos: isIos,
          ),
        ),
      ],
    );
  }

  String _shortName(String s) {
    if (s.contains(' · ')) return s.split(' · ').first.toUpperCase();
    return s.toUpperCase();
  }

  String _serial() {
    // EXHIBIT-style serial derived from the title
    final base = title.contains(' · ') ? title.split(' · ').first : title;
    final letters = base
        .replaceAll(RegExp(r'[^A-Za-z]'), '')
        .toUpperCase()
        .padRight(3, 'X')
        .substring(0, 3);
    final num = base.hashCode.abs() % 1000;
    return 'SPECIMEN · $letters-${num.toString().padLeft(3, '0')}';
  }

  String _provYear() {
    // Roman year-ish marker pulled from chapter; falls back to MCMXCIX
    final ch = (cultural.chapter ?? '').toUpperCase();
    if (ch.contains('IX')) return 'MCMLXXII';
    if (ch.contains('VIII')) return 'MCMLXIV';
    if (ch.contains('VII')) return 'MCMLVII';
    if (ch.contains('VI')) return 'MCMLI';
    if (ch.contains('V')) return 'MCMXLV';
    return 'MCMXCIX';
  }
}

// ─────────────────────────────────────────────────────────────────────
// Wood-grain striations overlay
// ─────────────────────────────────────────────────────────────────────
class _WoodGrainOverlay extends StatelessWidget {
  const _WoodGrainOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WoodGrainPainter(isIos: context.hud.isIosStyle),
    );
  }
}

class _WoodGrainPainter extends CustomPainter {
  _WoodGrainPainter({required this.isIos});
  final bool isIos;

  @override
  void paint(Canvas canvas, Size size) {
    final fineColor = isIos
        ? const Color(0xFF3A2818).withValues(alpha: 0.05)
        : HudTokens.gold.withValues(alpha: 0.05);
    final coarseColor = isIos
        ? const Color(0xFF3A2818).withValues(alpha: 0.04)
        : HudTokens.gold.withValues(alpha: 0.04);
    final fine = Paint()
      ..color = fineColor
      ..strokeWidth = 1;
    final coarse = Paint()
      ..color = coarseColor
      ..strokeWidth = 1;
    for (var y = 22.0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), fine);
    }
    for (var y = 38.0; y < size.height; y += 17) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), coarse);
    }
  }

  @override
  bool shouldRepaint(covariant _WoodGrainPainter old) => old.isIos != isIos;
}

// ─────────────────────────────────────────────────────────────────────
// Gilded frame with 4 corner medallions
// ─────────────────────────────────────────────────────────────────────
class _GildedFrame extends StatelessWidget {
  const _GildedFrame({
    required this.child,
    required this.brassBright,
    required this.brassDeep,
    required this.medallionInner,
    required this.medallionOuter,
  });
  final Widget child;
  final Color brassBright;
  final Color brassDeep;
  final Color medallionInner;
  final Color medallionOuter;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1 / 1.1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Brass gradient frame
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [brassBright, brassDeep, brassBright],
                stops: const [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.40),
                  width: 1,
                ),
              ),
              child: ClipRect(child: child),
            ),
          ),
          // 4 corner medallions
          Positioned(
            top: -4,
            left: -4,
            child: _Medallion(
              inner: medallionInner,
              outer: medallionOuter,
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: _Medallion(
              inner: medallionInner,
              outer: medallionOuter,
            ),
          ),
          Positioned(
            bottom: -4,
            left: -4,
            child: _Medallion(
              inner: medallionInner,
              outer: medallionOuter,
            ),
          ),
          Positioned(
            bottom: -4,
            right: -4,
            child: _Medallion(
              inner: medallionInner,
              outer: medallionOuter,
            ),
          ),
        ],
      ),
    );
  }
}

class _Medallion extends StatelessWidget {
  const _Medallion({required this.inner, required this.outer});
  final Color inner;
  final Color outer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [inner, outer],
          stops: const [0.3, 0.9],
        ),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '+',
        style: GoogleFonts.cinzel(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.6),
          height: 1.0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Specimen label — serial, Cinzel title, italic latin subtitle
// ─────────────────────────────────────────────────────────────────────
class _SpecimenLabel extends StatelessWidget {
  const _SpecimenLabel({
    required this.serial,
    required this.title,
    required this.latin,
    required this.pronunciation,
    required this.parchInk,
    required this.filigree,
    required this.accent,
    required this.isIos,
  });
  final String serial;
  final String title;
  final String latin;
  final String pronunciation;
  final Color parchInk;
  final Color filigree;
  final Color accent;
  final bool isIos;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: filigree.withValues(alpha: 0.30), width: 1),
          bottom: BorderSide(color: filigree.withValues(alpha: 0.30), width: 1),
        ),
      ),
      child: Column(
        children: [
          Text(
            serial,
            textAlign: TextAlign.center,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 7,
              fontWeight: FontWeight.w700,
              letterSpacing: 3.0,
              color: filigree,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cinzel(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: isIos ? parchInk : accent,
              height: 1.1,
            ),
          ),
          if (latin.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              latin,
              textAlign: TextAlign.center,
              style: GoogleFonts.cormorantGaramond(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w400,
                color: parchInk.withValues(alpha: 0.75),
                height: 1.2,
              ),
            ),
          ],
          if (pronunciation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              pronunciation,
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: parchInk.withValues(alpha: 0.55),
                letterSpacing: 1.0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Two-column manuscript body in Cormorant Garamond
// ─────────────────────────────────────────────────────────────────────
class _TwoColumnBody extends StatelessWidget {
  const _TwoColumnBody({
    required this.text,
    required this.color,
    required this.rule,
  });
  final String text;
  final Color color;
  final Color rule;

  @override
  Widget build(BuildContext context) {
    // Split the text in two roughly equal halves at the nearest sentence break.
    final mid = text.length ~/ 2;
    var split = mid;
    final breakIdx = text.lastIndexOf('. ', mid + 30);
    if (breakIdx > mid - 60 && breakIdx < text.length - 10) {
      split = breakIdx + 2;
    }
    final col1 = text.substring(0, split).trim();
    final col2 = text.substring(split).trim();

    final style = GoogleFonts.cormorantGaramond(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: color,
      height: 1.5,
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: Text(col1, style: style)),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: rule.withValues(alpha: 0.30),
          ),
          Expanded(child: Text(col2, style: style)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Old-world catalog table — mono key/value rows with dashed bottom borders
// ─────────────────────────────────────────────────────────────────────
class _CatalogTable extends StatelessWidget {
  const _CatalogTable({
    required this.facts,
    required this.keyColor,
    required this.valueColor,
    required this.rule,
  });
  final List<CulturalFact> facts;
  final Color keyColor;
  final Color valueColor;
  final Color rule;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: facts.map((f) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: rule, width: 1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  f.key.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: keyColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  f.value,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: valueColor,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Rotated provenance tag
// ─────────────────────────────────────────────────────────────────────
class _ProvenanceTag extends StatelessWidget {
  const _ProvenanceTag({
    required this.year,
    required this.label,
    required this.accent,
    required this.filigree,
    required this.parchInk,
    required this.isIos,
  });
  final String year;
  final String label;
  final Color accent;
  final Color filigree;
  final Color parchInk;
  final bool isIos;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.14, // ~8deg
      child: Container(
        width: 82,
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: isIos
              ? const Color(0xFFEAD8B6).withValues(alpha: 0.85)
              : HudTokens.gold.withValues(alpha: 0.10),
          border: Border.all(color: filigree, width: 1),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Punched hole
            Positioned(
              left: -10,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filigree.withValues(alpha: 0.7),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.4),
                        blurRadius: 0,
                        spreadRadius: -1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PROV.',
                  style: GoogleFonts.cinzel(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 9,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: parchInk,
                    height: 1.1,
                  ),
                ),
                Text(
                  year,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 8,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w400,
                    color: parchInk.withValues(alpha: 0.75),
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Ofrenda panel — bordered with Cinzel header
// ─────────────────────────────────────────────────────────────────────
class _OfrendaPanel extends StatelessWidget {
  const _OfrendaPanel({
    required this.ofrenda,
    required this.accent,
    required this.parchInk,
    required this.filigree,
    required this.isIos,
  });
  final CulturalOfrenda ofrenda;
  final Color accent;
  final Color parchInk;
  final Color filigree;
  final bool isIos;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: isIos
            ? Colors.white.withValues(alpha: 0.45)
            : HudTokens.gold.withValues(alpha: 0.05),
        border: Border.all(color: filigree, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ofrenda.label.toUpperCase(),
            style: GoogleFonts.cinzel(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 3.0,
              color: filigree,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ofrenda.text,
            style: GoogleFonts.cormorantGaramond(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w400,
              color: parchInk,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Brass-stamped CTA wrapper
// ─────────────────────────────────────────────────────────────────────
class _BrassStampedCtaWrap extends StatelessWidget {
  const _BrassStampedCtaWrap({
    required this.child,
    required this.brassBright,
    required this.brassDeep,
  });
  final Widget child;
  final Color brassBright;
  final Color brassDeep;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [brassBright, brassDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: brassBright.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: child,
      ),
    );
  }
}
