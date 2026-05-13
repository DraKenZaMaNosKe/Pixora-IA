import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../constants/supabase_config.dart';
import '../../features/hot_wallpapers/data/models/live_wallpaper.dart';

class LiveWallpaperCatalogService {
  LiveWallpaperCatalogService._();
  static final instance = LiveWallpaperCatalogService._();

  static const _catalogFile = 'live_wallpaper_catalog.json';
  static const _diskCacheFile = 'live_wallpaper_cache.json';

  List<LiveWallpaper>? _cache;
  DateTime? _lastFetch;

  /// Borra el cache in-memory para que el próximo fetch traiga del Storage.
  /// Lo usa el pull-to-refresh de la tab LIVE.
  void clearCache() {
    _cache = null;
    _lastFetch = null;
  }

  /// Cold-start optimization: lee live_wallpaper_cache.json de disco antes
  /// de runApp(). Resultado: la tab LIVE arranca con data al instante en
  /// vez de mostrar el skeleton de loading 1-3s.
  ///
  /// Idempotente. Silencioso ante errores (primera instalación = no cache).
  Future<void> preloadFromDiskCache() async {
    if (_cache != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_diskCacheFile');
      if (!await file.exists()) return;
      final body = await file.readAsString();
      final data = json.decode(body) as Map<String, dynamic>;
      final list = (data['wallpapers'] as List<dynamic>?) ?? [];
      _cache = list
          .map((e) => LiveWallpaper.fromJson(e as Map<String, dynamic>))
          .toList();
      _sortInPlace(_cache!);
      _lastFetch = DateTime.now();
      debugPrint(
          '[Pixora] Live catalog preloaded from disk: ${_cache!.length}');
    } catch (e) {
      debugPrint('[Pixora] Live disk preload failed: $e');
    }
  }

  /// Guarda el body raw del response a disco — más robusto que re-serializar
  /// porque preservamos campos del JSON que aún no estén en el modelo Dart
  /// (cuando agregamos un campo nuevo al catálogo no perdemos data en cache).
  Future<void> _saveRawToDisk(String rawJson) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_diskCacheFile');
      await file.writeAsString(rawJson);
    } catch (e) {
      debugPrint('[Pixora] Live disk save failed: $e');
    }
  }

  void _sortInPlace(List<LiveWallpaper> items) {
    // Sort newest first. Primary key is createdAt (ISO timestamp); items
    // sin date caen a sortOrder DESC.
    items.sort((a, b) {
      final aDate = a.createdAt;
      final bDate = b.createdAt;
      if (aDate != null && bDate != null) return bDate.compareTo(aDate);
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return b.sortOrder.compareTo(a.sortOrder);
    });
  }

  Future<List<LiveWallpaper>> fetchCatalog({bool forceRefresh = false}) async {
    // 30-min cache — admin edits desde Pixora Admin dashboard llegan al
    // usuario en máx 30 min sin necesidad de FCM push. Antes era 6h.
    if (!forceRefresh &&
        _cache != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inMinutes < 30) {
      return _cache!;
    }

    try {
      final url =
          '${SupabaseConfig.storageBase}/wallpaper-videos/$_catalogFile';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final items = (data['wallpapers'] as List<dynamic>?)
                ?.map((e) => LiveWallpaper.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _sortInPlace(items);
        _cache = items;
        _lastFetch = DateTime.now();
        // Persist a disk para próximo cold-start (guarda el response raw).
        unawaited(_saveRawToDisk(response.body));
        return items;
      }
    } catch (e) {
      debugPrint('[Pixora] Live wallpaper catalog fetch failed: $e');
    }

    return _cache ?? [];
  }
}
