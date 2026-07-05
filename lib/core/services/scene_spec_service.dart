import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../utils/connectivity.dart';
import 'capability_registry.dart';
import 'catalog_index_service.dart';
import 'sprite_download_service.dart';

/// Lazily fetches per-scene JSON specs from Supabase. Specs are cached in
/// filesDir indefinitely — only invalidated when the catalog index version
/// bumps (signalling that any scene MAY have changed).
///
/// Use after the user taps a wallpaper preview, before invoking the apply
/// flow that needs the full spec (background URL, sprite list, uniforms).
class SceneSpecService {
  SceneSpecService._();
  static final instance = SceneSpecService._();

  static const _cacheDir = 'scene_specs';
  // In-memory parsed cache keyed by scene id.
  final Map<String, Map<String, dynamic>> _memCache = {};

  Future<Directory> _diskDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/$_cacheDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _diskFile(String id) async {
    final dir = await _diskDir();
    return File('${dir.path}/$id.json');
  }

  /// Fetch the spec for one scene by index entry. Returns null on failure
  /// (no internet AND no cache, or unsupported vocabulary in the spec).
  Future<Map<String, dynamic>?> fetch(CatalogIndexEntry entry) async {
    if (entry.specUrl == null || entry.specUrl!.isEmpty) {
      debugPrint('[SceneSpec] ${entry.id}: no spec_url in index');
      return null;
    }
    final cached = _memCache[entry.id];
    if (cached != null) {
      // Spec may be cached while image_layers are still missing on disk
      // (e.g. FCM refresh wrote JSON but layer download failed). Always
      // reconcile layers before the native engine reads filesDir.
      await _fetchImageLayers(entry.id, cached);
      return cached;
    }

    // Try disk
    final f = await _diskFile(entry.id);
    if (f.existsSync()) {
      try {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (CapabilityRegistry.sceneSpecValid(json)) {
          _memCache[entry.id] = json;
          await _fetchImageLayers(entry.id, json);
          // Background refresh check (don't block)
          unawaited(_refreshIfStale(entry, f.lastModifiedSync()));
          return json;
        } else {
          debugPrint('[SceneSpec] ${entry.id}: cached spec has unknown vocab');
        }
      } catch (e) {
        debugPrint('[SceneSpec] ${entry.id} disk read error: $e');
      }
    }

    return _fetchAndCache(entry);
  }

  /// Force-fetch one spec, bypassing cache.
  Future<Map<String, dynamic>?> refresh(CatalogIndexEntry entry) async {
    _memCache.remove(entry.id);
    return _fetchAndCache(entry);
  }

  /// Drop disk + memory cache (e.g. after sign-out, FCM invalidate, or
  /// debugging). Wipes BOTH scene_specs/ and scene_layers/ so the next
  /// apply re-downloads fresh JSON + layer bitmaps from Supabase. This is
  /// what makes remote-only edits (bob amplitude, position, scale) reach
  /// users without an app update.
  Future<void> clearCache() async {
    _memCache.clear();
    try {
      final dir = await _diskDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('[SceneSpec] specs cache clear error: $e');
    }
    try {
      final support = await getApplicationSupportDirectory();
      final layers = Directory('${support.path}/scene_layers');
      if (await layers.exists()) await layers.delete(recursive: true);
    } catch (e) {
      debugPrint('[SceneSpec] layers cache clear error: $e');
    }
  }

  /// Re-download every canvas_scene spec (and layers/sprites). Used after
  /// FCM catalog invalidation so the live wallpaper keeps working — wiping
  /// scene_specs/ without an immediate re-fetch leaves the :wallpaper process
  /// with no spec until the user re-applies manually.
  Future<void> refreshAllCanvasScenes() async {
    if (!await Connectivity.hasInternet()) {
      debugPrint('[SceneSpec] refreshAllCanvasScenes: offline, skip');
      return;
    }
    try {
      await CatalogIndexService.instance.refresh();
      final items = await CatalogIndexService.instance.ofType('canvas_scene');
      for (final entry in items) {
        _memCache.remove(entry.id);
        await _fetchAndCache(entry);
      }
      debugPrint(
          '[SceneSpec] refreshAllCanvasScenes: ${items.length} scenes updated');
    } catch (e) {
      debugPrint('[SceneSpec] refreshAllCanvasScenes error: $e');
    }
  }

  /// Drop just one entry (e.g. when index version bumps and you know
  /// this specific scene was updated).
  Future<void> evict(String id) async {
    _memCache.remove(id);
    try {
      final f = await _diskFile(id);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  // ── Internals ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _fetchAndCache(CatalogIndexEntry entry) async {
    if (!await Connectivity.hasInternet()) {
      debugPrint('[SceneSpec] ${entry.id}: offline, no fetch');
      return null;
    }
    try {
      final r = await http
          .get(Uri.parse(entry.specUrl!))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        debugPrint('[SceneSpec] ${entry.id}: HTTP ${r.statusCode}');
        return null;
      }
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      if (!CapabilityRegistry.sceneSpecValid(json)) {
        debugPrint('[SceneSpec] ${entry.id}: spec contains unknown vocab');
        return null;
      }
      _memCache[entry.id] = json;
      try {
        final f = await _diskFile(entry.id);
        await f.writeAsString(r.body);
      } catch (e) {
        debugPrint('[SceneSpec] ${entry.id}: disk write failed: $e');
      }
      // Also fetch any parallax image_layers and cache them so the native
      // CanvasSceneRenderer can read them from filesDir/scene_layers/<id>/<key>.webp
      await _fetchImageLayers(entry.id, json);
      // Auto-download sprite folders declared by `manifest_key` in the spec.
      // This makes new canvas_scene wallpapers ship without bumping any
      // hardcoded list in SpriteDownloadService — the spec is the truth.
      try {
        await SpriteDownloadService.instance.ensureSpritesForScene(json);
      } catch (e) {
        debugPrint('[SceneSpec] ${entry.id}: sprite download error $e');
      }
      debugPrint(
          '[SceneSpec] ${entry.id}: cached (${r.bodyBytes.length} bytes)');
      return json;
    } catch (e) {
      debugPrint('[SceneSpec] ${entry.id}: fetch error $e');
      return null;
    }
  }

