import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'catalog_index_service.dart';
import 'catalog_service.dart';
import 'scene_spec_service.dart';
import 'wallpaper_engine_coordinator.dart';

/// Service for auto-rotating wallpapers at configurable intervals.
///
/// Sends catalog data to native Android where AutoRotateWorker handles:
/// - Random selection (avoids last 5)
/// - Download with temp files (crash-safe)
/// - Max 10 cached wallpapers
/// - Disk space checks
/// - Offline fallback to cached wallpaper
/// - Pre-downloads next wallpaper
class AutoRotateService {
  AutoRotateService._();
  static final instance = AutoRotateService._();

  static const _channel = MethodChannel('com.orbix.pixora/wallpaper');

  /// Max canvas_scene wallpapers pulled into a Daily rotation (2026-07-07).
  /// Scenes carry sprites + layers (~3-12 MB each), so this caps disk use.
  static const kMaxDailyScenes = 6;

  /// Marker suffix mirrored from PixoraWallpaperService.SCENE_MARKER_SUFFIX.
  /// A cached file "<sceneId>__scene.webp" tells the native rotation to write
  /// scene_id (parallax scene) instead of a plain image path.
  static const _sceneMarkerSuffix = '__scene.webp';

  /// Start auto-rotating wallpapers.
  /// [intervalMinutes] - time between changes (default 5)
  /// [target] - 0=Home, 1=Lock, 2=Both
  /// [category] - filter by category (null = all)
  /// Engine that was preempted by the most recent successful `start()` call,
  /// or [WallpaperEngine.none] if nothing was running. UI reads this once
  /// after start to optionally show "Pixora Daily reemplazó a Day Cycle".
  WallpaperEngine lastPreempted = WallpaperEngine.none;

