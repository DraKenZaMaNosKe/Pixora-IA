import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../constants/supabase_config.dart';
import '../../features/day_cycle/data/models/day_cycle_theme.dart';
import 'catalog_cache_store.dart';

/// Catálogo de Day Cycle themes. Tier 3 (2026-05-18): migrado a
/// CatalogCacheStore.
class DayCycleCatalogService {
  DayCycleCatalogService._();
  static final instance = DayCycleCatalogService._();

  static const _catalogFile = 'day_cycle_catalog.json';
  static const _cacheKey = 'images:day_cycle_catalog.json';
  static const _ttl = Duration(hours: 6);

  List<DayCycleTheme> _themes = [];
  DateTime? _lastFetch;

  Future<void> clearCache() async {
    _themes = [];
    _lastFetch = null;
    await CatalogCacheStore.instance.clear(_cacheKey);
  }

  bool get _isCacheValid =>
      _lastFetch != null && DateTime.now().difference(_lastFetch!) < _ttl;

  Future<List<DayCycleTheme>> fetchCatalog({bool forceRefresh = false}) async {
    if (_themes.isNotEmpty && _isCacheValid && !forceRefresh) return _themes;
    final url =
        '${SupabaseConfig.storageBase}/${SupabaseConfig.imagesBucket}/$_catalogFile';
    final result = await CatalogCacheStore.instance.fetchWithCache(
      key: _cacheKey,
      url: url,
      ttl: _ttl,
      forceRefresh: forceRefresh,
    );
    if (result.hasBody) {
      final parsed = _parse(result.body!);
      if (parsed.isNotEmpty) {
        _themes = parsed;
        _lastFetch = DateTime.now();
        debugPrint(
            '[Pixora] Day cycle catalog loaded (${result.source.name}): ${_themes.length}');
        return _themes;
      }
    }
    return _themes;
  }

  List<DayCycleTheme> _parse(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final list = (data['themes'] as List<dynamic>?) ?? [];
      return list
          .map((e) => DayCycleTheme.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Pixora] Day cycle parse error: $e');
      return [];
    }
  }
}
