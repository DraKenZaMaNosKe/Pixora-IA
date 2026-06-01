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
    // Plasma + lava lamp pack (Eduardo's pick 2026-05-31)
    'cosmic_plasma',
    'liquid_aurora',
    'galaxy_plasma',
    'lava_red',
    'lava_blue',
    'lava_pastel',
    // Hybrid texture-shader lamps (Eduardo's pick 2026-05-31)
    'lava_hot_pink',
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
    if (!f.existsSync() || f.lengthSync() <= 50) return false;
    // Self-healing: HEAD-check Content-Length against cached size. If the
    // bucket has a re-uploaded version (same name, different bytes), drop
    // the stale file so the next ensureShader downloads fresh. Mirrors
    // the AURA download service pattern. HEAD failures fall back to using
    // the cache (offline, transient errors).
    try {
      final r = await http
          .head(Uri.parse('$_baseUrl/$name.glsl'))
          .timeout(const Duration(seconds: 6));
      final remoteLen = int.tryParse(r.headers['content-length'] ?? '') ?? 0;
      if (r.statusCode == 200 && remoteLen > 0 && remoteLen != f.lengthSync()) {
        debugPrint('[Pixora] Shader size mismatch $name '
            '(${f.lengthSync()} vs $remoteLen) — re-downloading');
        try {
          await f.delete();
        } catch (_) {}
        return false;
      }
    } catch (_) {
      // HEAD failed — trust the cache.
    }
    return true;
  }

  /// Download one shader by name. Returns true on success or if already cached.
  /// Also fetches optional companion texture (<name>.png) from
  /// wallpaper-images/realm_textures/<name>.png so hybrid shaders (e.g. lava
  /// lamps with a photo body + animated blobs inside) get both files together.
  Future<bool> ensureShader(String name) async {
    final cached = await _isCached(name);
    if (cached) {
      // Even if the .glsl is cached, the companion .png might not be yet
      // (added later or first run after the texture pipeline shipped).
      await _ensureCompanionTexture(name);
      return true;
    }
    if (!await Connectivity.hasInternet()) return false;
    try {
      final url = '$_baseUrl/$name.glsl';
      final r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && r.bodyBytes.length > 50) {
        final dir = await _shadersDir();
        await File('${dir.path}/$name.glsl').writeAsBytes(r.bodyBytes);
        debugPrint('[Pixora] Shader cached: $name (${r.bodyBytes.length} B)');
        await _ensureCompanionTexture(name);
        return true;
      }
      debugPrint('[Pixora] Shader download HTTP ${r.statusCode}: $name');
    } catch (e) {
      debugPrint('[Pixora] Shader download failed: $name → $e');
    }
    return false;
  }

  /// Try to download <name>.png from realm_textures/. Companion textures are
  /// optional — most shaders are pure-procedural and don't have one. HEAD-check
  /// first so we don't waste bandwidth on shaders without skins. Silent on
  /// missing texture (HTTP 404) since that's the common case.
  Future<void> _ensureCompanionTexture(String name) async {
    try {
      final dir = await _shadersDir();
      final pngFile = File('${dir.path}/$name.png');
      const texBase =
          '${SupabaseConfig.storageBase}/wallpaper-images/realm_textures';
      final url = '$texBase/$name.png';
      // If cached, HEAD-check size for self-healing (same pattern as .glsl).
      if (pngFile.existsSync() && pngFile.lengthSync() > 1024) {
        try {
          final head = await http
              .head(Uri.parse(url))
              .timeout(const Duration(seconds: 6));
          final remoteLen =
              int.tryParse(head.headers['content-length'] ?? '') ?? 0;
          if (head.statusCode == 200 &&
              remoteLen > 0 &&
              remoteLen == pngFile.lengthSync()) {
            return; // cache matches remote
          }
          if (head.statusCode == 404) return; // no companion, that's fine
        } catch (_) {
          return; // HEAD failed — trust cache
        }
      }
      if (!await Connectivity.hasInternet()) return;
      final r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (r.statusCode == 200 && r.bodyBytes.length > 1024) {
        await pngFile.writeAsBytes(r.bodyBytes);
        debugPrint(
            '[Pixora] Shader texture cached: $name (${r.bodyBytes.length} B)');
      }
    } catch (e) {
      // Companion is optional — never block .glsl flow on PNG fetch errors.
      debugPrint('[Pixora] Texture fetch for $name: $e');
    }
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
