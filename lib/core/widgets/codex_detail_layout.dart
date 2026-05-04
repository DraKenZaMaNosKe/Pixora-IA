import 'package:flutter/material.dart';
import '../design/hud_tokens.dart';
import '../models/cultural_content.dart';

/// Editorial "Códice Mexica" layout for cultural/mythology wallpapers.
///
/// One widget renders both Black & Gold and iOS White themes, switching
/// colors via `context.hud`. Layout, typography, and decorative elements
/// (greca, glyph, drop cap) are identical across themes; only colors and
/// surface treatments change.
class CodexDetailLayout extends StatelessWidget {
  const CodexDetailLayout({
    super.key,
    required this.heroImage,
    required this.title,
    required this.cultural,
    required this.applyCta,
    required this.statusBar,
  });

  /// The wallpaper preview image painted as the hero (340 dp tall).
  final Widget heroImage;

  /// Wallpaper name (e.g. "Mictlantecuhtli · Señor del Mictlan").
  final String title;

  /// Editorial content from the catalog. Optional fields render conditionally.
  final CulturalContent cultural;

  /// CTA widget (the "Set as Live Wallpaper" button + ad/credit row).
  final Widget applyCta;

  /// Top app bar / status overlay rendered above the scroll.
  final Widget statusBar;

  static const double _heroHeight = 340;

  @override
  Widget build(BuildContext context) {
    final hud = context.hud;
    final isIos = hud.isIosStyle;

    // Color palette — derived from theme so it matches the rest of the app.
    final bg = hud.bg;
    final text = hud.text;
    final dim = hud.textDim;
    final accent = hud.accent;
    final divider = isIos
        ? const Color(0xFFC0B09A) // warmer beige for iOS
        : const Color(0xFF44351A); // dark brown for B&G

    return Stack(
      children: [
        // Scrollable content
        Positioned.fill(
          child: Container(
            color: bg,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero image with bottom-fade into bg
                  SizedBox(
                    height: _heroHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        heroImage,
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.center,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, bg],
                              stops: const [0.5, 1.0],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Decorative greca (mesoamerican border pattern)
                  CustomPaint(
                    size: const Size(double.infinity, 14),
                    painter: _GrecaPainter(color: accent),
                  ),

                  // Body
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 24, 26, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((cultural.chapter ?? '').isNotEmpty)
                          Text(
                            '— ${cultural.chapter} —',
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2.5,
                              color: accent,
                            ),
                          ),
                        const SizedBox(height: 8),

                        // Main title (the wallpaper name, split smartly)
                        Text(
                          _splitTitle(title),
                          style: TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 36,
                            fontWeight: FontWeight.w400,
                            height: 1.05,
                            color: text,
                          ),
                        ),
                        if ((cultural.subtitle ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            cultural.subtitle!,
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontStyle: FontStyle.italic,
                              fontSize: 22,
                              fontWeight: FontWeight.w400,
                              color: accent,
                              height: 1.05,
                            ),
                          ),
                        ],

                        if ((cultural.pronunciation ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            cultural.pronunciation!,
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                              color: dim,
                            ),
                          ),
                        ],

                        // Lead paragraph with drop cap
                        if ((cultural.lead ?? '').isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _LeadParagraph(
                            text: cultural.lead!,
                            textColor: text,
                            accent: accent,
                          ),
                        ],

                        // Facts grid 2-col
                        if (cultural.facts.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _FactsGrid(
                            facts: cultural.facts,
                            keyColor: dim,
                            valueColor: text,
                            divider: divider,
                          ),
                        ],

                        // Ofrenda card
                        if (cultural.ofrenda != null) ...[
                          const SizedBox(height: 22),
                          _OfrendaCard(
                            ofrenda: cultural.ofrenda!,
                            accent: accent,
                            text: text,
                          ),
                        ],

                        const SizedBox(height: 24),

                        // CTA — uses the Apply button passed in (preserves all
                        // ad / credit / loading logic from the page).
                        applyCta,

                        const SizedBox(height: 16),

                        // Closing greca
                        CustomPaint(
                          size: const Size(double.infinity, 14),
                          painter: _GrecaPainter(color: accent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Top status bar (back button + name) painted on top of the hero.
        Positioned(top: 0, left: 0, right: 0, child: statusBar),
      ],
    );
  }

