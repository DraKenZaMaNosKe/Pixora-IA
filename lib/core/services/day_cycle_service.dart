import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../features/day_cycle/data/models/day_cycle_theme.dart';
import 'download_service.dart';

class DayCycleService {
  DayCycleService._();
  static final instance = DayCycleService._();

  static const _channel = MethodChannel('com.orbix.pixora/wallpaper');

  Future<bool> activate(
    DayCycleTheme theme, {
    int target = 0,
    void Function(int current, int total)? onProgress,
  }) async {
    try {
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

  Future<void> deactivate() async {
    try {
      await _channel.invokeMethod('stopDayCycle');
    } catch (e) {
      debugPrint('[Pixora] Day cycle deactivation failed: $e');
    }
  }

  Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await _channel.invokeMethod('getDayCycleStatus');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'enabled': false};
    } catch (e) {
      debugPrint('[Pixora] Day cycle status error: $e');
      return {'enabled': false};
    }
  }
}
