import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/design/hud_tokens.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
import '../../data/models/story.dart';
import '../../providers/story_providers.dart';
import 'story_detail_page.dart';

/// STORIES tab — Comic Book Panel (concept #01, picked by Eduardo
/// 2026-05-15). Página de manga con paneles asimétricos, borde dorado
/// grueso, halftone, onomatopoeyas (¡KA-POW!) y bocadillos. Vibra
/// Marvel/Shōnen, ideal para wallpapers episódicos de anime/manga.
class StoriesPage extends ConsumerWidget {
  const StoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(storyCatalogProvider);
    final activeId = ref.watch(activeStoryIdProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF070710),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _HalftoneBg()),
          catalogAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: HudTokens.gold),
            ),
            error: (e, _) => _EmptyState(
              icon: Icons.error_outline,
              title: LocaleHelper.pick(
                  es: 'Error al cargar', en: 'Failed to load'),
              onRetry: () => ref.invalidate(storyCatalogProvider),
            ),
            data: (stories) {
              if (stories.isEmpty) {
                return _EmptyState(
                  icon: Icons.auto_stories,
                  title: LocaleHelper.pick(
                      es: '¡Pronto vienen historias!',
                      en: 'Stories coming soon!'),
                  subtitle: LocaleHelper.pick(
                      es: 'Wallpapers que cuentan una historia',
                      en: 'Wallpapers that tell a story'),
                );
              }
              final featured = stories.first;
              final rest = stories.skip(1).toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                children: [
                  _ComicHeroPanel(
                    story: featured,
                    isActive: activeId == featured.id,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StoryDetailPage(story: featured),
                      ),
                    ),
                  ),
                  if (rest.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _SectionHeader(
                      text: LocaleHelper.pick(
                        es: 'PRÓXIMOS CAPÍTULOS',
                        en: 'NEXT CHAPTERS',
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < rest.length; i++) ...[
                      _ChapterCard(
                        story: rest[i],
                        chapterNumber: i + 2,
                        isActive: activeId == rest[i].id,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoryDetailPage(story: rest[i]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Comic Hero Panel — featured story laid out as a manga page
// ═════════════════════════════════════════════════════════════════════
class _ComicHeroPanel extends StatelessWidget {
  const _ComicHeroPanel({
    required this.story,
    required this.isActive,
    required this.onTap,
  });
  final Story story;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D18),
          border: Border.all(color: HudTokens.gold, width: 3),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: HudTokens.gold.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Featured stats row at top
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              color: HudTokens.gold.withValues(alpha: 0.10),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: HudTokens.goldBright,
                      borderRadius: BorderRadius.circular(2),
                      border:
                          Border.all(color: const Color(0xFF070710), width: 1),
                    ),
                    child: Text(
                      LocaleHelper.pick(
                        es: isActive ? 'EN VIVO' : '¡EL INICIO!',
                        en: isActive ? 'PLAYING' : 'BEGIN!',
                      ),
                      style: GoogleFonts.bangers(
                        fontSize: 11,
                        color: const Color(0xFF070710),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF070710),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: HudTokens.goldBright, width: 1),
                    ),
                    child: Text(
                      'CAP. 01',
                      style: GoogleFonts.bangers(
                        fontSize: 11,
                        color: HudTokens.goldBright,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 3-panel asymmetric layout: 1 big left + 2 small right stacked
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: _PanelCell(
                      imageUrl: story.coverImageUrl,
                      isMain: true,
                      onomatopeya: isActive ? null : _kapowFor(story.category),
                    ),
                  ),
                  Container(
                    width: 3,
                    color: HudTokens.gold,
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Expanded(
                          child: _PanelCell(
                            imageUrl: story.frames.length > 1
                                ? story.frames[1].fullImageUrl
                                : story.coverImageUrl,
                            isMain: false,
                          ),
                        ),
                        Container(
                          height: 3,
                          color: HudTokens.gold,
                        ),
                        Expanded(
                          child: _PanelCell(
                            imageUrl: story.frames.length > 2
                                ? story.frames[2].fullImageUrl
                                : story.coverImageUrl,
                            isMain: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Title bar
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0D0D18),
                border: Border(
                  top: BorderSide(color: HudTokens.gold, width: 2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          story.title.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.bangers(
                            fontSize: 22,
                            color: HudTokens.goldBright,
                            letterSpacing: 1.4,
                            height: 1.0,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.7),
                                blurRadius: 4,
                                offset: const Offset(2, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: HudTokens.goldBright,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            '${story.frames.length} ${LocaleHelper.pick(es: "FRAMES", en: "FRAMES")} · ${story.intervalMinutes} MIN',
                            style: GoogleFonts.bangers(
                              fontSize: 10,
                              color: const Color(0xFF070710),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  WallpaperStatsBar(
                    wallpaperId: 'story_${story.id}',
                    glowColor: HudTokens.gold,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _kapowFor(String category) {
    final upper = category.toUpperCase();
    if (upper.contains('ANIME') || upper.contains('DRAGON')) return '¡KA-POW!';
    if (upper.contains('ZODIAC')) return '¡COSMO!';
    if (upper.contains('ACTION') || upper.contains('FIGHT')) return '¡BAM!';
    if (upper.contains('DARK') || upper.contains('HORROR')) return '¡BOOM!';
    return '¡KA-POW!';
  }
}

// ═════════════════════════════════════════════════════════════════════
// Single panel cell with optional onomatopoeia overlay
// ═════════════════════════════════════════════════════════════════════
class _PanelCell extends StatelessWidget {
  const _PanelCell({
    required this.imageUrl,
    required this.isMain,
    this.onomatopeya,
  });
  final String imageUrl;
  final bool isMain;
  final String? onomatopeya;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          memCacheWidth: isMain ? 480 : 240,
          placeholder: (_, __) => Container(color: const Color(0xFF1A1A24)),
          errorWidget: (_, __, ___) => Container(
            color: const Color(0xFF1A1A24),
            child: const Center(
              child: Icon(Icons.image_not_supported,
                  color: HudTokens.goldDeep, size: 32),
            ),
          ),
        ),
        // Halftone dot overlay on main panel only
        if (isMain)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _PanelHalftonePainter()),
            ),
          ),
        // Vignette gradient
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0x55000000)],
              stops: [0.5, 1.0],
            ),
          ),
        ),
        if (onomatopeya != null && isMain)
          Positioned(
            right: 14,
            bottom: 26,
            child: Transform.rotate(
              angle: -0.18,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: HudTokens.goldBright,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFF070710), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 8,
                      offset: const Offset(3, 3),
                    ),
                  ],
                ),
                child: Text(
                  onomatopeya!,
                  style: GoogleFonts.bangers(
                    fontSize: 28,
                    color: const Color(0xFF070710),
                    letterSpacing: 2,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: HudTokens.gold.withValues(alpha: 0.8),
                        blurRadius: 6,
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

// ═════════════════════════════════════════════════════════════════════
// Chapter card for the rest of the catalog
// ═════════════════════════════════════════════════════════════════════
class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.story,
    required this.chapterNumber,
    required this.isActive,
    required this.onTap,
  });
  final Story story;
  final int chapterNumber;
  final bool isActive;
  final VoidCallback onTap;

  String _capLabel() {
    final n = chapterNumber.toString().padLeft(2, '0');
    return 'CAP. $n';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 86,
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D18),
          border: Border.all(
            color: isActive
                ? HudTokens.goldBright
                : HudTokens.gold.withValues(alpha: 0.55),
            width: isActive ? 2.5 : 2,
          ),
          borderRadius: BorderRadius.circular(3),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: HudTokens.goldBright.withValues(alpha: 0.45),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Cover thumbnail with thick gold border
            Container(
              width: 78,
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: HudTokens.gold, width: 2),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: story.coverImageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 160,
                    placeholder: (_, __) =>
                        Container(color: const Color(0xFF1A1A24)),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF1A1A24),
                      child: const Icon(Icons.image,
                          color: HudTokens.goldDeep, size: 22),
                    ),
                  ),
                  // CAP ribbon
                  Positioned(
                    top: 6,
                    left: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: HudTokens.goldBright,
                        border: Border.all(
                            color: const Color(0xFF070710), width: 1),
                      ),
                      child: Text(
                        _capLabel(),
                        style: GoogleFonts.bangers(
                          fontSize: 9,
                          color: const Color(0xFF070710),
                          letterSpacing: 1,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Title + meta
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      story.title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.bangers(
                        fontSize: 16,
                        color: Colors.white,
                        letterSpacing: 1.2,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${story.frames.length} ${LocaleHelper.pick(es: "FRAMES", en: "FRAMES")} · ${story.intervalMinutes} MIN',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: HudTokens.gold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: HudTokens.goldBright,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          LocaleHelper.pick(es: 'EN VIVO', en: 'PLAYING'),
                          style: GoogleFonts.bangers(
                            fontSize: 9,
                            color: const Color(0xFF070710),
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Stats + chevron
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  WallpaperStatsBar(
                    wallpaperId: 'story_${story.id}',
                    glowColor: HudTokens.gold,
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right,
                      color: HudTokens.gold, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Section header with star + neon-glow gold
// ═════════════════════════════════════════════════════════════════════
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('★',
            style: TextStyle(color: HudTokens.goldBright, fontSize: 13)),
        const SizedBox(width: 7),
        Text(
          text,
          style: GoogleFonts.bangers(
            fontSize: 14,
            color: HudTokens.goldBright,
            letterSpacing: 1.8,
            shadows: [
              Shadow(
                color: HudTokens.gold.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Halftone background
// ═════════════════════════════════════════════════════════════════════
class _HalftoneBg extends StatelessWidget {
  const _HalftoneBg();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _HalftonePainter());
  }
}

class _HalftonePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 18.0;
    final paint = Paint()..color = HudTokens.gold.withValues(alpha: 0.025);
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = 0.0; x < size.width; x += step) {
        final offsetX = (y / step).floor().isOdd ? step / 2 : 0.0;
        canvas.drawCircle(Offset(x + offsetX, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PanelHalftonePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 7.0;
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.18);
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = 0.0; x < size.width; x += step) {
        final offsetX = (y / step).floor().isOdd ? step / 2 : 0.0;
        canvas.drawCircle(Offset(x + offsetX, y), 0.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═════════════════════════════════════════════════════════════════════
// Empty state
// ═════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onRetry,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: HudTokens.goldDeep),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.bangers(
              fontSize: 18,
              color: HudTokens.goldBright,
              letterSpacing: 1.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(
                LocaleHelper.pick(es: 'Reintentar', en: 'Retry'),
                style: const TextStyle(color: HudTokens.gold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
