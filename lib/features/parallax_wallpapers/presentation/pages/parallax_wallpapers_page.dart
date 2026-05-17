import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/hud_tokens.dart';
import '../../../wallpapers/data/models/wallpaper.dart';
import '../../../wallpapers/presentation/pages/wallpaper_preview_page.dart';
import '../../providers/parallax_wallpaper_providers.dart';

/// "3D" tab — Holographic Tilt layout (concept #04, Eduardo 2026-05-16).
///
/// Removes all the green/mint from the legacy editorial layout and wraps
/// every card / chip / CTA in an animated holographic foil gradient that
/// mirrors the static wallpaper Trading Card Holo aesthetic (consistency
/// across the app). The metaphor matches the feature: tilting reveals
/// depth, just like a real holographic trading card.
class ParallaxWallpapersPage extends ConsumerWidget {
  const ParallaxWallpapersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = context.hud;
    final asyncList = ref.watch(parallaxWallpapersProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(parallaxWallpapersProvider),
      child: asyncList.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: h.accent),
        ),
        error: (e, _) => const _EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'No pudimos cargar',
          subtitle: 'Revisa tu conexión y desliza para reintentar',
        ),
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyState(
              icon: Icons.threed_rotation_rounded,
              title: 'Pronto · piezas 3D curadas',
              subtitle:
                  'Estamos preparando wallpapers con parallax y profundidad.\nDesliza para reintentar.',
            );
          }
          final hero = items.first;
          final rest = items.skip(1).toList();
          return _MagazineLayout(hero: hero, rest: rest);
        },
      ),
    );
  }
}

