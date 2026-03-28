import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/wallpaper_providers.dart';
import '../widgets/hero_banner.dart';
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
                    const Icon(Icons.cloud_off,
                        color: Colors.white24, size: 48),
                    const SizedBox(height: 12),
                    Text('Failed to load wallpapers',
                        style:
                            TextStyle(color: Colors.white.withOpacity(0.5))),
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
      data: (rows) => Column(
        children: rows
            .map((r) => WallpaperCarouselRow(title: r.title, items: r.items))
            .toList(),
      ),
      loading: () => const Column(
        children: [CarouselRowShimmer(), CarouselRowShimmer()],
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
