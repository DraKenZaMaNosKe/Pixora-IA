import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../data/models/wallpaper.dart';
import '../../providers/wallpaper_providers.dart';
import '../pages/wallpaper_preview_page.dart';

class HeroBanner extends ConsumerStatefulWidget {
  const HeroBanner({super.key});

  @override
  ConsumerState<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends ConsumerState<HeroBanner> {
  final _controller = PageController();
  Timer? _autoTimer;
  int _currentPage = 0;

  void _startAutoScroll(int itemCount) {
    _autoTimer?.cancel();
    if (itemCount <= 1) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_controller.hasClients) return;
      _currentPage = (_currentPage + 1) % itemCount;
      _controller.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannerAsync = ref.watch(heroBannerProvider);
    final height = MediaQuery.of(context).size.height * 0.52;

    return bannerAsync.when(
      loading: () => Shimmer.fromColors(
        baseColor: const Color(0xFF1A1A2E),
        highlightColor: const Color(0xFF2A2A3E),
        child: Container(height: height, color: const Color(0xFF1A1A2E)),
      ),
      error: (_, __) => SizedBox(height: height),
      data: (wallpapers) {
        if (wallpapers.isEmpty) return SizedBox(height: height);
        _startAutoScroll(wallpapers.length);
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: wallpapers.length,
                onPageChanged: (i) {
                  setState(() => _currentPage = i);
                  _startAutoScroll(wallpapers.length);
                },
                itemBuilder: (context, index) =>
                    _HeroPage(wallpaper: wallpapers[index]),
              ),
              // Dot indicators
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(wallpapers.length, (i) {
                    final active = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 24 : 8,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: active
                            ? Colors.white
                            : Colors.white.withOpacity(0.3),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroPage extends StatelessWidget {
  const _HeroPage({required this.wallpaper});
  final Wallpaper wallpaper;

  Color get _glowColor {
    try {
      final hex = wallpaper.glowColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.deepPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WallpaperPreviewPage(wallpaper: wallpaper),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedWallpaperImage(imageUrl: wallpaper.previewUrl),
          // Gradient fade to background
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Color(0xCC0A0A0F),
                  Color(0xFF0A0A0F),
                ],
                stops: [0.0, 0.4, 0.75, 1.0],
              ),
            ),
          ),
          // Info
          Positioned(
            bottom: 36,
            left: 20,
            right: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _glowColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _glowColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    wallpaper.category,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _glowColor,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  wallpaper.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (wallpaper.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    wallpaper.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Preview button
          Positioned(
            bottom: 42,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: _glowColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Icon(Icons.play_arrow_rounded,
                    color: Colors.black, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
