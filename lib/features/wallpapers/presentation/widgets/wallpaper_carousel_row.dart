import 'package:flutter/material.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/services/mystery_slot.dart';
import '../../../../core/widgets/aurora_waves_loading.dart';
import '../../../../core/widgets/stamped_foil_header.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../data/models/wallpaper.dart';
import '../pages/wallpaper_preview_page.dart';
import '../../../../core/widgets/watch_card_pieces.dart';
import 'grid_card_animations.dart';
import 'mystery_card_widget.dart';
import 'native_ad_card.dart';
import 'wallpaper_card.dart'
    show PixoraCardKind, PixoraCardKindUI, PixoraCornerIcon;

/// One native ad card injected every [_kAdEvery] wallpaper cards in the
/// carousel. 6 is the industry sweet spot (similar to Instagram / Pinterest
/// feed density) — high enough revenue, low enough that the feed still feels
/// like content rather than ad reel.
const int _kAdEvery = 6;

class WallpaperCarouselRow extends StatefulWidget {
  const WallpaperCarouselRow({
    required this.title,
    required this.items,
    this.cardHeight = 260.0,
    this.cardWidth = 140.0,
    this.customHeader,
    super.key,
  });

  final String title;
  final List<Wallpaper> items;
  final double cardHeight;
  final double cardWidth;

  /// Header alternativo al StampedFoilHeader estándar. Usado por secciones
  /// con skin propio (ej. Amor → AmorLatidoHeader). Cuando es null se
  /// renderiza el foil header de siempre con [title].
  final Widget? customHeader;

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

