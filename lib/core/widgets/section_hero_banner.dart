import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/hud_tokens.dart';

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
    this.accentColor = HudTokens.gold,
  });
}

/// Section hero banner — Holographic Foil Frame (concept #02, Eduardo
/// 2026-05-16). Used by LIVE (and any other section that still needs a
/// rotating featured banner). Animated foil border (silver/blue/violet iOS,
/// gold/copper B&G), holo category pill, title overlay bottom-left, EXPLORE
/// button with shine sweep. Mirrors the HOME hero — the whole app speaks the
/// same "rare collectible" language.
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
    final h = context.hud;

    return SizedBox(
      height: bannerHeight,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return GestureDetector(
                onTap: () => widget.onTap(index),
                child: _HoloBannerPage(item: item),
              );
            },
          ),
          // Dot indicators below the holo frame
          if (widget.items.length > 1)
            Positioned(
              bottom: 6,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.items.length, (i) {
                  final isActive = i == _currentPage;
                  final activeColor = h.isIosStyle
                      ? const Color(0xFF0A84FF)
                      : HudTokens.goldBright;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 28 : 8,
                    height: 3,
                    color: isActive
                        ? activeColor
                        : Colors.white.withValues(alpha: 0.25),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Single hero page — animated foil frame + holo pill + EXPLORE shine
// ═════════════════════════════════════════════════════════════════════
class _HoloBannerPage extends StatefulWidget {
  const _HoloBannerPage({required this.item});
  final HeroBannerItem item;

  @override
  State<_HoloBannerPage> createState() => _HoloBannerPageState();
}

class _HoloBannerPageState extends State<_HoloBannerPage>
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
            Color(0xFFE5C8FF),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      child: AnimatedBuilder(
        animation: _foil,
        builder: (_, __) {
          final shift = (_foil.value * 2.0) - 1.0;
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
                  // Wallpaper full-bleed
                  widget.item.imageUrl.isEmpty
                      ? const _HeroFallback()
                      : CachedNetworkImage(
                          imageUrl: widget.item.imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 640,
                          maxWidthDiskCache: 1080,
                          placeholder: (_, __) =>
                              Container(color: context.hud.bg),
                          errorWidget: (_, __, ___) => const _HeroFallback(),
                        ),
                  // Bottom gradient for legibility
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
                  // Category holo pill top-left
                  if (widget.item.badge.isNotEmpty)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: HoloFoilPill(
                        label: widget.item.badge,
                        controller: _foil,
                        colors: foilColors,
                        isIos: isIos,
                      ),
                    ),
                  // Title + subtitle bottom-left
                  Positioned(
                    left: 16,
                    right: 130,
                    bottom: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.item.title,
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
                        if (widget.item.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                      ],
                    ),
                  ),
                  // EXPLORE shine-sweep button bottom-right
                  Positioned(
                    right: 14,
                    bottom: 16,
                    child: _ExploreShineButton(
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
    );
  }
}

/// Public holographic foil pill — small animated pill that cycles colors.
/// Reusable for category pills, LIVE tags on cards, etc.
class HoloFoilPill extends StatefulWidget {
  const HoloFoilPill({
    super.key,
    required this.label,
    this.controller,
    this.colors,
    this.isIos,
    this.size = HoloFoilPillSize.normal,
  });
  final String label;
  final AnimationController? controller; // pass external or use internal
  final List<Color>? colors; // pass external or derive
  final bool? isIos;
  final HoloFoilPillSize size;

  @override
  State<HoloFoilPill> createState() => _HoloFoilPillState();
}

enum HoloFoilPillSize { mini, normal }

class _HoloFoilPillState extends State<HoloFoilPill>
    with SingleTickerProviderStateMixin {
  AnimationController? _internal;

  AnimationController get _ctrl =>
      widget.controller ??
      (_internal ??= AnimationController(
        vsync: this,
        duration: const Duration(seconds: 5),
      )..repeat());

  @override
  void dispose() {
    _internal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = widget.isIos ?? h.isIosStyle;
    final colors = widget.colors ??
        (isIos
            ? const [
                Color(0xFFC0C5CC),
                Color(0xFFE5C8FF),
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
              ]);
    final isMini = widget.size == HoloFoilPillSize.mini;
    final padding = isMini
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 4);
    final fontSize = isMini ? 6.5 : 8.0;
    final letterSpacing = isMini ? 1.2 : 2.0;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final shift = (_ctrl.value * 2.0) - 1.0;
        return Container(
          padding: padding,
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
                blurRadius: isMini ? 4 : 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: isIos ? const Color(0xFF1C1C1E) : const Color(0xFF0A0A14),
              letterSpacing: letterSpacing,
              height: 1.0,
            ),
          ),
        );
      },
    );
  }
}

class _ExploreShineButton extends StatelessWidget {
  const _ExploreShineButton({required this.controller, required this.isIos});
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
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: controller,
                builder: (_, __) {
                  final v = controller.value;
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
          angle: 0.785398,
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
