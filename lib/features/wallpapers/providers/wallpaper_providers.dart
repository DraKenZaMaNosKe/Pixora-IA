import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/categories.dart';
import '../../../core/services/catalog_service.dart';
import '../data/models/wallpaper.dart';

/// Categories that have their own dedicated section in the app and must
/// NEVER bleed into the regular Wallpapers feed (featured / trending / new /
/// category rows). Iah Egyptian and future cultural calendars live in ARCANO.
const _arcanoCategories = {'ARCANO'};

bool _isArcano(Wallpaper w) =>
    _arcanoCategories.contains(w.category.toUpperCase());

/// Raw catalog from Supabase (every wallpaper, used internally + by the
/// ARCANO provider). UI feeds should consume `catalogPublicProvider`.
final catalogProvider = FutureProvider<List<Wallpaper>>((ref) async {
  return CatalogService.instance.fetchCatalog();
});

/// Public catalog with ARCANO items stripped out. This is what the regular
/// Wallpapers/Live tabs see — keeps lunar/tarot content from polluting the
/// general grid (it has its own dedicated tab).
final catalogPublicProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final all = await ref.watch(catalogProvider.future);
  return all.where((w) => !_isArcano(w)).toList();
});

/// ARCANO-only feed for the new mystical/lunar/tarot section.
final arcanoCatalogProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final all = await ref.watch(catalogProvider.future);
  return all.where(_isArcano).toList();
});

/// Categoría actualmente seleccionada en los chips de filtro.
final selectedCategoryProvider =
    StateProvider<WallpaperCategory>((ref) => WallpaperCategory.all);

/// Wallpapers marcados como featured en el catálogo JSON.
final featuredWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  return wallpapers.where((w) => w.featured).toList();
});

/// Hero banner: featured wallpapers, fallback to first 5.
final heroBannerProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final featured = await ref.watch(featuredWallpapersProvider.future);
  if (featured.isNotEmpty) return featured.take(6).toList();
  final all = await ref.watch(catalogPublicProvider.future);
  return all.take(5).toList();
});

/// Trending: sorted by download count (highest first), fallback to sortOrder.
final trendingWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
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
  final wallpapers = await ref.watch(catalogPublicProvider.future);
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
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  final map = <String, List<Wallpaper>>{};
  for (final w in wallpapers) {
    if (Platform.isIOS && w.category.toUpperCase() == 'PANORAMIC') continue;
    map.putIfAbsent(w.category, () => []).add(w);
  }
  return map.entries
      .where((e) => e.value.length >= 3)
      .map((e) => (
            title: e.key[0].toUpperCase() + e.key.substring(1).toLowerCase(),
            items: e.value
          ))
      .toList();
});
