import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../constants/supabase_config.dart';
import '../../features/stories/data/models/story.dart';
import 'catalog_cache_store.dart';

/// Catálogo de stories. Tier 3 (2026-05-18): migrado a CatalogCacheStore.
class StoryCatalogService {
  StoryCatalogService._();
  static final instance = StoryCatalogService._();

  static const _catalogFile = 'stories_catalog.json';
  static const _cacheKey = 'images:stories_catalog.json';
  static const _ttl = Duration(hours: 6);

  List<Story> _stories = [];
  DateTime? _lastFetch;

  List<Story> get stories => _stories;

  Future<void> clearCache() async {
    _stories = [];
    _lastFetch = null;
    await CatalogCacheStore.instance.clear(_cacheKey);
  }

  bool get _isCacheValid =>
      _lastFetch != null && DateTime.now().difference(_lastFetch!) < _ttl;

  Future<List<Story>> fetchCatalog({bool forceRefresh = false}) async {
    if (_stories.isNotEmpty && _isCacheValid && !forceRefresh) {
      return _stories;
    }
    const url =
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
        _stories = parsed;
        _lastFetch = DateTime.now();
        debugPrint(
            '[Pixora] Stories catalog loaded (${result.source.name}): ${_stories.length}');
        return _stories;
      }
    }
    return _stories;
  }

  List<Story> _parse(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final list = (data['stories'] as List<dynamic>?) ?? [];
      return list
          .map((e) => Story.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Pixora] Stories parse error: $e');
      return [];
    }
  }
}
