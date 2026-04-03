import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../constants/supabase_config.dart';
import '../utils/connectivity.dart';

class DownloadService {
  DownloadService._();
  static final instance = DownloadService._();

  static const _maxRetries = 3;
  static const _maxCacheMb = 500;
  static const _timeoutSeconds = 60;
  /// Minimum valid file size (bytes) — anything smaller is likely corrupt.
  static const _minValidBytes = 512;

  /// Download a wallpaper image with progress + retry.
  /// Returns local file path on success, null on failure.
  /// [onError] is called with a user-friendly message on failure.
  Future<String?> downloadWallpaper(
    String filename, {
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/wallpapers/$filename');

      // Cache hit
      if (await file.exists() && await file.length() > _minValidBytes) {
        onProgress?.call(1.0);
        return file.path;
      }

      // Check connectivity before attempting download
      if (!await Connectivity.hasInternet()) {
        onError?.call('No internet connection');
        return null;
      }

      await file.parent.create(recursive: true);
      final url = SupabaseConfig.imageUrl(filename);

      for (var attempt = 1; attempt <= _maxRetries; attempt++) {
        try {
          final path = await _streamDownload(url, file, onProgress);
          if (path != null) {
            _trimCacheIfNeeded(dir.path);
            return path;
          }
        } catch (e) {
          debugPrint('[Pixora] Download attempt $attempt/$_maxRetries: $e');
          // Clean up partial file
          if (await file.exists()) await file.delete();
          if (attempt < _maxRetries) {
            await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
            onProgress?.call(0.0);
          }
        }
      }
      onError?.call('Download failed after $_maxRetries attempts');
    } catch (e) {
      debugPrint('[Pixora] Download error: $e');
      onError?.call('Download failed');
    }
    return null;
  }

  /// Generic file download with progress, timeout, and validation.
  /// Works for any URL → local file (videos, tones, images).
  /// Returns local path on success, null on failure.
  Future<String?> downloadFile(
    String url,
    File destination, {
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
    int retries = 3,
    int timeoutSeconds = 120,
    int minBytes = 1000,
  }) async {
    // Cache hit
    if (await destination.exists() && await destination.length() > minBytes) {
      onProgress?.call(1.0);
      return destination.path;
    }

    if (!await Connectivity.hasInternet()) {
      onError?.call('No internet connection');
      return null;
    }

    await destination.parent.create(recursive: true);

    for (var attempt = 1; attempt <= retries; attempt++) {
      try {
        final path = await _streamDownload(
          url,
          destination,
          onProgress,
          timeoutSeconds: timeoutSeconds,
          minBytes: minBytes,
        );
        if (path != null) return path;
      } catch (e) {
        debugPrint('[Pixora] Download attempt $attempt/$retries: $e');
        if (await destination.exists()) await destination.delete();
        if (attempt < retries) {
          await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
          onProgress?.call(0.0);
        }
      }
    }
    onError?.call('Download failed. Please try again.');
    return null;
  }

  /// Core stream download — shared by all download methods.
  Future<String?> _streamDownload(
    String url,
    File file,
    void Function(double)? onProgress, {
    int timeoutSeconds = _timeoutSeconds,
    int minBytes = _minValidBytes,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request).timeout(
        Duration(seconds: timeoutSeconds),
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

        // Post-download validation
        final fileSize = await file.length();
        if (fileSize < minBytes) {
          debugPrint('[Pixora] File too small ($fileSize bytes), deleting');
          await file.delete();
          return null;
        }

        // Verify size matches if server sent Content-Length
        if (totalBytes > 0 && fileSize != totalBytes) {
          debugPrint('[Pixora] Size mismatch: expected $totalBytes, got $fileSize');
          await file.delete();
          return null;
        }

        onProgress?.call(1.0);
        return file.path;
      } catch (e) {
        await sink.close();
        if (await file.exists()) await file.delete();
        rethrow;
      }
    } finally {
      client.close();
    }
  }

  /// Remove oldest cached files if cache exceeds max size.
  void _trimCacheIfNeeded(String basePath) {
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
        totalSize += size;
      }

      const maxBytes = _maxCacheMb * 1024 * 1024;
      if (totalSize <= maxBytes) return;

      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      for (final f in files) {
        if (totalSize <= maxBytes) break;
        totalSize -= (fileSizes[f] ?? 0);
        await f.delete();
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
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (e) {
      debugPrint('[Pixora] Get cache size error: $e');
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
    } catch (e) {
      debugPrint('[Pixora] Clear cache error: $e');
    }
  }
}
