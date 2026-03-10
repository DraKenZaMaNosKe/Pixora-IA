import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'catalog_service.dart';

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
  Future<bool> start({
    int intervalMinutes = 5,
    int target = 2,
    String? category,
  }) async {
    if (!Platform.isAndroid) return false;

    try {
      // Fetch catalog and build compact data for native
      final catalog = await CatalogService.instance.fetchCatalog();
      if (catalog.isEmpty) {
        debugPrint('[AutoRotate] No wallpapers in catalog');
        return false;
      }

      // Filter by category if specified
      final filtered = category != null
          ? catalog.where((w) => w.category == category).toList()
          : catalog;

      if (filtered.isEmpty) {
        debugPrint('[AutoRotate] No wallpapers for category: $category');
        return false;
      }

      // Build compact catalog: "id|imageFile|glowColor" per entry
      final catalogData = filtered.map((w) =>
        '${w.id}|${w.imageFile}|${w.glowColor}'
      ).toList();

      final result = await _channel.invokeMethod<bool>(
        'startAutoRotate',
        {
          'catalogData': catalogData,
          'intervalMinutes': intervalMinutes,
          'target': target,
          if (category != null) 'category': category,
        },
      );

      debugPrint('[AutoRotate] Started: ${filtered.length} wallpapers, ${intervalMinutes}min');
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
}
