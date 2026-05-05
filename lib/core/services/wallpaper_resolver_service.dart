import 'package:flutter/foundation.dart';
import '../models/resolved_wallpaper.dart';
import '../../features/wallpapers/data/models/wallpaper.dart';
import '../../features/hot_wallpapers/data/models/live_wallpaper.dart';
import 'catalog_index_service.dart';
import 'catalog_service.dart';
import 'live_wallpaper_catalog_service.dart';

/// Resolves wallpaper IDs across all three Pixora catalogs into a unified
/// `ResolvedWallpaper` object. Used by sections that display heterogeneous
/// collections (Events, Search, Recommendations) where one ID may live in:
///
///   - dynamic_catalog (Postgres `wallpapers` table) → static / panoramic
///   - live_wallpaper_catalog.json                   → video / explore
///   - catalog_index.json                            → canvas_scene
///
/// Lookups are cached in-memory so repeated calls during a single session
/// are O(1) per id.
class WallpaperResolverService {
  WallpaperResolverService._();
  static final instance = WallpaperResolverService._();

  // Per-catalog caches. Each is built lazily on first lookup.
  Map<String, Wallpaper>? _staticIndex;
  Map<String, LiveWallpaper>? _liveIndex;
  // catalog_index entries already cache themselves inside CatalogIndexService.

  /// Resolve a single id. Returns null if not found in any catalog.
  Future<ResolvedWallpaper?> resolve(String id) async {
    // 1. Static / panoramic catalog (Postgres-backed)
    final staticHit = await _findStatic(id);
    if (staticHit != null) {
      return ResolvedWallpaper(
        id: staticHit.id,
        name: staticHit.name,
        previewUrl: staticHit.previewUrl,
        kind: staticHit.isPanoramic
            ? WallpaperKind.panoramic
            : WallpaperKind.staticImage,
        raw: staticHit,
      );
    }

    // 2. Live wallpaper catalog (JSON)
    final liveHit = await _findLive(id);
    if (liveHit != null) {
      return ResolvedWallpaper(
        id: liveHit.id,
        name: liveHit.name,
        previewUrl: liveHit.previewUrl,
        kind: WallpaperKind.liveVideo,
        raw: liveHit,
      );
    }

    // 3. Canvas scene catalog (JSON)
    final sceneHit = await CatalogIndexService.instance.findById(id);
    if (sceneHit != null && sceneHit.type == 'canvas_scene') {
      return ResolvedWallpaper(
        id: sceneHit.id,
        name: sceneHit.titleFor('es'),
        previewUrl: sceneHit.previewUrl,
        kind: WallpaperKind.canvasScene,
        raw: sceneHit,
      );
    }

    debugPrint('[WallpaperResolver] not found: $id');
    return null;
  }

  /// Resolve many ids at once. Skips ids that don't resolve. Order preserved.
  Future<List<ResolvedWallpaper>> resolveMany(List<String> ids) async {
    final out = <ResolvedWallpaper>[];
    for (final id in ids) {
      final r = await resolve(id);
      if (r != null) out.add(r);
    }
    return out;
  }

  /// Drop in-memory caches. Useful after sign-in / sign-out or admin refresh.
  void clearCache() {
    _staticIndex = null;
    _liveIndex = null;
  }

  // ── Internals ──────────────────────────────────────────────────────

  Future<Wallpaper?> _findStatic(String id) async {
    if (_staticIndex == null) {
      try {
        final all = await CatalogService.instance.fetchCatalog();
        _staticIndex = {for (final w in all) w.id: w};
      } catch (e) {
        debugPrint('[WallpaperResolver] static catalog fetch error: $e');
        _staticIndex = const {};
      }
    }
    return _staticIndex![id];
  }

  Future<LiveWallpaper?> _findLive(String id) async {
    if (_liveIndex == null) {
      try {
        final all = await LiveWallpaperCatalogService.instance.fetchCatalog();
        _liveIndex = {for (final w in all) w.id: w};
      } catch (e) {
        debugPrint('[WallpaperResolver] live catalog fetch error: $e');
        _liveIndex = const {};
      }
    }
    return _liveIndex![id];
  }
}
