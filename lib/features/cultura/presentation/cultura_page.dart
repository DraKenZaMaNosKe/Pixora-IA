import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/design/hud_tokens.dart';
import '../../wallpapers/data/models/wallpaper.dart';
import '../../wallpapers/presentation/pages/wallpaper_preview_page.dart';
import '../../../widgets/cached_wallpaper_image.dart';
import '../providers/cultura_provider.dart';

/// "Cultura" section — Museum Exhibit layout (concept #02, Eduardo
/// 2026-05-16). Each wallpaper is a museum specimen with brass corners,
/// measurement marks on the image, a placard with serial number + title in
/// Cinzel, italic type label and classification chips.
///
/// Initially curated to a single wallpaper (Mictlantecuhtli). New entries
/// get added by editing `_curatedCulturaIds` in the provider.
class CulturaPage extends ConsumerWidget {
  const CulturaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = context.hud;
    final async = ref.watch(culturaWallpapersProvider);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: h.isIosStyle
              ? const [Color(0xFFFAFAFA), Color(0xFFECECEC)]
              : const [Color(0xFF0A0A14), Color(0xFF14141F)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: h.accent, strokeWidth: 2),
          ),
          error: (e, _) => Center(
            child: Text('No se pudo cargar Cultura',
                style: TextStyle(color: h.textDim)),
          ),
          data: (items) =>
              items.isEmpty ? _Empty(h: h) : _MuseumList(items: items, h: h),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.h});
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.museum_outlined, size: 56, color: h.textDim),
          const SizedBox(height: 18),
          Text(
            'CÓDEX PIXORA',
            textAlign: TextAlign.center,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
              color: h.accent,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Cultura',
            textAlign: TextAlign.center,
            style: GoogleFonts.cinzel(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: h.text,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Próximamente — wallpapers con historia, mitología y datos curiosos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: h.textDim, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Museum Exhibit list — vertical scroll of exhibit cards.
class _MuseumList extends StatelessWidget {
  const _MuseumList({required this.items, required this.h});
  final List<Wallpaper> items;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 26, 12, 30),
      itemCount: items.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return _MuseumHeader(h: h);
        }
        final w = items[i - 1];
        return _ExhibitCard(
          wallpaper: w,
          h: h,
          index: i,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WallpaperPreviewPage(wallpaper: w),
            ),
          ),
        );
      },
    );
  }
}

/// Museum gallery header — eyebrow + Cinzel title + subtitle + thick rule.
class _MuseumHeader extends StatelessWidget {
  const _MuseumHeader({required this.h});
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    final isIos = h.isIosStyle;
    final ruleColor = isIos
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.18)
        : HudTokens.gold.withValues(alpha: 0.30);
    final eyebrowColor = isIos
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.5)
        : HudTokens.gold.withValues(alpha: 0.6);
    final titleColor = isIos ? const Color(0xFF1C1C1E) : HudTokens.goldBright;
    final subColor = h.textDim;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CODEX PIXORA · GALERÍA',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: eyebrowColor,
              letterSpacing: 3.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Cultura',
            style: GoogleFonts.cinzel(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: titleColor,
              letterSpacing: 1.4,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'MITOLOGÍA · HISTORIA · CIENCIA · WALLPAPERS VIVOS',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: subColor,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 2, color: ruleColor),
        ],
      ),
    );
  }
}

/// Single exhibit card — brass corners + specimen image with measurement
/// marks + placard meta (serial, title, type, classification).
class _ExhibitCard extends StatelessWidget {
  const _ExhibitCard({
    required this.wallpaper,
    required this.h,
    required this.index,
    required this.onTap,
  });
  final Wallpaper wallpaper;
  final HudTheme h;
  final int index;
  final VoidCallback onTap;

