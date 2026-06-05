import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../constants/supabase_config.dart';
import '../../features/realm/data/realm_catalog.dart';
import '../../features/realm/data/realm_shader.dart';
import 'catalog_cache_store.dart';

/// REALM shader catalog — mirrors the live/stories/day_cycle pattern:
/// in-memory cache + Hive ETag check + FCM `realm` invalidation.
///
/// Falls back to the hardcoded [RealmCatalog.all] when Supabase is
/// unreachable AND no Hive cache exists (cold start / first run with no
/// network). This guarantees the REALM tab always renders something —
/// the in-code list is the safety net for "the catalog will never be
/// empty" rather than the source of truth.
class RealmCatalogService {
  RealmCatalogService._();
  static final instance = RealmCatalogService._();

  static const _catalogFile = 'realm_catalog.json';
  static const _cacheKey = 'wallpaper-shaders:realm_catalog.json';
  static const _ttl = Duration(minutes: 30);

  List<RealmShader>? _memCache;
  DateTime? _lastFetch;

  /// Drop the in-memory + Hive cache. Triggered by FCM `realm` scope and
  /// by the pull-to-refresh on the REALM grid.
  Future<void> clearCache() async {
    _memCache = null;
    _lastFetch = null;
    await CatalogCacheStore.instance.clear(_cacheKey);
  }

  /// Read Hive cache on cold start so the REALM tab renders instantly
  /// without a network round-trip. Idempotent.
  Future<void> preloadFromDiskCache() async {
    if (_memCache != null) return;
    try {
      final entry = await CatalogCacheStore.instance.read(_cacheKey);
      if (entry == null) return;
      final list = _parse(entry.body);
      if (list.isEmpty) return;
      _memCache = list;
      _lastFetch = DateTime.now();
      debugPrint('[Pixora] Realm catalog preloaded: ${list.length}');
    } catch (e) {
      debugPrint('[Pixora] Realm preload failed: $e');
    }
  }

  List<RealmShader> _parse(String body) {
    try {
      final data = json.decode(body) as Map<String, dynamic>;
      final list = (data['shaders'] as List<dynamic>?) ?? [];
      return list
          .map((e) => RealmShader.fromJson(e as Map<String, dynamic>))
          .whereType<RealmShader>()
          .toList();
    } catch (e) {
      debugPrint('[Pixora] Realm catalog parse failed: $e');
      return [];
    }
  }

  Future<List<RealmShader>> fetchCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _memCache != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _ttl) {
      return _memCache!;
    }
    const url = '${SupabaseConfig.storageBase}/wallpaper-shaders/$_catalogFile';
    try {
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
    } catch (e) {
      debugPrint('[Pixora] Realm catalog fetch failed: $e');
    }
    // Safety net: hardcoded list. Guarantees REALM tab never goes blank
    // even on first install with no network.
    if (_memCache == null) {
      _memCache = RealmCatalog.all;
      _lastFetch = DateTime.now();
    }
    return _memCache ?? RealmCatalog.all;
  }
}
