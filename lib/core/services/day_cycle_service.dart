import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../features/day_cycle/data/models/day_cycle_theme.dart';
import 'download_service.dart';

/// Manages Day Cycle activation/deactivation via native WorkManager.
/// Downloads all 4 period images and schedules periodic wallpaper changes.
class DayCycleService {
  DayCycleService._();
  static final instance = DayCycleService._();

  static const _channel = MethodChannel('com.orbix.pixora/wallpaper');

  /// Activate a day cycle theme.
  /// Downloads all 4 images, then starts native DayCycleWorker.
  Future<bool> activate(
    DayCycleTheme theme, {
    int target = 0,
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      // Download all 4 period images
      final images = theme.allImages;
      final paths = <String>[];

      for (var i = 0; i < images.length; i++) {
        onProgress?.call(i + 1, images.length);
        final path = await DownloadService.instance.downloadWallpaper(images[i]);
        if (path == null) {
          debugPrint('[Pixora] Day cycle: failed to download ${images[i]}');
          return false;
        }
        paths.add(path);
      }

      // Start native worker with downloaded paths
      await _channel.invokeMethod('startDayCycle', {
        'themeId': theme.id,
        'morningPath': paths[0],
        'afternoonPath': paths[1],
        'eveningPath': paths[2],
        'nightPath': paths[3],
        'glowColor': theme.glowColor,
        'target': target,
      });

      debugPrint('[Pixora] Day cycle activated: ${theme.name}');
      return true;
    } catch (e) {
      debugPrint('[Pixora] Day cycle activation failed: $e');
      return false;
    }
  }

  /// Deactivate the current day cycle.
  Future<void> deactivate() async {
    try {
      await _channel.invokeMethod('stopDayCycle');
      debugPrint('[Pixora] Day cycle deactivated');
    } catch (e) {
      debugPrint('[Pixora] Day cycle deactivation failed: $e');
    }
  }

  /// Get current day cycle status.
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await _channel.invokeMethod('getDayCycleStatus');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      debugPrint('[Pixora] Day cycle status failed: $e');
      return {'enabled': false};
    }
  }
}
