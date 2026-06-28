import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../constants/supabase_config.dart';
import '../utils/connectivity.dart';

class SpriteDownloadService {
  SpriteDownloadService._();
  static final instance = SpriteDownloadService._();

  static const _bucket = 'wallpaper-sprites';
  static const _baseUrl = '${SupabaseConfig.storageBase}/$_bucket';

  static const _themeSprites = <String, List<String>>{
    'aquarium': [
      'aquarium/betta',
      'aquarium/angel',
      'aquarium/neon',
    ],
    'firefly': [
      'aquarium/firefly/moth_a',
      'aquarium/firefly/moth_b',
      'aquarium/firefly/moth_c',
      'aquarium/firefly/moth_d',
      'aquarium/firefly/owl',
    ],
    'jellyfish': [
      'aquarium/jellyfish_blue',
      'aquarium/jellyfish_gold',
      'aquarium/angler_fish',
      'aquarium/comb_jelly',
    ],
    'pixora_island': [
      'pixora_island/idle',
      'pixora_island/eat',
      'pixora_island/sleep',
      'pixora_island/walk',
    ],
    'volcano_dragon': [
      'v160_sprites/dragon_main',
      'v160_sprites/dragon_secondary',
      'v160_sprites/bat',
      'v160_sprites/phoenix',
    ],
    'dusk_fortress': [
      'v160_sprites/owl',
      'v160_sprites/crow',
      'v160_sprites/bat',
      'v160_sprites/dragon_main',
    ],
    'anime_drive': [
      'anime_cockpit',
    ],
    'bosque_lluvioso': [
      'v160_sprites/crow',
    ],
    'goku_genkidama': [
      'goku_genkidama_orb',
    ],
  };

  Map<String, dynamic>? _manifest;

  String? detectTheme(String wallpaperFilename) {
    final lower = wallpaperFilename.toLowerCase();
    for (final theme in _themeSprites.keys) {
      if (lower.contains(theme)) return theme;
    }
    return null;
  }