class _MagazineLayout extends StatelessWidget {
  const _MagazineLayout({required this.hero, required this.rest});
  final Wallpaper hero;
  final List<Wallpaper> rest;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        // Editorial header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const _HoloChip(label: '3D · TILT'),
                  const SizedBox(width: 8),
                  Text(
                    '${(rest.length + 1).toString().padLeft(2, '0')} piezas curadas',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 1.6,
                      color: h.textDim,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: 'Profundidad\n',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w300,
                        fontSize: 42,
                        height: 0.96,
                        letterSpacing: -1.2,
                        color: h.text,
                      ),
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _HoloShimmerText(
                        text: 'curada.',
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w300,
                          fontSize: 42,
                          height: 0.96,
                          letterSpacing: -1.2,
                          color: h.text,
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(
                  'el equipo de Pixora elige · semanal',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: h.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Hero card
        SliverToBoxAdapter(
          child: _HeroCard(wallpaper: hero),
        ),

        // Editorial quote panel
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: h.accent, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '«La profundidad cobra vida cuando inclinas el teléfono.»',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                      height: 1.4,
                      color: h.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '— pixora editorial',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 9,
                      letterSpacing: 1.4,
                      color: h.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Section header
        if (rest.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
              child: Row(
                children: [
                  Container(width: 18, height: 1, color: h.accent),
                  const SizedBox(width: 10),
                  Text(
                    'MÁS · 3D',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 2.6,
                      color: h.text,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    rest.length.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 1.6,
                      color: h.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 2-column grid
        if (rest.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _GridCard(wallpaper: rest[i]),
                childCount: rest.length,
              ),
            ),
          ),

        // Bottom nav safe-space
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Hero card — wallpaper inside an animated holographic foil frame
// ═════════════════════════════════════════════════════════════════════
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.wallpaper});
  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WallpaperPreviewPage(wallpaper: wallpaper),
          ),
        ),
        child: _HoloFoilFrame(
          padding: 4,
          radius: 14,
          duration: const Duration(seconds: 6),
          extraShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: h.isIosStyle ? 0.18 : 0.55),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
          child: AspectRatio(
            aspectRatio: 0.78,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    wallpaper.previewUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 800,
                    errorBuilder: (_, __, ___) => Container(color: h.surfaceHi),
                  ),
                  // Gradient overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0, 0.5, 1],
                        ),
                      ),
                    ),
                  ),
                  // Top-left badge — solid color, theme-aware
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _SolidBadge(
                      label: '★ EDITOR\'S PICK',
                    ),
                  ),
                  // Bottom holographic APLICAR button
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: _HoloApplyButton(label: '▸ APLICAR'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Grid card — mini holographic foil frame
// ═════════════════════════════════════════════════════════════════════
class _GridCard extends StatelessWidget {
  const _GridCard({required this.wallpaper});
  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WallpaperPreviewPage(wallpaper: wallpaper),
        ),
      ),
      child: _HoloFoilFrame(
        padding: 3,
        radius: 10,
        duration: const Duration(seconds: 7),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                wallpaper.previewUrl,
                fit: BoxFit.cover,
                cacheWidth: 320,
                errorBuilder: (_, __, ___) => Container(color: h.surfaceHi),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: _HoloChip(label: '3D', dense: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Holographic foil frame — animated gradient padding around any child
// ═════════════════════════════════════════════════════════════════════
class _HoloFoilFrame extends StatefulWidget {
  const _HoloFoilFrame({
    required this.child,
    this.padding = 4,
    this.radius = 14,
    this.duration = const Duration(seconds: 6),
    this.extraShadow,
  });
  final Widget child;
  final double padding;
  final double radius;
  final Duration duration;
  final List<BoxShadow>? extraShadow;

  @override
  State<_HoloFoilFrame> createState() => _HoloFoilFrameState();
}

class _HoloFoilFrameState extends State<_HoloFoilFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    // Foil palette per theme — silver/blue iOS, gold/copper B&G
    final colors = isIos
        ? const [
            Color(0xFFC0C5CC),
            Color(0xFFF8FAFF),
            Color(0xFFB8D4FF),
            Color(0xFFF8FAFF),
            Color(0xFFC0C5CC),
          ]
        : const [
            Color(0xFF5A3F12),
            Color(0xFFF5D676),
            Color(0xFFB86F3A),
            Color(0xFFF5D676),
            Color(0xFF5A3F12),
          ];
    final borderTint = isIos
        ? const Color(0xFF0A84FF).withValues(alpha: 0.4)
        : HudTokens.goldBright.withValues(alpha: 0.5);

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        // Animate begin/end alignment to scroll the gradient horizontally.
        final t = _c.value;
        final shift = (t * 2.0) - 1.0; // -1 → 1
        return Container(
          padding: EdgeInsets.all(widget.padding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + shift, -0.3),
              end: Alignment(1.0 + shift, 0.3),
              colors: colors,
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
            ),
            boxShadow: [
              BoxShadow(color: borderTint, blurRadius: 1, spreadRadius: 0),
              if (widget.extraShadow != null) ...widget.extraShadow!,
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Holographic chip — animated gradient pill (used for "3D · TILT" and
// the small "3D" badge on grid cards)
// ═════════════════════════════════════════════════════════════════════
class _HoloChip extends StatefulWidget {
  const _HoloChip({required this.label, this.dense = false});
  final String label;
  final bool dense;

  @override
  State<_HoloChip> createState() => _HoloChipState();
}

class _HoloChipState extends State<_HoloChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    // Chip background: silver/blue gradient on iOS, gold gradient on B&G
    final colors = isIos
        ? const [
            Color(0xFFC0C5CC),
            Color(0xFFF8FAFF),
            Color(0xFFB8D4FF),
            Color(0xFFF8FAFF),
            Color(0xFFC0C5CC),
          ]
        : const [
            Color(0xFF5A3F12),
            Color(0xFFF5D676),
            Color(0xFFB86F3A),
            Color(0xFFF5D676),
            Color(0xFF5A3F12),
          ];
    final border = isIos
        ? const Color(0xFF0A84FF).withValues(alpha: 0.4)
        : HudTokens.goldBright.withValues(alpha: 0.5);
    final textColor = isIos ? const Color(0xFF1C1C1E) : const Color(0xFF0A0A14);

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final shift = (_c.value * 2.0) - 1.0;
        return Container(
          padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? 7 : 10,
              vertical: widget.dense ? 3 : 4),
          decoration: BoxDecoration(
            border: Border.all(color: border, width: 1),
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + shift, 0),
              end: Alignment(1.0 + shift, 0),
              colors: colors,
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
            ),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: widget.dense ? 8 : 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: textColor,
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Holographic APLICAR button — animated 3-stop gradient
// ═════════════════════════════════════════════════════════════════════
class _HoloApplyButton extends StatefulWidget {
  const _HoloApplyButton({required this.label});
  final String label;

  @override
  State<_HoloApplyButton> createState() => _HoloApplyButtonState();
}

class _HoloApplyButtonState extends State<_HoloApplyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    // Apply colors: Apple Blue → Indigo → Purple iOS; Gold → Copper B&G
    final colors = isIos
        ? const [
            Color(0xFF0A84FF), // blue
            Color(0xFF5E5CE6), // indigo
            Color(0xFFBF5AF2), // purple
            Color(0xFF0A84FF),
          ]
        : const [
            Color(0xFFD4AF37), // gold
            Color(0xFFF5D676), // gold-bright
            Color(0xFFE89B5F), // copper-bright
            Color(0xFFD4AF37),
          ];
    final textColor = isIos ? Colors.white : const Color(0xFF0A0A14);

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final shift = (_c.value * 2.0) - 1.0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + shift, 0),
              end: Alignment(1.0 + shift, 0),
              colors: colors,
              stops: const [0.0, 0.33, 0.66, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: (isIos ? const Color(0xFF5E5CE6) : HudTokens.goldBright)
                    .withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.2,
              color: textColor,
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Solid badge — used for non-holo accents like "★ EDITOR'S PICK"
// ═════════════════════════════════════════════════════════════════════
class _SolidBadge extends StatelessWidget {
  const _SolidBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    final fg = isIos ? const Color(0xFF0A84FF) : HudTokens.goldBright;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: fg, width: 1),
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withValues(alpha: 0.55),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.6,
          color: fg,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Holographic shimmer text — animated gradient text using ShaderMask
// ═════════════════════════════════════════════════════════════════════
class _HoloShimmerText extends StatefulWidget {
  const _HoloShimmerText({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_HoloShimmerText> createState() => _HoloShimmerTextState();
}

class _HoloShimmerTextState extends State<_HoloShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    final colors = isIos
        ? const [
            Color(0xFF0A84FF),
            Color(0xFF5E5CE6),
            Color(0xFFBF5AF2),
            Color(0xFF0A84FF),
          ]
        : const [
            Color(0xFFD4AF37),
            Color(0xFFF5D676),
            Color(0xFFE89B5F),
            Color(0xFFD4AF37),
          ];

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final shift = (_c.value * 2.0) - 1.0;
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 + shift, 0),
              end: Alignment(1.0 + shift, 0),
              colors: colors,
              stops: const [0.0, 0.33, 0.66, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: Text(widget.text, style: widget.style),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Icon(icon, color: h.textDim, size: 48),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontStyle: FontStyle.italic,
            fontSize: 22,
            height: 1.1,
            color: h.text,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 11,
            height: 1.5,
            letterSpacing: 0.6,
            color: h.textDim,
          ),
        ),
      ],
    );
  }
}
