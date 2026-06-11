import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'catalog_service.dart';
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

      // 2026-06-10 product decision (Eduardo) — Daily ONLY rotates static
      // and panoramic wallpapers. Live videos are excluded by design:
      //
      // 1. Stability — the 3 critical crashes shipped in v1.7.19 (HWUI
      //    RenderThread SIGABRT, startVideoWallpaper race, self-kill loop
      //    on commit-vs-apply) ALL stem from the canvas↔video Surface
      //    producer transition. If Daily never touches videos, those
      //    transitions never happen → that entire class of bugs is gone.
      //
      // 2. Monetization — live wallpapers are the premium experience.
      //    Forcing users to apply them MANUALLY routes every live install
      //    through AdService.showInterstitialAd, which is more ad views
      //    than a silent background rotation could ever produce.
      //
      // 3. UX coherence — Daily reads as "passive rotation", Live reads
      //    as "deliberate premium choice". Mixing them confused both.
      //
      // Panoramic stays IN — it's just a wider static image, no Surface
      // producer change needed (Canvas handles both).
      final catalog = await CatalogService.instance.fetchCatalog();
      if (catalog.isEmpty) {
        debugPrint('[AutoRotate] No wallpapers in static catalog');
        return false;
      }

      // Filter by category. 'DAILY' = flag for curated daily set (uses
      // per-wallpaper dailyEligible boolean instead of a real category).
      final filtered = category == 'DAILY'
          ? catalog.where((w) => w.dailyEligible).toList()
          : (category != null
              ? catalog.where((w) => w.category == category).toList()
              : catalog);

      if (filtered.isEmpty) {
        debugPrint('[AutoRotate] No wallpapers for category: $category');
        return false;
      }

      // Wire format: "id|file|glowColor|type" — type is always `static` here
      // (the native worker treats panoramic as static too — aspect ratio is
      // detected at draw time, not in the catalog). The `type` field is
      // kept for backward compat with the worker's parser and as a future
      // hook in case live is re-introduced via a different code path.
      final catalogData = filtered
          .map((w) => '${w.id}|${w.imageFile}|${w.glowColor}|static')
          .toList();

      final result = await _channel.invokeMethod<bool>(
        'startAutoRotate',
        {
          'catalogData': catalogData,
          'intervalMinutes': intervalMinutes,
          'target': target,
          if (category != null) 'category': category,
        },
      );

      debugPrint(
          '[AutoRotate] Started: ${filtered.length} wallpapers, ${intervalMinutes}min');
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
      // Static-only per the 2026-06-10 decision (see comment in start()).
      final catalog = await CatalogService.instance.fetchCatalog();
      final filtered = category == 'DAILY'
          ? catalog.where((w) => w.dailyEligible).toList()
          : (category != null
              ? catalog.where((w) => w.category == category).toList()
              : catalog);

      if (filtered.isEmpty) {
        debugPrint('[AutoRotate] Refresh: empty filtered catalog, skipping');
        return false;
      }

      final catalogData = filtered
          .map((w) => '${w.id}|${w.imageFile}|${w.glowColor}|static')
          .toList();

      debugPrint(
          '[AutoRotate] Refresh: silent catalog update (${catalogData.length} entries, cat=$category)');
      final result = await _channel.invokeMethod<bool>(
        'updateAutoRotateCatalog',
        {
          'catalogData': catalogData,
          'intervalMinutes': intervalMinutes,
          'target': target,
          if (category != null) 'category': category,
        },
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[AutoRotate] refreshIfRunning error: $e');
      return false;
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