  /// Split "Mictlantecuhtli · Señor del Mictlan" into two lines at the
  /// middle separator so the long names don't overflow on small phones.
  String _splitTitle(String s) {
    if (s.contains(' · ')) return s.replaceFirst(' · ', '\n');
    return s;
  }
}

/// Drop-cap intro paragraph in italic Fraunces.
class _LeadParagraph extends StatelessWidget {
  const _LeadParagraph({
    required this.text,
    required this.textColor,
    required this.accent,
  });
  final String text;
  // ignore: non_constant_identifier_names
  final Color textColor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final words = text.trim().split(' ');
    if (words.isEmpty) return const SizedBox.shrink();
    final first = words.first;
    final rest = words.sublist(1).join(' ');
    final firstLetter = first.isNotEmpty ? first[0] : '';
    final firstRest = first.length > 1 ? first.substring(1) : '';

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
            fontSize: 15,
            height: 1.55,
            color: textColor.withValues(alpha: 0.85),
          ),
          children: [
            TextSpan(
              text: firstLetter,
              style: TextStyle(
                fontSize: 50,
                height: 0.85,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.normal,
                color: accent,
              ),
            ),
            TextSpan(text: '$firstRest $rest'),
          ],
        ),
      ),
    );
  }
}

/// 2-column facts grid with dashed top borders, codex-style.
class _FactsGrid extends StatelessWidget {
  const _FactsGrid({
    required this.facts,
    required this.keyColor,
    required this.valueColor,
    required this.divider,
  });

  final List<CulturalFact> facts;
  final Color keyColor;
  final Color valueColor;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    // Pair facts into rows of 2
    final rows = <List<CulturalFact>>[];
    for (int i = 0; i < facts.length; i += 2) {
      rows.add(facts.sublist(i, (i + 2).clamp(0, facts.length)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FactCell(
                    fact: row[0],
                    keyColor: keyColor,
                    valueColor: valueColor,
                    divider: divider),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: row.length > 1
                    ? _FactCell(
                        fact: row[1],
                        keyColor: keyColor,
                        valueColor: valueColor,
                        divider: divider)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _FactCell extends StatelessWidget {
  const _FactCell({
    required this.fact,
    required this.keyColor,
    required this.valueColor,
    required this.divider,
  });
  final CulturalFact fact;
  final Color keyColor;
  final Color valueColor;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: divider, style: BorderStyle.solid, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fact.key.toUpperCase(),
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9,
              fontWeight: FontWeight.w400,
              letterSpacing: 2.5,
              color: keyColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fact.value,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 14,
              height: 1.3,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfrendaCard extends StatelessWidget {
  const _OfrendaCard({
    required this.ofrenda,
    required this.accent,
    required this.text,
  });
  final CulturalOfrenda ofrenda;
  final Color accent;
  final Color text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ofrenda.label,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ofrenda.text,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 13,
              height: 1.5,
              color: text.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stepped meander pattern (greca) inspired by mesoamerican textiles.
class _GrecaPainter extends CustomPainter {
  _GrecaPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const step = 26.0;
    final h = size.height;
    final centerY = h / 2;

    final path = Path();
    double x = 0;
    while (x < size.width) {
      // Stepped square pattern — outline of a "greca"
      path.moveTo(x, centerY + 3);
      path.lineTo(x + 8, centerY + 3);
      path.lineTo(x + 8, centerY - 3);
      path.lineTo(x + 16, centerY - 3);
      path.lineTo(x + 16, centerY + 3);
      x += step;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GrecaPainter old) => old.color != color;
}
