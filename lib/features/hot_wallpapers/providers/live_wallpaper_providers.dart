import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/live_wallpaper_catalog_service.dart';
import '../data/models/live_wallpaper.dart';

final liveWallpaperCatalogProvider =
    FutureProvider<List<LiveWallpaper>>((ref) async {
  return LiveWallpaperCatalogService.instance.fetchCatalog();
});
