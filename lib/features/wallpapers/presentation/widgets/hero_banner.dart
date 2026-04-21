import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/design/hud_shapes.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/design/hud_widgets.dart';
import '../../../../core/utils/color_utils.dart';
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

    final h = context.hud;
    return bannerAsync.when(
      loading: () => Shimmer.fromColors(
        baseColor: h.surface,
        highlightColor: h.surfaceHi,
        child: Container(height: height, color: h.surface),
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
                      width: active ? 28 : 8,
                      height: 3,
                      color: active ? h.accent : Colors.white.withOpacity(0.25),
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

  Color get _glowColor =>
      parseHexColor(wallpaper.glowColor, fallback: Colors.deepOrange);

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
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
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  h.bg.withOpacity(0.85),
                  h.bg,
                ],
                stops: const [0.0, 0.4, 0.78, 1.0],
              ),
            ),
          ),
          // HUD status tag top-right
          Positioned(
            top: 60,
            right: 16,
            child: HudStatusTag(text: '▲ LOADED', color: h.accent),
          ),
          // Info
          Positioned(
            bottom: 44,
            left: 20,
            right: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: HudTokens.sp2, vertical: 3),
                  color: h.accent,
                  child: Text(
                    wallpaper.category.toUpperCase(),
                    style: HudTokens.mono(
                      size: 9,
                      weight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
                const SizedBox(height: HudTokens.sp3),
                Text(
                  wallpaper.name.toUpperCase(),
                  style: HudTokens.display(
                    size: 24,
                    color: Colors.white,
                    letterSpacing: -0.01,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (wallpaper.description.isNotEmpty) ...[
                  const SizedBox(height: HudTokens.sp2),
                  Text(
                    '> ${wallpaper.description}',
                    style: HudTokens.mono(
                      size: 11,
                      color: Colors.white.withOpacity(0.7),
                      letterSpacing: 0.05,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Play button — corner-cut, accent color
          Positioned(
            bottom: 48,
            right: 16,
            child: ClipPath(
              clipper: const CornerCutClipper(cut: 8),
              child: Container(
                color: h.accent,
                padding: const EdgeInsets.symmetric(
                    horizontal: HudTokens.sp4, vertical: HudTokens.sp3),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
