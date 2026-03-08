import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/categories.dart';
import '../../../core/services/catalog_service.dart';
import '../data/models/wallpaper.dart';

final catalogProvider = FutureProvider<List<Wallpaper>>((ref) async {
  return CatalogService.instance.fetchCatalog();
});

final selectedCategoryProvider =
    StateProvider<WallpaperCategory>((ref) => WallpaperCategory.all);

final filteredWallpapersProvider = Provider<AsyncValue<List<Wallpaper>>>((ref) {
  final catalog = ref.watch(catalogProvider);
  final category = ref.watch(selectedCategoryProvider);

  return catalog.whenData((wallpapers) {
    if (category == WallpaperCategory.all) return wallpapers;
    return wallpapers
        .where((w) =>
            w.category.toUpperCase() == category.name.replaceAll('_', '').toUpperCase())
        .toList();
  });
});

final featuredWallpapersProvider = Provider<AsyncValue<List<Wallpaper>>>((ref) {
  final catalog = ref.watch(catalogProvider);
  return catalog.whenData(
      (wallpapers) => wallpapers.where((w) => w.featured).toList());
});
