import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/categories.dart';
import '../../../core/services/catalog_service.dart';
import '../data/models/wallpaper.dart';

/// Provider principal: descarga y cachea el catálogo desde Supabase.
/// Se invalida con ref.invalidate(catalogProvider) en pull-to-refresh.
final catalogProvider = FutureProvider<List<Wallpaper>>((ref) async {
  return CatalogService.instance.fetchCatalog();
});

/// Categoría actualmente seleccionada en los chips de filtro.
final selectedCategoryProvider =
    StateProvider<WallpaperCategory>((ref) => WallpaperCategory.all);

/// Wallpapers filtrados por categoría.
///
/// FIX: Antes era Provider<AsyncValue<List>> — ahora es FutureProvider
/// que propaga correctamente los estados loading/error/data.
final filteredWallpapersProvider =
    FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogProvider.future);
  final category = ref.watch(selectedCategoryProvider);

  var filtered = wallpapers;

  // iOS: exclude panoramic wallpapers (no panoramic scroll support)
  if (Platform.isIOS) {
    filtered = filtered.where((w) => w.category.toUpperCase() != 'PANORAMIC').toList();
  }

  if (category == WallpaperCategory.all) return filtered;

  return filtered
      .where((w) =>
          w.category.toUpperCase() ==
          category.name.replaceAll('_', '').toUpperCase())
      .toList();
});

/// Wallpapers marcados como featured en el catálogo JSON.
final featuredWallpapersProvider =
    FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogProvider.future);
  return wallpapers.where((w) => w.featured).toList();
});

/// Hero banner: featured wallpapers, fallback to first 5.
final heroBannerProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final featured = await ref.watch(featuredWallpapersProvider.future);
  if (featured.isNotEmpty) return featured.take(6).toList();
  final all = await ref.watch(catalogProvider.future);
  return all.take(5).toList();
});

/// Trending: sorted by sortOrder (lowest = most popular), top 15.
final trendingWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogProvider.future);
  final sorted = [...wallpapers]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return sorted.take(15).toList();
});

/// New wallpapers: those with badge == 'NEW'.
final newWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogProvider.future);
  return wallpapers.where((w) => w.badge == 'NEW').take(15).toList();
});

/// Category rows: grouped by category, min 3 items per row.
final categoryRowsProvider =
    FutureProvider<List<({String title, List<Wallpaper> items})>>((ref) async {
  final wallpapers = await ref.watch(catalogProvider.future);
  final map = <String, List<Wallpaper>>{};
  for (final w in wallpapers) {
    if (Platform.isIOS && w.category.toUpperCase() == 'PANORAMIC') continue;
    map.putIfAbsent(w.category, () => []).add(w);
  }
  return map.entries
      .where((e) => e.value.length >= 3)
      .map((e) => (title: e.key[0].toUpperCase() + e.key.substring(1).toLowerCase(), items: e.value))
      .toList();
});
