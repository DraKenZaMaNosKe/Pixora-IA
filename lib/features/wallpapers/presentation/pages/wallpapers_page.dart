import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/wallpaper_providers.dart';
import '../widgets/category_chips.dart';
import '../widgets/wallpaper_card.dart';

class WallpapersPage extends ConsumerWidget {
  const WallpapersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpapersAsync = ref.watch(filteredWallpapersProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(catalogProvider);
      },
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 8, bottom: 12),
              child: CategoryChips(),
            ),
          ),
          wallpapersAsync.when(
            data: (wallpapers) {
              if (wallpapers.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No wallpapers found',
                      style: TextStyle(color: Colors.white38),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.6,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        WallpaperCard(wallpaper: wallpapers[index]),
                    childCount: wallpapers.length,
                  ),
                ),
              );
            },
            error: (err, _) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off,
                        color: Colors.white24, size: 48),
                    const SizedBox(height: 12),
                    Text('Failed to load wallpapers',
                        style: TextStyle(color: Colors.white.withOpacity(0.5))),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(catalogProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}
