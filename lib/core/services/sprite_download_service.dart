import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../constants/supabase_config.dart';

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

  bool _isCached(Directory spritesRoot, String folder) {
    final dir = Directory('${spritesRoot.path}/$folder');
    if (!dir.existsSync()) return false;
    final pngs =
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png'));
    return pngs.length > 5;
  }

  Future<Map<String, dynamic>> _fetchManifest() async {
    if (_manifest != null) return _manifest!;
    try {
      final r = await http
          .get(Uri.parse('$_baseUrl/manifest.json'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        _manifest = json.decode(r.body) as Map<String, dynamic>;
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

    final root = await _spritesDir();
    final toDownload = folders.where((f) => !_isCached(root, f)).toList();

    if (toDownload.isEmpty) {
      debugPrint('[Pixora] Sprites for $theme already cached');
      onProgress?.call(1.0);
      return true;
    }

    debugPrint(
        '[Pixora] Downloading sprite ZIPs for $theme: ${toDownload.length} folders');
    final manifest = await _fetchManifest();
    if (manifest.isEmpty) return false;

    var done = 0;
    final total = toDownload.length;

    for (final folder in toDownload) {
      final info = manifest[folder] as Map<String, dynamic>?;
      if (info == null) continue;

      final zipPath = info['zip'] as String?;
      if (zipPath == null) continue;

      final dir = Directory('${root.path}/$folder');
      await dir.create(recursive: true);

      final zipUrl = '$_baseUrl/$zipPath';
      debugPrint('[Pixora] Downloading $zipUrl');

      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final r = await http
              .get(Uri.parse(zipUrl))
              .timeout(const Duration(seconds: 60));
          if (r.statusCode == 200 && r.bodyBytes.length > 100) {
            final archive = ZipDecoder().decodeBytes(r.bodyBytes);
            for (final file in archive) {
              if (file.isFile && file.name.endsWith('.png')) {
                final outFile = File('${dir.path}/${file.name}');
                await outFile.writeAsBytes(file.content as List<int>);
              }
            }
            debugPrint('[Pixora] Extracted ${archive.length} files to $folder');
            break;
          }
        } catch (e) {
          if (attempt == 2) {
            debugPrint('[Pixora] Failed to download ZIP $zipUrl: $e');
          }
        }
      }

      done++;
      onProgress?.call(done / total);
    }

    onProgress?.call(1.0);
    debugPrint('[Pixora] Sprites for $theme ready ($done/$total folders)');
    return true;
  }

  Future<void> clearCache() async {
    try {
      final root = await _spritesDir();
      if (await root.exists()) await root.delete(recursive: true);
    } catch (e) {
      debugPrint('[Pixora] Sprite cache clear error: $e');
    }
  }
}