  /// Download each image_layer URL referenced in the spec to
  /// filesDir/scene_layers/<sceneId>/<key>.webp. Native side reads these
  /// directly via BitmapFactory.
  ///
  /// v1.7.43 fix: _meta.json stores {url, size} per layer. Re-download when
  /// the remote Content-Length differs from cached size OR local file size —
  /// same URL with a replaced Supabase object now reaches users without _vN
  /// suffix churn.
  Future<void> _fetchImageLayers(
      String sceneId, Map<String, dynamic> spec) async {
    final layers = spec['image_layers'];
    if (layers is! List || layers.isEmpty) return;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/scene_layers/$sceneId');
      await dir.create(recursive: true);

      final metaFile = File('${dir.path}/_meta.json');
      Map<String, dynamic> meta = {};
      if (metaFile.existsSync()) {
        try {
          meta =
              jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        } catch (_) {
          meta = {};
        }
      }

      bool metaChanged = false;
      for (final l in layers) {
        if (l is! Map) continue;
        final key = l['key'] as String?;
        final url = l['url'] as String?;
        if (key == null || url == null) continue;
        final specRevision = (l['revision'] as num?)?.toInt() ?? 0;
        final out = File('${dir.path}/$key.webp');
        final fileFresh = out.existsSync() && out.lengthSync() > 1024;
        final entry = meta[key];
        final cachedUrl =
            entry is Map ? entry['url'] as String? : entry as String?;
        final cachedSize = entry is Map ? entry['size'] as int? : null;
        final cachedRevision =
            entry is Map ? (entry['revision'] as num?)?.toInt() : null;
        final localSize = fileFresh ? out.lengthSync() : 0;
        final revisionMatch =
            cachedRevision != null && cachedRevision == specRevision;

        if (fileFresh &&
            cachedUrl == url &&
            revisionMatch &&
            specRevision > 0) {
          continue;
        }

        if (fileFresh && cachedUrl == url) {
          final remoteSize = await _remoteContentLength(url);
          if (remoteSize != null &&
              remoteSize == cachedSize &&
              remoteSize == localSize &&
              revisionMatch) {
            continue;
          }
          if (remoteSize == null &&
              cachedSize != null &&
              cachedSize == localSize &&
              revisionMatch) {
            continue;
          }
        }

        try {
          final r = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 30));
          if (r.statusCode == 200 && r.bodyBytes.length > 1024) {
            await out.writeAsBytes(r.bodyBytes);
            meta[key] = {
              'url': url,
              'size': r.bodyBytes.length,
              if (specRevision > 0) 'revision': specRevision,
            };
            metaChanged = true;
            final reason = !fileFresh
                ? 'first fetch'
                : cachedUrl != url
                    ? 'URL changed'
                    : !revisionMatch
                        ? 'revision $specRevision'
                        : 'remote size changed';
            debugPrint(
                '[SceneSpec] $sceneId/$key: $reason, ${r.bodyBytes.length} bytes');
          }
        } catch (e) {
          debugPrint('[SceneSpec] $sceneId/$key: layer fetch error $e');
        }
      }
      if (metaChanged) {
        try {
          await metaFile.writeAsString(jsonEncode(meta));
        } catch (e) {
          debugPrint('[SceneSpec] $sceneId: meta write failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[SceneSpec] $sceneId: image_layers cache dir error $e');
    }
  }

  /// HEAD Content-Length for remote asset staleness checks.
  Future<int?> _remoteContentLength(String url) async {
    try {
      final r =
          await http.head(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (r.statusCode < 200 || r.statusCode >= 300) return null;
      final len = r.contentLength;
      return (len != null && len > 0) ? len : null;
    } catch (_) {
      return null;
    }
  }

  /// Re-fetch in background if disk copy is older than the stale window.
  /// 2026-07-04 — window reduced from 7 days to 5 minutes because the
  /// old value made spec edits from the sprite editor invisible until
  /// FCM push arrived (and FCM occasionally fails on Google-side SSL
  /// issues). With 5 minutes, any edit becomes visible on the next open
  /// of the wallpaper, without requiring the user to force-clear cache.
  /// Trade-off: slightly more network requests on frequent app opens,
  /// but each request is a small JSON (~1-3 KB) so the cost is minimal.
  Future<void> _refreshIfStale(
      CatalogIndexEntry entry, DateTime savedAt) async {
    if (DateTime.now().difference(savedAt) < const Duration(minutes: 5)) return;
    if (!await Connectivity.hasInternet()) return;
    await _fetchAndCache(entry);
  }
}
