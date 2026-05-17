import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/design/hud_tokens.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../data/models/wallpaper.dart';
import '../../providers/wallpaper_providers.dart';
import '../pages/wallpaper_preview_page.dart';

/// Hero banner — Holographic Foil Frame (concept #02, Eduardo 2026-05-16).
///
/// Each featured wallpaper sits inside an animated holographic foil border
/// (silver/blue iOS, gold/copper B&G) that shifts colors slowly. A "FEATURED"
/// holo pill floats top-left, the title + category sit bottom-left, and an
/// EXPLORE pill button with shine sweep is bottom-right.
///
/// Consistency play: matches Trading Card Holo (static wallpaper preview) +
/// Holographic Tilt (3D section) so the whole app speaks the same "rare
/// collectible" language.
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
                    _HoloHeroPage(wallpaper: wallpapers[index]),
              ),
              // Dot indicators below the holo frame
              Positioned(
                bottom: 6,
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

// ═════════════════════════════════════════════════════════════════════
// Single holographic hero page — animated foil border + FEATURED pill +
// title overlay + EXPLORE shine-sweep button.
// ═════════════════════════════════════════════════════════════════════
class _HoloHeroPage extends StatefulWidget {
  const _HoloHeroPage({required this.wallpaper});
  final Wallpaper wallpaper;

  @override
  State<_HoloHeroPage> createState() => _HoloHeroPageState();
}

class _HoloHeroPageState extends State<_HoloHeroPage>
    with TickerProviderStateMixin {
  late final AnimationController _foil;
  late final AnimationController _shine;

  @override
  void initState() {
    super.initState();
    _foil = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _shine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
  }

  @override
  void dispose() {
    _foil.dispose();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    final foilColors = isIos
        ? const [
            Color(0xFFC0C5CC),
            Color(0xFFE5C8FF), // soft violet
            Color(0xFFF8FAFF),
            Color(0xFFB8D4FF),
            Color(0xFFC0C5CC),
          ]
        : const [
            Color(0xFF5A3F12),
            Color(0xFFF5D676),
            Color(0xFFB86F3A),
            Color(0xFFF5D676),
            Color(0xFF5A3F12),
          ];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WallpaperPreviewPage(wallpaper: widget.wallpaper),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        child: AnimatedBuilder(
          animation: _foil,
          builder: (_, __) {
            final t = _foil.value;
            final shift = (t * 2.0) - 1.0;
            return Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment(-1.0 + shift, -0.3),
                  end: Alignment(1.0 + shift, 0.3),
                  colors: foilColors,
                  stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isIos ? const Color(0xFFE5C8FF) : HudTokens.gold)
                        .withValues(alpha: 0.35),
                    blurRadius: 26,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedWallpaperImage(imageUrl: widget.wallpaper.previewUrl),
                    // Bottom gradient overlay for legibility
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.65),
                            Colors.black.withValues(alpha: 0.88),
                          ],
                          stops: const [0.0, 0.5, 0.82, 1.0],
                        ),
                      ),
                    ),
                    // FEATURED holo pill top-left
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _HoloPill(
                        label: 'FEATURED',
                        controller: _foil,
                        colors: foilColors,
                        isIos: isIos,
                      ),
                    ),
                    // Title + category at bottom-left
                    Positioned(
                      left: 16,
                      right: 130,
                      bottom: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.wallpaper.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.fraunces(
                              fontSize: 22,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.1,
                              letterSpacing: -0.4,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  offset: const Offset(0, 2),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.wallpaper.category.toUpperCase()} · VOL XII',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.80),
                              letterSpacing: 1.8,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  offset: const Offset(0, 1),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // EXPLORE shine-sweep button bottom-right
                    Positioned(
                      right: 14,
                      bottom: 16,
                      child: _ExploreButton(
                        controller: _shine,
                        isIos: isIos,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Tiny holographic FEATURED pill
// ═════════════════════════════════════════════════════════════════════
class _HoloPill extends StatelessWidget {
  const _HoloPill({
    required this.label,
    required this.controller,
    required this.colors,
    required this.isIos,
  });
  final String label;
  final AnimationController controller;
  final List<Color> colors;
  final bool isIos;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final shift = (controller.value * 2.0) - 1.0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + shift, 0),
              end: Alignment(1.0 + shift, 0),
              colors: colors,
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
            ),
            border: Border.all(
              color: (isIos ? const Color(0xFF0A84FF) : HudTokens.goldBright)
                  .withValues(alpha: 0.45),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: isIos ? const Color(0xFF1C1C1E) : const Color(0xFF0A0A14),
              letterSpacing: 2.0,
              height: 1.0,
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// EXPLORE pill button with shine sweep every 3.5s
// ═════════════════════════════════════════════════════════════════════
class _ExploreButton extends StatelessWidget {
  const _ExploreButton({required this.controller, required this.isIos});
  final AnimationController controller;
  final bool isIos;

  @override
  Widget build(BuildContext context) {
    final bgColor = isIos
        ? Colors.white.withValues(alpha: 0.95)
        : const Color(0xFF14141F).withValues(alpha: 0.92);
    final txtColor = isIos ? const Color(0xFF1C1C1E) : HudTokens.goldBright;
    final borderColor = isIos ? const Color(0xFF0A84FF) : HudTokens.goldBright;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: borderColor.withValues(alpha: 0.45), width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: borderColor.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'EXPLORE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: txtColor,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, size: 14, color: txtColor),
              ],
            ),
          ),
          // Shine sweep overlay
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: controller,
                builder: (_, __) {
                  final v = controller.value;
                  // 0..0.6 idle, 0.6..0.8 sweep
                  final double t;
                  final double opacity;
                  if (v < 0.6) {
                    t = -1.0;
                    opacity = 0;
                  } else if (v < 0.8) {
                    final p = (v - 0.6) / 0.20;
                    t = -1.0 + p * 2.0;
                    opacity = (1 - (p - 0.5).abs() * 2) * 0.5;
                  } else {
                    t = 1.0;
                    opacity = 0;
                  }
                  return FractionalTranslation(
                    translation: Offset(t, 0),
                    child: Opacity(
                      opacity: opacity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: const Alignment(-0.5, -1),
                            end: const Alignment(0.5, 1),
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: isIos ? 0.7 : 0.4),
                              Colors.transparent,
                            ],
                            stops: const [0.30, 0.50, 0.70],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