  Future<Directory> _spritesDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/sprites');
  }

  static const _metaFileName = '.pixora_sprite_meta.json';

  bool _isCached(
    Directory spritesRoot,
    String folder,
    Map<String, dynamic> info,
  ) {
    final dir = Directory('${spritesRoot.path}/$folder');
    if (!dir.existsSync()) return false;
    final pngs =
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png'));
    final expectedFrames = (info['frames'] as int?) ?? 1;
    // Exact match — stale folders with extra frames (e.g. 8 cached vs 5
    // expected) must re-download or the device keeps old low-res art.
    if (pngs.length != expectedFrames) return false;
    final expectedSize = info['size'] as int?;
    if (expectedSize == null) return true;
    final metaFile = File('${dir.path}/$_metaFileName');
    // Legacy folders (pre-meta) — trust frame count until next download.
    if (!metaFile.existsSync()) return true;
    try {
      final meta =
          json.decode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      return meta['zip_size'] == expectedSize;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeSpriteMeta(
    Directory dir,
    Map<String, dynamic> info,
  ) async {
    final frames = info['frames'];
    final zipSize = info['size'];
    if (frames is! int && zipSize is! int) return;
    try {
      await File('${dir.path}/$_metaFileName').writeAsString(
        jsonEncode({
          if (frames is int) 'frames': frames,
          if (zipSize is int) 'zip_size': zipSize,
        }),
      );
    } catch (e) {
      debugPrint('[Pixora] sprite meta write failed: $e');
    }
  }

  Future<Map<String, dynamic>> _fetchManifest() async {
    if (_manifest != null) return _manifest!;

    // Try disk cache first (expire after 24h to pick up new entries)
    try {
      final root = await _spritesDir();
      final cacheFile = File('${root.path}/manifest.json');
      if (cacheFile.existsSync()) {
        final age = DateTime.now().difference(cacheFile.lastModifiedSync());
        if (age.inHours < 24) {
          _manifest = json.decode(await cacheFile.readAsString())
              as Map<String, dynamic>;
          return _manifest!;
        }
      }
    } catch (_) {}

    try {
      final r = await http
          .get(Uri.parse('$_baseUrl/manifest.json'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        _manifest = json.decode(r.body) as Map<String, dynamic>;
        // Persist to disk
        try {
          final root = await _spritesDir();
          await root.create(recursive: true);
          await File('${root.path}/manifest.json').writeAsString(r.body);
        } catch (_) {}
        return _manifest!;
      }
    } catch (e) {
      debugPrint('[Pixora] Failed to fetch sprite manifest: $e');
    }
    return {};
  }

  Future<bool> ensureSpritesForTheme(
    String theme, {
    void Function(double progress)? onProgress,
  }) async {
    final folders = _themeSprites[theme];
    if (folders == null) return true;

    if (!await Connectivity.hasInternet()) {
      debugPrint('[Pixora] No internet — skipping sprite download for $theme');
      return false;
    }

    final manifest = await _fetchManifest();
    if (manifest.isEmpty) return false;

    final root = await _spritesDir();
    final toDownload = folders.where((f) {
      final info = manifest[f];
      if (info is! Map<String, dynamic>) return true;
      return !_isCached(root, f, info);
    }).toList();

    if (toDownload.isEmpty) {
      debugPrint('[Pixora] Sprites for $theme already cached');
      onProgress?.call(1.0);
      return true;
    }

    debugPrint(
        '[Pixora] Downloading sprite ZIPs for $theme: ${toDownload.length} folders');

    var done = 0;
    var failed = 0;
    final total = toDownload.length;

    for (final folder in toDownload) {
      final info = manifest[folder];
      if (info is! Map<String, dynamic>) {
        failed++;
        continue;
      }

      final zipPath = info['zip'] as String?;
      if (zipPath == null) {
        failed++;
        continue;
      }

      final dir = Directory('${root.path}/$folder');
      await dir.create(recursive: true);

      final zipUrl = '$_baseUrl/$zipPath';
      debugPrint('[Pixora] Downloading $zipUrl');

      var success = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final r = await http
              .get(Uri.parse(zipUrl))
              .timeout(const Duration(seconds: 60));
          if (r.statusCode == 200 && r.bodyBytes.length > 100) {
            final bytes = r.bodyBytes;
            final archive = await compute(_decodeZip, bytes);
            for (final file in archive) {
              if (file.isFile && file.name.endsWith('.png')) {
                final outFile = File('${dir.path}/${file.name}');
                await outFile.writeAsBytes(file.content as List<int>);
              }
            }
            await _writeSpriteMeta(dir, info);
            debugPrint('[Pixora] Extracted ${archive.length} files to $folder');
            success = true;
            break;
          }
        } catch (e) {
          if (attempt == 2) {
            debugPrint('[Pixora] Failed to download ZIP $zipUrl: $e');
          }
        }
      }

      if (!success) {
        try {
          if (dir.existsSync()) await dir.delete(recursive: true);
        } catch (_) {}
        failed++;
      }

      done++;
      onProgress?.call(done / total);
    }

    onProgress?.call(1.0);
    final ok = failed == 0;
    debugPrint(
        '[Pixora] Sprites for $theme ${ok ? "ready" : "INCOMPLETE ($failed failed)"} ($done/$total folders)');
    return ok;
  }

  /// Download every sprite folder declared by `manifest_key` in a scene
  /// spec's `sprites` array. This makes new canvas_scene wallpapers work
  /// out-of-the-box without bumping the hardcoded `_themeSprites` map —
  /// the spec is the source of truth.
  ///
  /// Schema expected (matches what CanvasSceneRenderer reads):
  /// ```json
  /// "sprites": [
  ///   {"name": "...", "manifest_key": "mictlantecuhtli/god", ...}
  /// ]
  /// ```
  Future<bool> ensureSpritesForScene(
    Map<String, dynamic> spec, {
    void Function(double progress)? onProgress,
  }) async {
    final sprites = spec['sprites'];
    if (sprites is! List || sprites.isEmpty) {
      onProgress?.call(1.0);
      return true; // nothing to download
    }
    final keys = <String>{};
    for (final s in sprites) {
      if (s is Map && s['manifest_key'] is String) {
        keys.add(s['manifest_key'] as String);
      }
    }
    if (keys.isEmpty) {
      onProgress?.call(1.0);
      return true;
    }

    if (!await Connectivity.hasInternet()) {
      debugPrint(
          '[Pixora] No internet — skipping spec sprite download (${keys.length} keys)');
      return false;
    }
    final manifest = await _fetchManifest();
    if (manifest.isEmpty) {
      debugPrint(
          '[Pixora] Empty sprite manifest — cannot resolve scene sprites');
      return false;
    }

    final root = await _spritesDir();
    final toDownload = keys.where((k) {
      final info = manifest[k];
      if (info is! Map<String, dynamic>) return true;
      return !_isCached(root, k, info);
    }).toList();

    if (toDownload.isEmpty) {
      debugPrint('[Pixora] All scene sprites already cached');
      onProgress?.call(1.0);
      return true;
    }

    debugPrint(
        '[Pixora] Downloading scene sprite ZIPs: ${toDownload.length} folders');

    var done = 0;
    var failed = 0;
    final total = toDownload.length;
    for (final folder in toDownload) {
      final info = manifest[folder];
      if (info is! Map<String, dynamic>) {
        failed++;
        done++;
        continue;
      }
      final zipPath = info['zip'] as String?;
      if (zipPath == null) {
        failed++;
        done++;
        continue;
      }
      final dir = Directory('${root.path}/$folder');
      await dir.create(recursive: true);
      final zipUrl = '$_baseUrl/$zipPath';
      var success = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final r = await http
              .get(Uri.parse(zipUrl))
              .timeout(const Duration(seconds: 60));
          if (r.statusCode == 200 && r.bodyBytes.length > 100) {
            final archive = await compute(_decodeZip, r.bodyBytes);
            for (final file in archive) {
              if (file.isFile && file.name.endsWith('.png')) {
                final outFile = File('${dir.path}/${file.name}');
                await outFile.writeAsBytes(file.content as List<int>);
              }
            }
            await _writeSpriteMeta(dir, info);
            debugPrint(
                '[Pixora] Extracted ${archive.length} files to $folder (scene sprite)');
            success = true;
            break;
          }
        } catch (e) {
          if (attempt == 2) {
            debugPrint('[Pixora] Failed to download scene sprite $zipUrl: $e');
          }
        }
      }
      if (!success) {
        try {
          if (dir.existsSync()) await dir.delete(recursive: true);
        } catch (_) {}
        failed++;
      }
      done++;
      onProgress?.call(done / total);
    }

    onProgress?.call(1.0);
    final ok = failed == 0;
    debugPrint(
        '[Pixora] Scene sprites ${ok ? "ready" : "INCOMPLETE ($failed failed)"} ($done/$total)');
    return ok;
  }

  static List<ArchiveFile> _decodeZip(List<int> bytes) {
    return ZipDecoder().decodeBytes(bytes).files;
  }

  Future<void> clearCache() async {
    try {
      final root = await _spritesDir();
      if (await root.exists()) await root.delete(recursive: true);
      _manifest = null;
    } catch (e) {
      debugPrint('[Pixora] Sprite cache clear error: $e');
    }
  }
}
