import 'package:flutter/material.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/services/app_strings_service.dart';
import '../../../../core/services/catalog_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/wallpaper.dart';
import '../../providers/wallpaper_providers.dart';
import '../widgets/category_chip_hud.dart';
import '../widgets/hero_banner.dart';
import '../widgets/pixora_daily_banner.dart';
import '../widgets/wallpaper_carousel_row.dart';
import 'wallpaper_viewer_hud_page.dart';

class WallpapersPage extends ConsumerWidget {
  const WallpapersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogProvider);

    return RefreshIndicator(
      onRefresh: () async {
        // Pull-to-refresh — fuerza fetch fresco del Storage. Sin clearCache()
        // el singleton retorna su cache vigente (TTL 30min) y el provider
        // re-fetched no traería nada nuevo.
        CatalogService.instance.clearCache();
        ref.invalidate(catalogProvider);
        await Future.wait([
          ref.read(catalogProvider.future),
          AppStringsService.instance.refresh(),
        ]);
      },
      child: catalogAsync.when(
        loading: () => const CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: CarouselRowShimmer()),
            SliverToBoxAdapter(child: CarouselRowShimmer()),
            SliverToBoxAdapter(child: CarouselRowShimmer()),
          ],
        ),
        error: (err, _) => CustomScrollView(
          slivers: [
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, color: context.hud.divider, size: 48),
                    const SizedBox(height: 12),
                    Text('Failed to load wallpapers',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5))),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(catalogProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        data: (_) => CustomScrollView(
          slivers: [
            // Hero Banner
            const SliverToBoxAdapter(child: HeroBanner()),

            // Pixora Daily — featured entry point for the auto-rotating
            // wallpaper feature (formerly buried in Settings).
            const SliverToBoxAdapter(child: PixoraDailyBanner()),

            // HUD chips row — entry point to the WallpaperViewerHudPage
            // (Eduardo's pick 2026-05-17). Tap any chip opens the special
            // explorer with horizontal swipe + native ads. Independent of
            // the carousels below (those keep the normal browse experience).
            const SliverToBoxAdapter(child: _HudChipsRow()),

            // Trending
            SliverToBoxAdapter(child: _TrendingRow()),

            // New
            SliverToBoxAdapter(child: _NewRow()),

            // Curated sections — multi-category via tags. Un wallpaper
            // PANORAMIC con tag `arte` aparece aquí Y en su categoría natural.
            SliverToBoxAdapter(child: _ArteRow()),
            SliverToBoxAdapter(child: _MitologiaRow()),

            // Category rows (excluye categorías ya curadas arriba)
            SliverToBoxAdapter(child: _CategoryRows()),

            // Bottom padding
            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }
}

class _TrendingRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trendingWallpapersProvider);
    return async.when(
      data: (items) => items.isEmpty
          ? const SizedBox.shrink()
          : WallpaperCarouselRow(title: 'Trending', items: items),
      loading: () => const CarouselRowShimmer(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _NewRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(newWallpapersProvider);
    return async.when(
      data: (items) => items.isEmpty
          ? const SizedBox.shrink()
          : WallpaperCarouselRow(title: 'New', items: items),
      loading: () => const CarouselRowShimmer(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ArteRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(arteWallpapersProvider);
    return async.when(
      data: (items) => items.isEmpty
          ? const SizedBox.shrink()
          : WallpaperCarouselRow(title: 'Arte', items: items),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _MitologiaRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mitologiaWallpapersProvider);
    return async.when(
      data: (items) => items.isEmpty
          ? const SizedBox.shrink()
          : WallpaperCarouselRow(title: 'Mitología', items: items),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _CategoryRows extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoryRowsProvider);
    return async.when(
      // ListView.builder with shrinkWrap so each row is built ONLY when
      // it scrolls into view. Previously a Column with .map().toList()
      // built all 8+ category carousels at once on first paint, mounting
      // ~80 wallpaper cards' image bitmaps even though only 1-2 rows
      // were on screen — major contributor to the 1 GB memory baseline.
      data: (rows) => ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows.length,
        // ignore: deprecated_member_use
        cacheExtent: 200,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        itemBuilder: (_, i) => WallpaperCarouselRow(
          title: rows[i].title,
          items: rows[i].items,
        ),
      ),
      loading: () => const Column(
        children: [CarouselRowShimmer(), CarouselRowShimmer()],
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// HUD chips row — entry point to the special wallpaper explorer (viewer).
/// Tap any chip opens WallpaperViewerHudPage filtered by that category.
/// Visual: Dual-Layer HUD chips (cyan/amber outline + LED dot).
class _HudChipsRow extends ConsumerStatefulWidget {
  const _HudChipsRow();

  @override
  ConsumerState<_HudChipsRow> createState() => _HudChipsRowState();
}

class _HudChipsRowState extends ConsumerState<_HudChipsRow> {
  String? _activeKey;

  // Each chip = (display label, provider key, fetcher).
  // Order matters: leftmost is highest visibility.
  static const _chips = <_ChipDef>[
    _ChipDef(label: 'TRENDING', key: 'trending'),
    _ChipDef(label: 'NEW', key: 'new'),
    _ChipDef(label: 'PANORAMIC', key: 'panoramic'),
    _ChipDef(label: 'ANIME', key: 'anime'),
    _ChipDef(label: 'GAMING', key: 'gaming'),
    _ChipDef(label: 'ARTE', key: 'arte'),
    _ChipDef(label: 'MITO', key: 'mitologia'),
    _ChipDef(label: 'CALENDAR', key: 'calendar'),
  ];

  Future<List<Wallpaper>> _fetch(WidgetRef ref, String key) async {
    switch (key) {
      case 'trending':
        return ref.read(trendingWallpapersProvider.future);
      case 'new':
        return ref.read(newWallpapersProvider.future);
      case 'panoramic':
        return ref.read(panoramicWallpapersProvider.future);
      case 'anime':
        return ref.read(animeWallpapersProvider.future);
      case 'gaming':
        return ref.read(gamingWallpapersProvider.future);
      case 'arte':
        return ref.read(arteWallpapersProvider.future);
      case 'mitologia':
        return ref.read(mitologiaWallpapersProvider.future);
      case 'calendar':
        return ref.read(calendarWallpapersProvider.future);
      default:
        return const [];
    }
  }

  Future<void> _openViewer(String key, String label) async {
    setState(() => _activeKey = key);
    final items = await _fetch(ref, key);
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sin wallpapers en $label todavía')),
      );
      setState(() => _activeKey = null);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WallpaperViewerHudPage(
          wallpapers: items,
          category: label,
        ),
      ),
    );
    if (mounted) setState(() => _activeKey = null);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Same dark band background regardless of app theme — gives the chips
      // their "command console" feel and previews the HUD aesthetic before
      // tap.
      color: const Color(0xFF02050A),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final c in _chips) ...[
              CategoryChipHud(
                label: c.label,
                active: _activeKey == c.key,
                onTap: () => _openViewer(c.key, c.label),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChipDef {
  const _ChipDef({required this.label, required this.key});
  final String label;
  final String key;
}