    // Set proporcional de Mystery cards para ESTA fila (calculado una vez;
    // ~28% del pool elegible con mínimo 1). checkFavorites: true → mismo
    // modelo Wallpaper que sí vive en la box `favorites`.
    final mysterySet = pickMysteryIds(
      widget.items.map((w) => w.id),
      checkFavorites: true,
    );

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
                // Stamped Foil header (concept #01, Eduardo 2026-05-16) —
                // metallic stamp with hairline outline + glyph + 4.5s shimmer.
                // iOS: dark text + Apple Blue glyph. B&G: gold foil + gold star.
                // Secciones con skin propio pasan customHeader (ej. Amor).
                widget.customHeader ??
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StampedFoilHeader(label: widget.title),
                      ),
                    ),
                // Horizontal list with scroll-driven effects
                SizedBox(
                  height: widget.cardHeight,
                  child: ListView.builder(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    // Expand by one slot for every block of [_kAdEvery] cards.
                    // Layout: [W W W W W W AD W W W W W W AD W W ...]
                    itemCount: widget.items.length +
                        (widget.items.length ~/ _kAdEvery),
                    // 2026-06-24 — bajado 150 → 80 después de OOM Samsung A15.
                    // Solo cachea 1 card off-screen a cada lado (cards son
                    // ~160 logical wide), purga el resto inmediato.
                    // ignore: deprecated_member_use
                    cacheExtent: 80,
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

                      // Every (_kAdEvery + 1)th slot is an ad — index 6, 13,
                      // 20, ... in 0-based. The wallpaper index strips out
                      // the ad slots: wpIdx = index - (index ~/ (_kAdEvery+1))
                      const stride = _kAdEvery + 1;
                      final isAd = (index + 1) % stride == 0;
                      final Widget child;
                      if (isAd) {
                        child = NativeAdCard(height: widget.cardHeight);
                      } else {
                        final wpIdx = index - (index ~/ stride);
                        if (wpIdx >= widget.items.length) {
                          return const SizedBox.shrink();
                        }
                        final wp = widget.items[wpIdx];
                        final card = _ParallaxCarouselCard(
                          wallpaper: wp,
                          width: widget.cardWidth,
                          height: widget.cardHeight,
                          scrollController: _scrollController,
                          index: wpIdx,
                        );
                        // 2026-06-24 — Mystery Card · 2026-07-05 selección
                        // proporcional (ver mystery_slot.dart). Excluye
                        // favoritos+installed; 1 de cada 5 reveals → Tesoro
                        // Bonus (ad interstitial + diamantes via AdService).
                        if (mysterySet.contains(wp.id)) {
                          child = SizedBox(
                            width: widget.cardWidth,
                            height: widget.cardHeight,
                            child: MysteryCardWidget(
                              wallpaperId: wp.id,
                              revealedChild: card,
                            ),
                          );
                        } else {
                          child = card;
                        }
                      }
                      return Opacity(
                        opacity: cardFade,
                        child: Transform.scale(
                          scale: cardScale,
                          child: child,
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

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    if (h.isIosStyle) return _buildIosCard(context);
    return _buildTicketCard(context);
  }

  PixoraCardKind get _kind => wallpaper.isPanoramic
      ? PixoraCardKind.panoramic
      : PixoraCardKind.staticImage;

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
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: h.bg,
          borderRadius: BorderRadius.circular(14),
          // Propuesta 3 — SOLO contorno 2px sólido (Eduardo 2026-06-20:
          // sin halo de color porque cuando varias cards del mismo
          // kind quedan adyacentes el blur se acumulaba y parecía un
          // relleno amarillo/rosa detrás del grid). La sombra negra
          // se queda solo para dar profundidad neutra.
          border: Border.all(color: _kind.color, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 2026-06-20 — quitado el parallax (Transform.scale +
                    // Transform.translate) a pedido de Eduardo: con
                    // imágenes panorámicas se veían franjas negras y la
                    // imagen "se salía del centro". Sin parallax el cover
                    // simple llena el card limpiamente para todo tipo.
                    SizedBox.expand(
                      child: CachedWallpaperImage(
                        imageUrl: wallpaper.previewUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (wallpaper.badge != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: WatchCartouchePill(
                          label: wallpaper.badge!.toUpperCase(),
                        ),
                      ),
                    // Activity Rings bottom-centered (concept #04)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 8,
                      child: Center(
                        child: ActivityRings(wallpaperId: wallpaper.id),
                      ),
                    ),
                    // 2026-06-13 — Realtime like/view animations overlay.
                    Positioned.fill(
                      child: GridCardAnimationOverlay(
                        wallpaperId: wallpaper.id,
                      ),
                    ),
                    // Propuesta 3 — corner icon kind arriba-derecha
                    // (zona limpia: no choca con ActivityRings center-
                    // bottom ni con badge top-left).
                    Positioned(
                      right: 8,
                      top: 8,
                      child: PixoraCornerIcon(kind: _kind),
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
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: context.hud.surface,
          borderRadius: BorderRadius.circular(14),
          // Propuesta 3 — SOLO contorno limpio (Eduardo 2026-06-20):
          // border 2px sólido del kind, sin halo de color porque cuando
          // varias cards adyacentes son del mismo tipo el blur se acumula
          // y parece relleno amarillo/rosa detrás del grid.
          border: Border.all(color: _kind.color, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        // Pure-image (sin header ADMIT, sin dashed perforation, sin
        // bottom stub). Image clipped al border radius para que rellene
        // el card por completo y se vea centrada como en el mockup.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Parallax quitado 2026-06-20 (Eduardo) — imagen centrada
              // y limpia, sin movimiento al scroll.
              SizedBox.expand(
                child: CachedWallpaperImage(
                  imageUrl: wallpaper.previewUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: ActivityRings(wallpaperId: wallpaper.id),
                ),
              ),
              Positioned.fill(
                child: GridCardAnimationOverlay(wallpaperId: wallpaper.id),
              ),
              if (wallpaper.badge != null)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: context.hud.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      wallpaper.badge!.toUpperCase(),
                      style: HudTokens.mono(
                        size: 8,
                        weight: FontWeight.w700,
                        color: Colors.black,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                ),
              // Corner icon Propuesta 3 — arriba-derecha (zona libre
              // en el ticket variant: no choca con ActivityRings
              // center-bottom ni con badge top-left).
              Positioned(
                right: 8,
                top: 8,
                child: PixoraCornerIcon(kind: _kind),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
