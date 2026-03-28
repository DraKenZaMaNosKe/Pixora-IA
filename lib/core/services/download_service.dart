import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../constants/supabase_config.dart';

class DownloadService {
  DownloadService._();
  static final instance = DownloadService._();

  static const _maxRetries = 3;
  static const _maxCacheMb = 500; // max cache size in MB

  /// Download wallpaper with progress callback and retry logic.
  /// Returns cached file if already downloaded.
  Future<String?> downloadWallpaper(
    String filename, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/wallpapers/$filename');

      // Cache hit: already downloaded
      if (await file.exists() && await file.length() > 0) {
        onProgress?.call(1.0);
        debugPrint('[Pixora] Cache hit: $filename');
        return file.path;
      }

      await file.parent.create(recursive: true);

      final url = SupabaseConfig.imageUrl(filename);

      // Retry loop
      for (var attempt = 1; attempt <= _maxRetries; attempt++) {
        try {
          final path = await _downloadWithProgress(url, file, onProgress);
          if (path != null) {
            // Cleanup old cache in background
            _trimCacheIfNeeded(dir.path);
            return path;
          }
        } catch (e) {
          debugPrint('[Pixora] Download attempt $attempt/$_maxRetries failed: $e');
          if (attempt < _maxRetries) {
            // Exponential backoff: 1s, 2s, 4s
            await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
            onProgress?.call(0.0); // reset progress for retry
          }
        }
      }
    } catch (e) {
      debugPrint('[Pixora] Download failed permanently: $e');
    }
    return null;
  }

  /// Stream download with progress reporting.
  Future<String?> _downloadWithProgress(
    String url,
    File file,
    void Function(double)? onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request).timeout(
      const Duration(seconds: 60),
    );

    if (response.statusCode != 200) {
      debugPrint('[Pixora] HTTP ${response.statusCode} for $url');
      return null;
    }

    final totalBytes = response.contentLength ?? -1;
    var receivedBytes = 0;
    final sink = file.openWrite();

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(receivedBytes / totalBytes);
        }
      }
      await sink.flush();
      await sink.close();

      debugPrint('[Pixora] Downloaded: ${file.path} ($receivedBytes bytes)');
      onProgress?.call(1.0);
      return file.path;
    } catch (e) {
      await sink.close();
      // Clean up partial file
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  /// Remove oldest cached files if cache exceeds max size.
  void _trimCacheIfNeeded(String basePath) {
    // Run in isolate-friendly way (fire and forget)
    compute(_trimCache, '$basePath/wallpapers');
  }

  static Future<void> _trimCache(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;

      final entities = await dir.list().toList();
      final files = entities.whereType<File>().toList();
      var totalSize = 0;
      final fileSizes = <File, int>{};

      for (final f in files) {
        final size = await f.length();
        fileSizes[f] = size;
        totalSize = totalSize + size;
      }

      final maxBytes = _maxCacheMb * 1024 * 1024;
      if (totalSize <= maxBytes) return;

      // Sort by last modified (oldest first)
      files.sort((a, b) {
        final aTime = a.lastModifiedSync();
        final bTime = b.lastModifiedSync();
        return aTime.compareTo(bTime);
      });

      // Delete oldest until under limit
      for (final f in files) {
        if (totalSize <= maxBytes) break;
        totalSize = totalSize - (fileSizes[f] ?? 0);
        await f.delete();
        debugPrint('[Pixora] Cache cleanup: deleted ${f.path}');
      }
    } catch (e) {
      debugPrint('[Pixora] Cache trim error: $e');
    }
  }

  /// Get current cache size in bytes.
  Future<int> getCacheSize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final wallpaperDir = Directory('${dir.path}/wallpapers');
      if (!await wallpaperDir.exists()) return 0;

      var total = 0;
      await for (final entity in wallpaperDir.list()) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Clear all downloaded wallpapers.
  Future<void> clearCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final wallpaperDir = Directory('${dir.path}/wallpapers');
      if (await wallpaperDir.exists()) {
        await wallpaperDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
