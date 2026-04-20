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

  bool _isCached(Directory spritesRoot, String folder, int expectedFrames) {
    final dir = Directory('${spritesRoot.path}/$folder');
    if (!dir.existsSync()) return false;
    final pngs =
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png'));
    return pngs.length >= expectedFrames;
  }

  Future<Map<String, dynamic>> _fetchManifest() async {
    if (_manifest != null) return _manifest!;

    // Try disk cache first
    try {
      final root = await _spritesDir();
      final cacheFile = File('${root.path}/manifest.json');
      if (cacheFile.existsSync()) {
        _manifest =
            json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
        return _manifest!;
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
      final expected = (info is Map && info.containsKey('frames'))
          ? (info['frames'] as int? ?? 10)
          : 10;
      return !_isCached(root, f, expected);
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
