import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/services/catalog_service.dart';
import '../../wallpapers/presentation/widgets/wallpaper_card.dart';
import '../providers/favorites_provider.dart';

class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = context.hud;
    final favoriteIds = ref.watch(favoritesProvider);
    final allWallpapers = CatalogService.instance.wallpapers;
    final favorites =
        allWallpapers.where((w) => favoriteIds.contains(w.id)).toList();

    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, color: h.textDim, size: 48),
            const SizedBox(height: HudTokens.sp4),
            Text(
              '// NO_FAVORITES',
              style: HudTokens.display(
                  size: 14, color: h.accent, letterSpacing: 0.1),
            ),
            const SizedBox(height: HudTokens.sp2),
            Text(
              'TAP THE HEART ICON ON ANY WALLPAPER',
              style: HudTokens.mono(
                  size: 11, color: h.textDim, letterSpacing: 0.15),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(HudTokens.sp3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: HudTokens.sp3,
        crossAxisSpacing: HudTokens.sp3,
        // Ticket card renders ~400 dp tall on a ~188 dp card width (image
        // forces 9:16 → tall content). 0.46 gives ~409 dp card height so
        // the 3.7 px overflow we were seeing at 0.48 is gone with margin.
        childAspectRatio: 0.46,
      ),
      itemCount: favorites.length,
      itemBuilder: (context, index) =>
          WallpaperCard(wallpaper: favorites[index]),
    );
  }
}