  String _romanNumeral(int n) {
    const romans = [
      '',
      'I',
      'II',
      'III',
      'IV',
      'V',
      'VI',
      'VII',
      'VIII',
      'IX',
      'X',
      'XI',
      'XII',
      'XIII',
      'XIV',
      'XV',
      'XVI',
      'XVII',
      'XVIII',
      'XIX',
      'XX',
    ];
    return n < romans.length ? romans[n] : n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = wallpaper.cultural;
    if (c == null) return const SizedBox.shrink();

    final isIos = h.isIosStyle;
    final brassColor = isIos ? const Color(0xFF0A84FF) : HudTokens.goldBright;
    final cardBg = isIos ? Colors.white : h.surface;
    final cardBorder = isIos
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.18)
        : HudTokens.gold.withValues(alpha: 0.25);
    final specimenBorder = isIos
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.15)
        : HudTokens.gold.withValues(alpha: 0.20);
    final serialColor = isIos ? const Color(0xFF0A84FF) : HudTokens.goldBright;
    final placardColor = isIos ? const Color(0xFF1C1C1E) : h.text;
    final chipBg = isIos
        ? const Color(0xFF0A84FF).withValues(alpha: 0.10)
        : HudTokens.gold.withValues(alpha: 0.10);
    final chipBorder = isIos
        ? const Color(0xFF0A84FF).withValues(alpha: 0.25)
        : HudTokens.gold.withValues(alpha: 0.30);
    final chipText = isIos ? const Color(0xFF0A84FF) : HudTokens.goldBright;

    final roman = _romanNumeral(index);
    final chapter = (c.chapter ?? '').trim();
    final locale = chapter.isEmpty ? null : chapter.split(' ').last;
    final serial =
        'EXHIBIT $roman${locale != null ? '.${locale.toUpperCase()}' : ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border.all(color: cardBorder, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Specimen — square thumbnail with measurement marks at bottom
                  SizedBox(
                    width: 76,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: specimenBorder, width: 1),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedWallpaperImage(
                              imageUrl: wallpaper.previewUrl,
                              fit: BoxFit.cover,
                            ),
                            // Measurement ruler (ticks at bottom)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 6,
                              child: CustomPaint(
                                painter: _RulerPainter(
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Meta — serial + placard title + type + classification
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          serial,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: serialColor,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _shortName(wallpaper.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cinzel(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: placardColor,
                            letterSpacing: 0.3,
                            height: 1.1,
                          ),
                        ),
                        if ((c.subtitle ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            c.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w400,
                              color: h.textDim,
                            ),
                          ),
                        ],
                        if ((c.lead ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            c.lead!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w400,
                              color: h.text.withValues(alpha: 0.78),
                              height: 1.45,
                            ),
                          ),
                        ],
                        if (c.facts.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: c.facts.take(3).map((f) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: chipBg,
                                  border:
                                      Border.all(color: chipBorder, width: 0.5),
                                ),
                                child: Text(
                                  f.value.toUpperCase(),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 6.5,
                                    fontWeight: FontWeight.w600,
                                    color: chipText,
                                    letterSpacing: 1.2,
                                    height: 1.0,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Brass corners — top-left + bottom-right L-shapes
            Positioned(
              top: -1,
              left: -1,
              child: _BrassCorner(color: brassColor, corner: _Corner.topLeft),
            ),
            Positioned(
              bottom: -1,
              right: -1,
              child:
                  _BrassCorner(color: brassColor, corner: _Corner.bottomRight),
            ),
          ],
        ),
      ),
    );
  }

  String _shortName(String full) {
    if (full.contains(' · ')) return full.split(' · ').first;
    return full;
  }
}

enum _Corner { topLeft, bottomRight }

class _BrassCorner extends StatelessWidget {
  const _BrassCorner({required this.color, required this.corner});
  final Color color;
  final _Corner corner;

  @override
  Widget build(BuildContext context) {
    final isTop = corner == _Corner.topLeft;
    return SizedBox(
      width: 14,
      height: 14,
      child: CustomPaint(
        painter: _CornerPainter(color: color, isTopLeft: isTop),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({required this.color, required this.isTopLeft});
  final Color color;
  final bool isTopLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (isTopLeft) {
      // Top edge + left edge
      canvas.drawLine(const Offset(0, 1), Offset(size.width, 1), paint);
      canvas.drawLine(const Offset(1, 0), Offset(1, size.height), paint);
    } else {
      // Bottom edge + right edge
      canvas.drawLine(Offset(0, size.height - 1),
          Offset(size.width, size.height - 1), paint);
      canvas.drawLine(Offset(size.width - 1, 0),
          Offset(size.width - 1, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isTopLeft != isTopLeft;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    // Draw 8 ticks evenly spaced
    final step = size.width / 8;
    for (var i = 0; i <= 8; i++) {
      final x = i * step;
      final h = i % 2 == 0 ? size.height : size.height * 0.55;
      canvas.drawLine(
          Offset(x, size.height - h), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.color != color;
}
