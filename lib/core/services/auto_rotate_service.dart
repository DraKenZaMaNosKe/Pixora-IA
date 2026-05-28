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

      // Fetch catalog and build compact data for native
      final catalog = await CatalogService.instance.fetchCatalog();
      if (catalog.isEmpty) {
        debugPrint('[AutoRotate] No wallpapers in catalog');
        return false;
      }

      // Filter by category. Caso especial: 'DAILY' no es una categoría
      // real (aunque exista en el enum), es un FLAG. Filtramos por el
      // boolean daily_eligible para que el wallpaper conserve su categoría
      // natural (ANIME, GAMING, etc.) pero rote en Pixora Daily curado.
      final filtered = category == 'DAILY'
          ? catalog.where((w) => w.dailyEligible).toList()
          : (category != null
              ? catalog.where((w) => w.category == category).toList()
              : catalog);

      if (filtered.isEmpty) {
        debugPrint('[AutoRotate] No wallpapers for category: $category');
        return false;
      }

      // Build compact catalog: "id|imageFile|glowColor" per entry
      final catalogData =
          filtered.map((w) => '${w.id}|${w.imageFile}|${w.glowColor}').toList();

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
