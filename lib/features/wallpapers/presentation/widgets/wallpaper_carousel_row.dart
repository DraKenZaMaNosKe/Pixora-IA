import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../data/models/wallpaper.dart';
import '../pages/wallpaper_preview_page.dart';
import 'wallpaper_stats_bar.dart';

class WallpaperCarouselRow extends StatefulWidget {
  const WallpaperCarouselRow({
    required this.title,
    required this.items,
    this.cardHeight = 200.0,
    this.cardWidth = 130.0,
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
        final slideValue = Curves.easeOutCubic.transform(_entranceController.value);
        final fadeValue = Curves.easeOut.transform(_entranceController.value);

        return Opacity(
          opacity: fadeValue,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - slideValue)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Horizontal list with scroll-driven effects
                SizedBox(
                  height: widget.cardHeight,
                  child: AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, _) => ListView.builder(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: widget.items.length,
                      cacheExtent: 500,
                      itemBuilder: (context, index) {
                        // Staggered entrance per card
                        final stagger = (index * 0.08).clamp(0.0, 0.6);
                        final cardProgress = ((_entranceController.value - stagger) / (1.0 - stagger)).clamp(0.0, 1.0);
                        final cardFade = Curves.easeOut.transform(cardProgress);
                        final cardScale = 0.85 + 0.15 * Curves.easeOutBack.transform(cardProgress);

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

  Color get _glowColor {
    try {
      final hex = wallpaper.glowColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final parallaxOffset = _getParallaxOffset(context);

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
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _glowColor.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Parallax image
              Transform.translate(
                offset: Offset(parallaxOffset, 0),
                child: Transform.scale(
                  scale: 1.1, // slightly oversized for parallax room
                  child: CachedWallpaperImage(imageUrl: wallpaper.previewUrl),
                ),
              ),
              // Bottom gradient
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: SizedBox(height: 60),
                ),
              ),
              // Stats bar (views, downloads, like) — TOP right
              Positioned(
                top: 6,
                right: 6,
                child: WallpaperStatsBar(
                  wallpaperId: wallpaper.id,
                  glowColor: _glowColor,
                ),
              ),
              // Name
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Text(
                  wallpaper.name,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Badge
              if (wallpaper.badge != null)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _glowColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      wallpaper.badge!,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shimmer placeholder for a carousel row while loading.
class CarouselRowShimmer extends StatelessWidget {
  const CarouselRowShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title shimmer
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Shimmer.fromColors(
            baseColor: const Color(0xFF1A1A2E),
            highlightColor: const Color(0xFF2A2A3E),
            child: Container(
              width: 120,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        // Cards shimmer
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: 4,
            itemBuilder: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Shimmer.fromColors(
                baseColor: const Color(0xFF1A1A2E),
                highlightColor: const Color(0xFF2A2A3E),
                child: Container(
                  width: 130,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
