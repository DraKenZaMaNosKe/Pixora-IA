import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/design/hud_shapes.dart';
import '../../../../core/design/hud_tokens.dart';
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
  int _timerForCount = 0;

  /// Restart the periodic auto-scroll timer.
  ///
  /// Always called from [onPageChanged] (manual swipe) so the next auto-advance
  /// is 7s from now, not 7s from the last timer tick.
  ///
  /// Called from [build] only when item count changes (first load or hot
  /// reload). Without this guard the timer was being recreated on every
  /// `ListenableBuilder(ThemeService)` + Riverpod rebuild, which thrashes the
  /// 7s window so the next advance never lands.
  void _restartAutoScroll(int itemCount) {
    _autoTimer?.cancel();
    _timerForCount = itemCount;
    if (itemCount <= 1) {
      _autoTimer = null;
      return;
    }
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

  void _ensureAutoScroll(int itemCount) {
    if (_autoTimer == null || _timerForCount != itemCount) {
      _restartAutoScroll(itemCount);
    }
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
        _ensureAutoScroll(wallpapers.length);
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: wallpapers.length,
                onPageChanged: (i) {
                  setState(() => _currentPage = i);
                  _restartAutoScroll(wallpapers.length);
                },
                itemBuilder: (context, index) =>
                    _HeroPage(wallpaper: wallpapers[index]),
              ),
              // Dot indicators — Strict B&G (gold) in dark; Apple Blue in iOS
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(wallpapers.length, (i) {
                    final active = i == _currentPage;
                    final activeColor = h.isIosStyle
                        ? const Color(0xFF0A84FF)
                        : HudTokens.goldBright;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 28 : 8,
                      height: 3,
                      color: active
                          ? activeColor
                          : Colors.white.withValues(alpha: 0.25),
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
                  h.bg.withValues(alpha: 0.85),
                  h.bg,
                ],
                stops: const [0.0, 0.4, 0.78, 1.0],
              ),
            ),
          ),
          // ▲ LOADED tag removed in Strict B&G concept #01 (2026-05-15) —
          // it added clutter without value. Image + pill speak for themselves.

          // Category pill — Strict B&G (gold) in dark; Apple Blue in iOS.
          // Reemplaza el mint green que choca tanto con B&G como con iOS White.
          Positioned(
            bottom: 44,
            left: 20,
            right: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: h.isIosStyle ? 10 : HudTokens.sp2,
                      vertical: h.isIosStyle ? 4 : 3),
                  decoration: BoxDecoration(
                    color: h.isIosStyle
                        ? const Color(0xFF0A84FF)
                        : HudTokens.goldBright,
                    borderRadius: BorderRadius.circular(h.isIosStyle ? 999 : 0),
                    boxShadow: h.isIosStyle
                        ? null
                        : [
                            BoxShadow(
                              color: HudTokens.gold.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Text(
                    wallpaper.category.toUpperCase(),
                    style: HudTokens.mono(
                      size: 9,
                      weight: FontWeight.w700,
                      color:
                          h.isIosStyle ? Colors.white : const Color(0xFF070710),
                      letterSpacing: h.isIosStyle ? 0.6 : 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Play button — iOS frosted glass with mint glow / B&G corner-cut
          Positioned(
            bottom: 48,
            right: 16,
            child: h.isIosStyle
                ? ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.28),
                              h.accent.withValues(alpha: 0.42),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.45),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: h.accent.withValues(alpha: 0.5),
                              blurRadius: 18,
                              spreadRadius: -2,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 30),
                      ),
                    ),
                  )
                : ClipPath(
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
