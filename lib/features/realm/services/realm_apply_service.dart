import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/services/shader_download_service.dart';
import '../data/realm_shader.dart';

/// Thin wrapper around the native `setShaderWallpaper` MethodChannel handler
/// in MainActivity.kt. The native side writes `shader_name` to prefs and
/// launches Android's wallpaper picker for our `ShaderWallpaperService`;
/// when the user taps "Apply" the engine spawns and reads the prefs.
class RealmApplyService {
  RealmApplyService._();
  static final instance = RealmApplyService._();

  static const _channel = MethodChannel('com.orbix.pixora/wallpaper');

  /// Apply (open the system picker for) a REALM shader. Ensures the .glsl
  /// is cached locally first so the engine has the source on disk before
  /// the user taps "Apply" — avoids a black screen while the file
  /// downloads in the background.
  Future<bool> apply(RealmShader shader) async {
    try {
      await ShaderDownloadService.instance.ensureShader(shader.id);
      final ok = await _channel.invokeMethod<bool>(
        'setShaderWallpaper',
        {'shaderName': shader.id},
      );
      return ok ?? false;
    } catch (e) {
      debugPrint('[RealmApply] ${shader.id} failed: $e');
      return false;
    }
  }
}
