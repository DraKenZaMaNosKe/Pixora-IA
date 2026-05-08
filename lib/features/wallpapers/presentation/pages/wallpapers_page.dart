import 'package:flutter/material.dart';
import '../../../../core/design/hud_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/wallpaper_providers.dart';
import '../widgets/hero_banner.dart';
import '../widgets/pixora_daily_banner.dart';
import '../widgets/wallpaper_carousel_row.dart';

class WallpapersPage extends ConsumerWidget {
  const WallpapersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(catalogProvider);
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

            // Trending
            SliverToBoxAdapter(child: _TrendingRow()),

            // New
            SliverToBoxAdapter(child: _NewRow()),

            // Category rows
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
