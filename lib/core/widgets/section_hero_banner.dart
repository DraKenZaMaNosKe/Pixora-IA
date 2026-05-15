import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/design/hud_tokens.dart';

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
    this.accentColor = HudTokens.gold, // default accent — overridden per item
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
    // Concept #03 Frosted Glass — wallpaper full-bleed + glass card flotante
    // con todo el texto adentro. Resuelve contraste sobre wallpapers brillantes.
    // Eduardo eligió este de 5 mockups el 2026-05-15.
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Wallpaper full-bleed ──────────────────────────────
        item.imageUrl.isEmpty
            ? const _HeroFallback()
            : CachedNetworkImage(
                imageUrl: item.imageUrl,
                fit: BoxFit.cover,
                memCacheWidth: 640,
                maxWidthDiskCache: 1080,
                placeholder: (_, __) => Container(color: context.hud.bg),
                errorWidget: (_, __, ___) => const _HeroFallback(),
              ),

        // ── Category pill (flota top-left sobre wallpaper) ────
        if (item.badge.isNotEmpty)
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: item.accentColor,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                item.badge.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),

        // ── Frosted glass card (bottom, 14px inset) ───────────
        Positioned(
          left: 14,
          right: 14,
          bottom: 14,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF14141F).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFF5D676).withValues(alpha: 0.25),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.15,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    // EXPLORE button — white pill on glass, dark text
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'EXPLORE',
                            style: HudTokens.display(
                              size: 11,
                              weight: FontWeight.w800,
                              color: const Color(0xFF070710),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '→',
                            style: TextStyle(
                              color: Color(0xFF070710),
                              fontSize: 14,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Fallback when no hero image available ─────────────────────────
class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [
            const Color(0xFF1A140A),
            context.hud.bg,
          ],
        ),
      ),
      child: Center(
        child: Transform.rotate(
          angle: 0.785398, // 45°
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              border: Border.all(
                color: context.hud.accent.withValues(alpha: 0.55),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Transform.rotate(
                angle: -0.785398,
                child: Text(
                  'P',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontStyle: FontStyle.italic,
                    fontSize: 34,
                    color: context.hud.accent2.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
