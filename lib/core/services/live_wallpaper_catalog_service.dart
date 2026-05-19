import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../constants/supabase_config.dart';
import '../../features/hot_wallpapers/data/models/live_wallpaper.dart';
import 'catalog_cache_store.dart';

/// Catálogo de live wallpapers. Tier 3 (2026-05-18): migrado a
/// `CatalogCacheStore` para que el cache sea Hive-backed y use el flujo
/// TTL + ETag HEAD-check + FCM invalidation.
class LiveWallpaperCatalogService {
  LiveWallpaperCatalogService._();
  static final instance = LiveWallpaperCatalogService._();

  static const _catalogFile = 'live_wallpaper_catalog.json';
  static const _cacheKey = 'wallpaper-videos:live_wallpaper_catalog.json';
  static const _ttl = Duration(minutes: 30);

  List<LiveWallpaper>? _memCache;
  DateTime? _lastFetch;

  /// Limpia el cache (memoria + Hive). Lo dispara el FCM
  /// `catalog_invalidate` y el pull-to-refresh de la tab LIVE.
  Future<void> clearCache() async {
    _memCache = null;
    _lastFetch = null;
    await CatalogCacheStore.instance.clear(_cacheKey);
  }

  /// Cold-start optimization: lee el cache Hive antes de runApp() y popula
  /// memoria. Resultado: la tab LIVE arranca con data al instante.
  /// Idempotente. Silencioso ante errores.
  Future<void> preloadFromDiskCache() async {
    if (_memCache != null) return;
    try {
      final entry = await CatalogCacheStore.instance.read(_cacheKey);
      if (entry == null) return;
      final list = _parse(entry.body);
      if (list.isEmpty) return;
      _memCache = list;
      // Treat as just fetched so the 30-min TTL starts now; the next call
      // to fetchCatalog() will hit the ETag check rather than full GET.
      _lastFetch = DateTime.now();
      debugPrint('[Pixora] Live catalog preloaded: ${list.length}');
    } catch (e) {
      debugPrint('[Pixora] Live preload failed: $e');
    }
  }

  List<LiveWallpaper> _parse(String body) {
    try {
      final data = json.decode(body) as Map<String, dynamic>;
      final list = (data['wallpapers'] as List<dynamic>?) ?? [];
      final items = list
          .map((e) => LiveWallpaper.fromJson(e as Map<String, dynamic>))
          .toList();
      _sortInPlace(items);
      return items;
    } catch (e) {
      debugPrint('[Pixora] Live catalog parse failed: $e');
      return [];
    }
  }

  void _sortInPlace(List<LiveWallpaper> items) {
    // Newest first. Primary key createdAt; fallback sortOrder DESC.
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
    // Fast path: in-memory cache still warm.
    if (!forceRefresh &&
        _memCache != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _ttl) {
      return _memCache!;
    }
    final url = '${SupabaseConfig.storageBase}/wallpaper-videos/$_catalogFile';
    final result = await CatalogCacheStore.instance.fetchWithCache(
      key: _cacheKey,
      url: url,
      ttl: _ttl,
      forceRefresh: forceRefresh,
    );
    if (result.hasBody) {
      final items = _parse(result.body!);
      if (items.isNotEmpty) {
        _memCache = items;
        _lastFetch = DateTime.now();
        return items;
      }
    }
    return _memCache ?? [];
  }
}
