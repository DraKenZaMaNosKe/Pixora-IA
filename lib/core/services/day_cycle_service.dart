import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../features/day_cycle/data/models/day_cycle_theme.dart';
import '../content/content_manager.dart';
import '../content/content_types.dart';
import '../content/content_url_resolver.dart';
import 'wallpaper_engine_coordinator.dart';

class DayCycleService {
  DayCycleService._();
  static final instance = DayCycleService._();

  static const _channel = MethodChannel('com.orbix.pixora/wallpaper');

  /// Engine that was preempted by the most recent successful `activate()`.
  WallpaperEngine lastPreempted = WallpaperEngine.none;

  Future<bool> activate(
    DayCycleTheme theme, {
    int target = 0,
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      // Mutex: stop AutoRotate / Story before claiming the wallpaper Surface.
      lastPreempted = await WallpaperEngineCoordinator.instance.claim(
        WallpaperEngine.dayCycle,
        context: theme.id,
      );

      final images = theme.allImages;
      final paths = <String>[];

      for (var i = 0; i < images.length; i++) {
        onProgress?.call(i + 1, images.length);
        final item = ContentItem(
          id: '${theme.id}_$i',
          type: ContentType.staticWallpaper,
          remoteFile: images[i],
          bucket: ContentUrlResolver.wallpaperImagesBucket,
        );
        final path = await ContentManager.instance.download(item);
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
      await WallpaperEngineCoordinator.instance
          .release(WallpaperEngine.dayCycle);
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
