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
