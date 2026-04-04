import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// ── Data model ─────────────────────────────────────────────────────
class HeroBannerItem {
  final String imageUrl;
  final String title;
  final String subtitle;
  final String badge;
  final Color accentColor;

  const HeroBannerItem({
    required this.imageUrl,
    required this.title,
    this.subtitle = '',
    this.badge = '',
    this.accentColor = const Color(0xFFE50914), // Netflix red
  });
}

// ── Reusable Netflix-style hero banner ─────────────────────────────
class SectionHeroBanner extends StatefulWidget {
  final List<HeroBannerItem> items;
  final void Function(int index) onTap;
  final double height; // fraction of screen height

  const SectionHeroBanner({
    super.key,
    required this.items,
    required this.onTap,
    this.height = 0.42,
  });

  @override
  State<SectionHeroBanner> createState() => _SectionHeroBannerState();
}

class _SectionHeroBannerState extends State<SectionHeroBanner> {
  late final PageController _pageController;
  Timer? _autoScrollTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    if (widget.items.length <= 1) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted) return;
      final next = (_currentPage + 1) % widget.items.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final bannerHeight = MediaQuery.of(context).size.height * widget.height;

    return SizedBox(
      height: bannerHeight,
      child: Stack(
        children: [
          // ── Page view ────────────────────────────────────────
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return GestureDetector(
                onTap: () => widget.onTap(index),
                child: _BannerPage(item: item),
              );
            },
          ),

          // ── Dot indicators ───────────────────────────────────
          if (widget.items.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.items.length, (i) {
                  final isActive = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : Colors.white30,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Single banner page ─────────────────────────────────────────────
class _BannerPage extends StatelessWidget {
  final HeroBannerItem item;
  const _BannerPage({required this.item});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background image ──────────────────────────────────
        CachedNetworkImage(
          imageUrl: item.imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: const Color(0xFF0A0A0F)),
          errorWidget: (_, __, ___) => Container(
            color: const Color(0xFF0A0A0F),
            child: const Icon(Icons.image_not_supported,
                color: Colors.white24, size: 48),
          ),
        ),

        // ── Bottom gradient fade ──────────────────────────────
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  const Color(0xFF0A0A0F).withOpacity(0.6),
                  const Color(0xFF0A0A0F),
                ],
                stops: const [0.0, 0.35, 0.7, 1.0],
              ),
            ),
          ),
        ),

        // ── Content overlay ───────────────────────────────────
        Positioned(
          bottom: 32,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge chip
              if (item.badge.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: item.accentColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    item.badge.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: item.accentColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),

              // Title
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // Subtitle
              if (item.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white60,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Play / Explore button
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: item.accentColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: item.accentColor.withOpacity(0.4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'EXPLORE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
