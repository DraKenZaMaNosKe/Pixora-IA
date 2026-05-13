import 'package:flutter/material.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/widgets/aurora_waves_loading.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../data/models/wallpaper.dart';
import '../pages/wallpaper_preview_page.dart';
import 'wallpaper_stats_bar.dart';
import 'package:google_fonts/google_fonts.dart';

class WallpaperCarouselRow extends StatefulWidget {
  const WallpaperCarouselRow({
    required this.title,
    required this.items,
    this.cardHeight = 260.0,
    this.cardWidth = 140.0,
    super.key,
  });

  final String title;
  final List<Wallpaper> items;
  final double cardHeight;
  final double cardWidth;

  @override
  State<WallpaperCarouselRow> createState() => _WallpaperCarouselRowState();
}

class _WallpaperCarouselRowState extends State<WallpaperCarouselRow>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _entranceController;
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // Trigger entrance animation after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasAnimated) {
        _hasAnimated = true;
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _entranceController,
      builder: (_, __) {
        final slideValue =
            Curves.easeOutCubic.transform(_entranceController.value);
        final fadeValue = Curves.easeOut.transform(_entranceController.value);

        return Opacity(
          opacity: fadeValue,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - slideValue)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section header — kept (and themed) so users navigate
                // by category, but kept ELEGANT so it never competes with
                // the imagery. Italic serif on top, gold underline accent.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 4,
                        height: 22,
                        decoration: BoxDecoration(
                          color: context.hud.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.title,
                        style: GoogleFonts.fraunces(
                          fontSize: 22,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                          color: context.hud.text,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: context.hud.accent.withValues(alpha: 0.25),
                        ),
                      ),
                    ],
                  ),
                ),
                // Horizontal list with scroll-driven effects
                SizedBox(
                  height: widget.cardHeight,
                  child: ListView.builder(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: widget.items.length,
                    cacheExtent: 150,
                    // Aggressive memory: drop offscreen cards from the
                    // element tree as soon as they scroll out (default
                    // `true` would keep them mounted forever, accumulating
                    // image bitmaps + Skia GPU resources).
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    itemBuilder: (context, index) {
                      final stagger = (index * 0.08).clamp(0.0, 0.6);
                      final cardProgress =
                          ((_entranceController.value - stagger) /
                                  (1.0 - stagger))
                              .clamp(0.0, 1.0);
                      final cardFade = Curves.easeOut.transform(cardProgress);
                      final cardScale = 0.85 +
                          0.15 * Curves.easeOutBack.transform(cardProgress);

                      final wp = widget.items[index];
                      return Opacity(
                        opacity: cardFade,
                        child: Transform.scale(
                          scale: cardScale,
                          child: _ParallaxCarouselCard(
                            wallpaper: wp,
                            width: widget.cardWidth,
                            height: widget.cardHeight,
                            scrollController: _scrollController,
                            index: index,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ParallaxCarouselCard extends StatelessWidget {
  const _ParallaxCarouselCard({
    required this.wallpaper,
    required this.width,
    required this.height,
    required this.scrollController,
    required this.index,
  });

  final Wallpaper wallpaper;
  final double width;
  final double height;
  final ScrollController scrollController;
  final int index;

  double _getParallaxOffset(BuildContext context) {
    if (!scrollController.hasClients) return 0.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final scrollOffset = scrollController.offset;
    final cardPosition = index * (width + 12) + 12 - scrollOffset;
    final center = screenWidth / 2;
    final cardCenter = cardPosition + width / 2;
    final distFromCenter = (cardCenter - center) / center;
    return distFromCenter * -15.0; // subtle parallax
  }

  String get _lotNumber {
    final n = wallpaper.id.hashCode.abs() % 1000;
    return n.toString().padLeft(3, '0');
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    if (h.isIosStyle) return _buildIosCard(context);
    return _buildTicketCard(context);
  }

  Widget _buildIosCard(BuildContext context) {
    final h = context.hud;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WallpaperPreviewPage(wallpaper: wallpaper),
        ),
      ),
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: h.bg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedBuilder(
                      animation: scrollController,
                      builder: (ctx, child) => Transform.translate(
                        offset: Offset(_getParallaxOffset(ctx), 0),
                        child: child,
                      ),
                      child: Transform.scale(
                        scale: 1.1,
                        child: CachedWallpaperImage(
                            imageUrl: wallpaper.previewUrl),
                      ),
                    ),
                    if (wallpaper.badge != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: h.accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            wallpaper.badge!.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    // Stats bar (likes/views/downloads) top-right
                    Positioned(
                      top: 8,
                      right: 8,
                      child: WallpaperStatsBar(
                        wallpaperId: wallpaper.id,
                        glowColor: h.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Title + category hidden — distraction-free image-only browsing.
          ],
        ),
      ),
    );
  }

  Widget _buildTicketCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WallpaperPreviewPage(wallpaper: wallpaper),
        ),
      ),
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: context.hud.surface,
          border: Border.all(
            color: context.hud.accent.withValues(alpha: 0.55),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top stub header ─────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
              child: Row(
                children: [
                  Text('ADMIT',
                      style: HudTokens.mono(
                          size: 7.5,
                          weight: FontWeight.w700,
                          color: context.hud.accent,
                          letterSpacing: 0.3)),
                  const Spacer(),
                  Text('N° $_lotNumber',
                      style: HudTokens.mono(
                          size: 7.5,
                          weight: FontWeight.w700,
                          color: context.hud.accent,
                          letterSpacing: 0.3)),
                ],
              ),
            ),
            // ── Image panel ─────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Parallax listens to scrollController so Transform.translate
                      // rebuilds on scroll, but the expensive image below does not.
                      AnimatedBuilder(
                        animation: scrollController,
                        builder: (ctx, child) => Transform.translate(
                          offset: Offset(_getParallaxOffset(ctx), 0),
                          child: child,
                        ),
                        child: Transform.scale(
                          scale: 1.1,
                          child: CachedWallpaperImage(
                              imageUrl: wallpaper.previewUrl),
                        ),
                      ),
                      // Stats bar top-right
                      Positioned(
                        top: 4,
                        right: 4,
                        child: WallpaperStatsBar(
                          wallpaperId: wallpaper.id,
                          glowColor: context.hud.accent,
                        ),
                      ),
                      // Badge top-left
                      if (wallpaper.badge != null)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            color: context.hud.accent,
                            child: Text(
                              wallpaper.badge!.toUpperCase(),
                              style: HudTokens.mono(
                                  size: 8,
                                  weight: FontWeight.w700,
                                  color: Colors.black,
                                  letterSpacing: 0.15),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // ── Dashed gold perforation ─────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: CustomPaint(
                size: const Size(double.infinity, 1),
                painter: _CarouselDashPainter(color: context.hud.accent),
              ),
            ),
            // Bottom stub (title + serial + category) hidden — pure-image
            // browsing per user request.
          ],
        ),
      ),
    );
  }
}

/// Dashed gold line for the torn-ticket perforation.
class _CarouselDashPainter extends CustomPainter {
  const _CarouselDashPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
  bool shouldRepaint(covariant _CarouselDashPainter old) => old.color != color;
}

/// Catalog loading skeleton — Faithful Mirror (concept #01, 2026-05-13).
///
/// Reemplaza el shimmer genérico Material con tarjetas tipo wallpaper que
/// contienen el mismo Aurora Waves que se ve dentro de los cards reales.
/// El título es una barra sólida (no shimmer). El usuario percibe el layout
/// real apareciendo, sin layout-shift cuando llegue la data.
class CarouselRowShimmer extends StatelessWidget {
  const CarouselRowShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title placeholder — solid gray bar, no animation
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Container(
            width: 120,
            height: 18,
            decoration: BoxDecoration(
              color: h.surface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        // Card placeholders — same dimensions as real carousel cards, each
        // hosting an AuroraWavesLoading inside its rounded rect.
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: 4,
            itemBuilder: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Container(
                width: 130,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: h.divider.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: const AuroraWavesLoading(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
