import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../constants/supabase_config.dart';
import '../utils/connectivity.dart';

/// Downloads + caches GLSL shader source from Supabase to filesDir/shaders/.
/// The native ShaderWallpaperService reads from there first.
///
/// Bootstrap shaders are pre-downloaded on app start so they're ready when
/// the user applies a shader wallpaper. Per-shader downloads are also
/// supported for future scene-driven wallpapers.
class ShaderDownloadService {
  ShaderDownloadService._();
  static final instance = ShaderDownloadService._();

  static const _bucket = 'wallpaper-shaders';
  static const _baseUrl = '${SupabaseConfig.storageBase}/$_bucket';

  /// Names of shaders that should always be available offline (after first
  /// successful download). REALM v1 catalog — 10 designs, ~16 KB total.
  static const _bootstrap = <String>[
    'universe',
    'honeycomb',
    'neon_triangles',
    'sacred_geometry',
    'digital_rain',
    'synthwave_grid',
    'plasma_orbs',
    'kaleidoscope',
    'metaballs',
    'circuit_city',
    'clock',
  ];

  Future<Directory> _shadersDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/shaders');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<bool> _isCached(String name) async {
    final dir = await _shadersDir();
    final f = File('${dir.path}/$name.glsl');
    return f.existsSync() && f.lengthSync() > 50;
  }

  /// Download one shader by name. Returns true on success or if already cached.
  Future<bool> ensureShader(String name) async {
    if (await _isCached(name)) return true;
    if (!await Connectivity.hasInternet()) return false;
    try {
      final url = '$_baseUrl/$name.glsl';
      final r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && r.bodyBytes.length > 50) {
        final dir = await _shadersDir();
        await File('${dir.path}/$name.glsl').writeAsBytes(r.bodyBytes);
        debugPrint('[Pixora] Shader cached: $name (${r.bodyBytes.length} B)');
        return true;
      }
      debugPrint('[Pixora] Shader download HTTP ${r.statusCode}: $name');
    } catch (e) {
      debugPrint('[Pixora] Shader download failed: $name → $e');
    }
    return false;
  }

  /// Pre-download all bootstrap shaders so they're ready offline. Safe to
  /// call repeatedly — already-cached shaders are skipped.
  Future<void> ensureBootstrapShaders() async {
    for (final name in _bootstrap) {
      await ensureShader(name);
    }
  }

  Future<void> clearCache() async {
    try {
      final dir = await _shadersDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('[Pixora] Shader cache clear error: $e');
    }
  }
}
