import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

/// Hive-backed cache store for content catalogs (live wallpapers, stories,
/// day cycle themes, ringtones, events…).
///
/// Replaces the previous "raw JSON file in app docs dir" pattern with a
/// single Hive box (`catalog_cache_v1`) keyed by a stable identifier per
/// catalog. Each entry stores the raw JSON body, the HTTP `ETag` reported
/// by Supabase Storage, and the `savedAt` timestamp.
///
/// Why ETag: Supabase Storage already returns a strong ETag header on every
/// public object. Doing a cheap `HEAD` request and comparing the remote
/// ETag against the cached one lets us:
///   1. Skip the full JSON download (~50-180 KB per catalog) when nothing
///      changed — typical case during the 6h TTL window.
///   2. Detect server-side changes ASAP without bumping the TTL down to a
///      few minutes (which would explode bandwidth on idle users).
///
/// Combined with the FCM `catalog_invalidate` push (see
/// PushNotificationService), this enables “publish from dashboard → users
/// see the new content on next refresh / app resume” without 6h waits.
class CatalogCacheStore {
  CatalogCacheStore._();
  static final CatalogCacheStore instance = CatalogCacheStore._();

  static const String _boxName = 'catalog_cache_v1';
  Box<Map>? _box;

  /// Idempotent. Safe to call from main.dart after Hive.initFlutter().
  /// Subsequent reads/writes that race against initialize() will wait via
  /// _ensureBox().
  Future<void> initialize() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox<Map>(_boxName);
      debugPrint('[CatalogCache] box opened — ${_box!.length} entries');
    } catch (e) {
      debugPrint('[CatalogCache] init failed: $e');
    }
  }

  Future<Box<Map>?> _ensureBox() async {
    if (_box != null && _box!.isOpen) return _box;
    await initialize();
    return _box;
  }

  /// Read the cached entry for [key]. Returns null when absent or on error.
  Future<CacheEntry?> read(String key) async {
    final box = await _ensureBox();
    if (box == null) return null;
    final raw = box.get(key);
    if (raw == null) return null;
    try {
      return CacheEntry(
        body: raw['body'] as String,
        etag: raw['etag'] as String?,
        savedAt: DateTime.fromMillisecondsSinceEpoch(raw['savedAt'] as int),
      );
    } catch (e) {
      debugPrint('[CatalogCache] read malformed entry for $key: $e');
      return null;
    }
  }

  /// Persist a cache entry. Safe to call repeatedly — overwrites.
  Future<void> write(String key, String body, String? etag) async {
    final box = await _ensureBox();
    if (box == null) return;
    await box.put(key, {
      'body': body,
      'etag': etag,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Clear a single entry. Use when a FCM `catalog_invalidate` push arrives
  /// or when the user pulls to refresh and we want to force a redownload.
  Future<void> clear(String key) async {
    final box = await _ensureBox();
    if (box == null) return;
    await box.delete(key);
  }

  /// Nuclear: drop the whole box. Only used by debug/diagnostics screens.
  Future<void> clearAll() async {
    final box = await _ensureBox();
    if (box == null) return;
    await box.clear();
  }

  /// Cheap `HEAD` request → return the server ETag, or null on any failure.
  /// Times out fast (4s) so it doesn’t add perceptible latency on slow nets.
  Future<String?> remoteEtag(String url) async {
    try {
      final res =
          await http.head(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        return res.headers['etag'];
      }
    } catch (e) {
      debugPrint('[CatalogCache] HEAD $url failed: $e');
    }
    return null;
  }

  /// High-level helper used by individual catalog services. Implements the
  /// full Hive + ETag flow so services don’t have to repeat it.
  ///
  /// Decision tree:
  ///   1. forceRefresh=true → skip cache, full GET.
  ///   2. cache absent → full GET.
  ///   3. cache present and fresh (within [ttl]) → return cache.
  ///   4. cache present but stale → HEAD; if remote ETag matches, refresh
  ///      savedAt and return cache; otherwise full GET.
  ///   5. Network failure anywhere → fall back to cache (even if stale)
  ///      rather than returning empty.
  ///
  /// [key] should be globally unique per catalog (e.g.
  /// `wallpaper-videos:live_wallpaper_catalog.json`).
  Future<CacheFetchResult> fetchWithCache({
    required String key,
    required String url,
    required Duration ttl,
    bool forceRefresh = false,
  }) async {
    final cached = await read(key);
    final now = DateTime.now();
    final fresh =
        cached != null && now.difference(cached.savedAt) < ttl && !forceRefresh;
    if (fresh) {
      return CacheFetchResult(
        body: cached.body,
        source: CacheSource.memoryFresh,
      );
    }

    // Cache is stale or missing — try ETag check first when we have one.
    if (cached?.etag != null && !forceRefresh) {
      final remote = await remoteEtag(url);
      if (remote != null && remote == cached!.etag) {
        // Server hasn’t changed — refresh savedAt and return cache.
        await write(key, cached.body, cached.etag);
        return CacheFetchResult(
          body: cached.body,
          source: CacheSource.etagMatched,
        );
      }
    }

    // Either no ETag to compare, or it differs — do the full GET.
    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final etag = res.headers['etag'];
        await write(key, res.body, etag);
        return CacheFetchResult(
          body: res.body,
          source: CacheSource.network,
          etag: etag,
        );
      }
      debugPrint('[CatalogCache] GET $url → ${res.statusCode}');
    } catch (e) {
      debugPrint('[CatalogCache] GET $url failed: $e');
    }

    // Network failed — fall back to cache even if stale.
    if (cached != null) {
      return CacheFetchResult(
        body: cached.body,
        source: CacheSource.networkFailedFallback,
      );
    }
    // No cache, no network — caller decides what to do.
    return const CacheFetchResult(body: null, source: CacheSource.empty);
  }
}

class CacheEntry {
  CacheEntry({required this.body, required this.etag, required this.savedAt});
  final String body;
  final String? etag;
  final DateTime savedAt;
}

enum CacheSource {
  /// Returned from the in-memory/Hive cache because the TTL hadn’t expired.
  memoryFresh,

  /// Cache was stale but a HEAD request confirmed the server ETag still
  /// matches what we have — no body download needed.
  etagMatched,

  /// Full GET hit the network and (re)populated the cache.
  network,

  /// Network call failed; returning the previously-cached body (stale).
  networkFailedFallback,

  /// No cache and no network — caller gets a null body.
  empty,
}

class CacheFetchResult {
  const CacheFetchResult({
    required this.body,
    required this.source,
    this.etag,
  });
  final String? body;
  final CacheSource source;
  final String? etag;

  bool get hasBody => body != null;
}
