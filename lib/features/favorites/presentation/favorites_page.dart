import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/catalog_service.dart';
import '../../wallpapers/presentation/widgets/wallpaper_card.dart';
import '../providers/favorites_provider.dart';

class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteIds = ref.watch(favoritesProvider);
    final allWallpapers = CatalogService.instance.wallpapers;
    final favorites =
        allWallpapers.where((w) => favoriteIds.contains(w.id)).toList();

    if (favorites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, color: Colors.white24, size: 64),
            SizedBox(height: 12),
            Text(
              'No favorites yet',
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Tap the heart icon on any wallpaper',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.6,
      ),
      itemCount: favorites.length,
      itemBuilder: (context, index) =>
          WallpaperCard(wallpaper: favorites[index]),
    );
  }
}
