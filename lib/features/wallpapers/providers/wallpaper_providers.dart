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

/// Trending: sorted by download count (highest first), fallback to sortOrder.
final trendingWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogProvider.future);
  final sorted = [...wallpapers]..sort((a, b) {
    // Primary: downloadCount descending
    if (a.downloadCount != b.downloadCount) {
      return b.downloadCount.compareTo(a.downloadCount);
    }
    // Fallback: sortOrder ascending
    return a.sortOrder.compareTo(b.sortOrder);
  });
  return sorted.take(15).toList();
});

/// New wallpapers: added within last 14 days or badge == 'NEW'.
final newWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogProvider.future);
  final newOnes = wallpapers.where((w) => w.isNew).toList();
  // Sort newest first
  newOnes.sort((a, b) {
    final aDate = a.createdAt ?? DateTime(2000);
    final bDate = b.createdAt ?? DateTime(2000);
    return bDate.compareTo(aDate);
  });
  return newOnes.take(15).toList();
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