  Future<bool> start({
    int intervalMinutes = 5,
    int target = 2,
    String? category,
  }) async {
    if (!Platform.isAndroid) return false;

    try {
      // Request microphone permission so the equalizer visualizer renders
      // audio waveform on the rotating wallpapers. The wallpaper apply flow
      // through WallpaperPreviewPage already does this, but AutoRotate runs
      // entirely in background and never goes through the preview — without
      // this request the visualizer stays silent for every rotated wallpaper.
      // .request() is idempotent and shows the system dialog only if the
      // permission is in an undetermined state; a denial doesn't block the
      // rotation (the visualizer just degrades silently).
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        debugPrint(
            '[AutoRotate] Microphone not granted — visualizer will be muted');
      }

      // Mutex: stop competing engines (DayCycle / Story) before claiming
      // the wallpaper Surface. Otherwise multiple engines fight for it.
      lastPreempted = await WallpaperEngineCoordinator.instance.claim(
        WallpaperEngine.pixoraDaily,
        context: category,
      );

      // 2026-06-10 product decision (Eduardo) — plain Daily categories rotate
      // ONLY static + panoramic (never live videos): the canvas↔video Surface
      // transition caused the 3 v1.7.19 crashes, so Daily never touches videos.
      //
      // 2026-07-07 — canvas_scene categories (SCENES_3D, AMOR) DO rotate
      // parallax scenes, which is SAFE because scenes render on Canvas (not
      // MediaPlayer) — Canvas↔Canvas needs no process kill. _buildCatalogData
      // handles both cases; scenes get a "<id>__scene.webp" marker prefetched
      // by Dart (spec + layers + sprites) after native start().
      final built = await _buildCatalogData(category);
      final catalogData = built.data;

      if (catalogData.isEmpty) {
        debugPrint('[AutoRotate] No wallpapers for category: $category');
        return false;
      }

      final result = await _channel.invokeMethod<bool>(
        'startAutoRotate',
        {
          'catalogData': catalogData,
          'intervalMinutes': intervalMinutes,
          'target': target,
          if (category != null) 'category': category,
        },
      );

      // Prefetch scene markers AFTER native start() — start() may clear the
      // cache on category change, so markers must be written afterwards.
      if (built.scenes.isNotEmpty) {
        unawaited(_prefetchSceneMarkers(built.scenes));
      }

      debugPrint(
          '[AutoRotate] Started: ${catalogData.length} items (${built.scenes.length} scenes), ${intervalMinutes}min');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[AutoRotate] Start error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[AutoRotate] Start error: $e');
      return false;
    }
  }

  /// Stop auto-rotating wallpapers.
  Future<bool> stop() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('stopAutoRotate');
      await WallpaperEngineCoordinator.instance
          .release(WallpaperEngine.pixoraDaily);
      debugPrint('[AutoRotate] Stopped');
      return result ?? false;
    } catch (e) {
      debugPrint('[AutoRotate] Stop error: $e');
      return false;
    }
  }

  /// Future-proofing: re-fetch the static + live catalogs and push them to
  /// native if Daily is currently active. Lets new wallpapers added to the
  /// Supabase catalogs flow into the user's Daily rotation without the user
  /// having to toggle it off/on. Call from app cold-start (main.dart) and
  /// optionally on resume after a long pause.
  ///
  /// Cheap no-op if Daily isn't running. Idempotent — running twice in a row
  /// just re-syncs the same catalog snapshot.
  ///
  /// 2026-06-10 bug fix: MUST use the silent `updateAutoRotateCatalog` native
  /// path, NOT `start()`. If Android tumbled Pixora out of being the live
  /// wallpaper (e.g. after a `:wallpaper` process crash), `start()` re-runs
  /// `ensureLiveWallpaperActive()` which detects "Pixora not active" and
  /// shows the system live-wallpaper picker on every single cold start —
  /// confusing the user with a forced picker they never asked for. The
  /// silent path only refreshes the catalog prefs the prefetch worker reads,
  /// without touching the wallpaper component or surfaces.
  Future<bool> refreshIfRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      final status = await getStatus();
      if (status['enabled'] != true) return false;
      final intervalMinutes = (status['intervalMinutes'] as int?) ?? 5;
      final target = (status['target'] as int?) ?? 2;
      final category = status['category'] as String?;

      // Build the same catalog data start() would, but DON'T call start().
      // Same helper → scene categories flow into the running rotation on cold
      // start (and re-create swept scene markers) just like static ones.
      final built = await _buildCatalogData(category);
      final catalogData = built.data;

      if (catalogData.isEmpty) {
        debugPrint('[AutoRotate] Refresh: empty filtered catalog, skipping');
        return false;
      }

      debugPrint(
          '[AutoRotate] Refresh: silent catalog update (${catalogData.length} entries, ${built.scenes.length} scenes, cat=$category)');
      final result = await _channel.invokeMethod<bool>(
        'updateAutoRotateCatalog',
        {
          'catalogData': catalogData,
          'intervalMinutes': intervalMinutes,
          'target': target,
          if (category != null) 'category': category,
        },
      );

      // Re-prefetch scene markers (idempotent; regenerates any swept by FCM).
      if (built.scenes.isNotEmpty) {
        unawaited(_prefetchSceneMarkers(built.scenes));
      }
      return result ?? false;
    } catch (e) {
      debugPrint('[AutoRotate] refreshIfRunning error: $e');
      return false;
    }
  }

  /// Builds the native wire catalog ("id|file|glow|type") for a category and
  /// returns it alongside the scene entries that need marker prefetch.
  ///
  /// - SCENES_3D: every canvas_scene (3D parallax).
  /// - AMOR: canvas_scene tagged 'amor' + static wallpapers tagged 'amor'.
  /// - Everything else: unchanged static/panoramic behavior (2026-06-10).
  ///
  /// Scene entries emit a "scene" type + a "<id>__scene.webp" marker file
  /// (written later by _prefetchSceneMarkers). The native worker skips
  /// downloading them; Dart owns scene downloads via SceneSpecService.
  Future<({List<String> data, List<CatalogIndexEntry> scenes})>
      _buildCatalogData(String? category) async {
    if (category == 'SCENES_3D' || category == 'AMOR') {
      final index = await CatalogIndexService.instance.getItems();
      // Shuffle BEFORE take so every user gets a DIFFERENT random subset of
      // scenes (not the same first N). Combined with the native randomOrNull
      // rotation + per-device seen-tracking, no two users share the same order.
      final scenes = (index
              .where((e) =>
                  e.type == 'canvas_scene' &&
                  (category == 'SCENES_3D' ||
                      e.tags.map((t) => t.toLowerCase()).contains('amor')))
              .toList()
            ..shuffle())
          .take(kMaxDailyScenes)
          .toList();
      final data = <String>[
        for (final e in scenes)
          '${e.id}|${e.id}$_sceneMarkerSuffix|'
              '${(e.raw['glow_color'] as String?) ?? '#C9A650'}|scene',
      ];
      // AMOR also mixes in static amor wallpapers (sunsets, silhouettes…).
      if (category == 'AMOR') {
        final catalog = await CatalogService.instance.fetchCatalog();
        for (final w in catalog.where(
            (w) => w.tags.map((t) => t.toLowerCase()).contains('amor'))) {
          data.add('${w.id}|${w.imageFile}|${w.glowColor}|static');
        }
      }
      return (data: data, scenes: scenes);
    }

    // Plain categories — unchanged static/panoramic behavior.
    final catalog = await CatalogService.instance.fetchCatalog();
    final filtered = category == 'DAILY'
        ? catalog.where((w) => w.dailyEligible).toList()
        : (category != null
            ? catalog.where((w) => w.category == category).toList()
            : catalog);
    final data = filtered
        .map((w) => '${w.id}|${w.imageFile}|${w.glowColor}|static')
        .toList();
    return (data: data, scenes: const <CatalogIndexEntry>[]);
  }

  /// Downloads scene content (spec + layers + sprites) via SceneSpecService
  /// and writes a flat marker "<id>__scene.webp" into auto_rotate_cache/ so the
  /// in-service rotation can pick it. The marker is the composited flat image
  /// (image_url) so it doubles as a COMPLETE visual fallback (with the subject)
  /// if the scene spec/assets ever go missing. Atomic tmp→rename. A scene only
  /// enters the pool once fully downloaded — fire-and-forget, failures skip it.
  Future<void> _prefetchSceneMarkers(List<CatalogIndexEntry> scenes) async {
    if (scenes.isEmpty) return;
    try {
      final support = await getApplicationSupportDirectory();
      final cacheDir = Directory('${support.path}/auto_rotate_cache');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

      for (final entry in scenes) {
        try {
          // 1. Ensure spec + image_layers + sprites are on disk.
          final spec = await SceneSpecService.instance.fetch(entry);
          if (spec == null) {
            debugPrint(
                '[AutoRotate] scene ${entry.id}: spec failed, no marker');
            continue;
          }
          // 2. Marker = composited flat so the fallback shows the subject.
          final bg = spec['background'];
          final flatUrl = (entry.raw['image_url'] as String?) ??
              (bg is Map ? bg['url'] as String? : null);
          if (flatUrl == null || flatUrl.isEmpty) {
            debugPrint(
                '[AutoRotate] scene ${entry.id}: no flat url, no marker');
            continue;
          }
          final marker =
              File('${cacheDir.path}/${entry.id}$_sceneMarkerSuffix');
          if (await marker.exists() && await marker.length() > 1024) {
            continue; // already prefetched
          }
          final r = await http
              .get(Uri.parse(flatUrl))
              .timeout(const Duration(seconds: 30));
          if (r.statusCode != 200 || r.bodyBytes.length <= 1024) {
            debugPrint(
                '[AutoRotate] scene ${entry.id}: flat HTTP ${r.statusCode}');
            continue;
          }
          final tmp = File('${marker.path}.tmp');
          await tmp.writeAsBytes(r.bodyBytes);
          await tmp.rename(marker.path);
          debugPrint('[AutoRotate] scene marker ready: ${entry.id}');
        } catch (e) {
          debugPrint('[AutoRotate] scene ${entry.id} prefetch error: $e');
        }
      }
    } catch (e) {
      debugPrint('[AutoRotate] _prefetchSceneMarkers error: $e');
    }
  }

  /// Get current status of auto-rotate.
  Future<Map<String, dynamic>> getStatus() async {
    if (!Platform.isAndroid) return {'enabled': false};
    try {
      final result = await _channel.invokeMethod<Map>('getAutoRotateStatus');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('[AutoRotate] Status error: $e');
      return {'enabled': false};
    }
  }

  /// Clear auto-rotate cache.
  Future<void> clearCache() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('clearAutoRotateCache');
    } catch (e) {
      debugPrint('[AutoRotate] Clear cache error: $e');
    }
  }

  /// True si Pixora sigue siendo el live wallpaper activo del sistema.
  /// La rotación in-service (Pixora Daily) SOLO funciona si esto es true;
  /// si el usuario o Samsung revirtió el wallpaper, la rotación no corre.
  Future<bool> isPixoraLiveActive() async {
    if (!Platform.isAndroid) return false;
    try {
      final active = await _channel.invokeMethod<bool>('isPixoraLiveActive');
      return active ?? false;
    } catch (e) {
      debugPrint('[AutoRotate] isPixoraLiveActive error: $e');
      return false;
    }
  }

  /// Abre el picker del sistema para re-activar PixoraWallpaperService como
  /// live wallpaper. Usado cuando se detecta que el componente se perdió pero
  /// Daily sigue habilitado (red de seguridad — Fase 3).
  Future<void> reactivateLiveWallpaper() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('reactivateLiveWallpaper');
    } catch (e) {
      debugPrint('[AutoRotate] reactivateLiveWallpaper error: $e');
    }
  }
}
