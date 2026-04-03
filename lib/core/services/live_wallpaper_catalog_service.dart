import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/supabase_config.dart';
import '../../features/hot_wallpapers/data/models/live_wallpaper.dart';

class LiveWallpaperCatalogService {
  LiveWallpaperCatalogService._();
  static final instance = LiveWallpaperCatalogService._();

  static const _catalogFile = 'live_wallpaper_catalog.json';

  List<LiveWallpaper>? _cache;
  DateTime? _lastFetch;

  Future<List<LiveWallpaper>> fetchCatalog({bool forceRefresh = false}) async {
    // 6-hour cache
    if (!forceRefresh &&
        _cache != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inHours < 6) {
      return _cache!;
    }

    try {
      final url =
          '${SupabaseConfig.storageBase}/wallpaper-videos/$_catalogFile';
      final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final items = (data['wallpapers'] as List<dynamic>?)
                ?.map((e) => LiveWallpaper.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _cache = items;
        _lastFetch = DateTime.now();
        return items;
      }
    } catch (e) {
      debugPrint('[Pixora] Live wallpaper catalog fetch failed: $e');
    }

    return _cache ?? [];
  }
}
