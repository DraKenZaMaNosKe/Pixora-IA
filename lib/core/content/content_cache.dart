import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'content_types.dart';

/// Unified cache for all downloadable content in Pixora.
/// Deterministic paths, LRU eviction, one-stop cache management.
class ContentCache {
  ContentCache._();
  static final instance = ContentCache._();

  static const maxCacheMb = 500;
  String? _basePath;

  Future<String> get basePath async {
    if (_basePath != null) return _basePath!;
    final dir = await getApplicationDocumentsDirectory();
    _basePath = dir.path;
    return _basePath!;
  }

  /// Deterministic local path for any content item.
  Future<String> pathFor(ContentItem item) async {
    final base = await basePath;
    switch (item.type) {
      case ContentType.staticWallpaper:
      case ContentType.panoramicWallpaper:
        return '$base/wallpapers/${item.remoteFile}';
      case ContentType.liveVideo:
      case ContentType.liveVideoExplore:
        return '$base/live_wallpapers/${item.remoteFile}';
      case ContentType.ringtone:
      case ContentType.notification:
      case ContentType.alarm:
        return '$base/tones/${item.id}.mp3';
      case ContentType.story:
      case ContentType.dayCycle:
        return '$base/wallpapers/${item.remoteFile}';
      case ContentType.auraTrack:
        return '$base/aura/${item.id}.mp3';
    }
  }

  /// Check if content is already cached and valid.
  ///
  /// Self-healing: if [item.expectedSize] is set (> 0) and the on-disk size
  /// doesn't match, the cache file is deleted and `false` returned so the
  /// caller re-downloads the fresh bytes. This makes content republish
  /// transparent to clients — no Play Store update required.
  Future<bool> isCached(ContentItem item, {int minBytes = 512}) async {
    final path = await pathFor(item);
    final file = File(path);
    if (!file.existsSync()) return false;
    final size = file.lengthSync();
    if (size <= minBytes) return false;
    final expected = item.expectedSize;
    if (expected > 0 && size != expected) {
      debugPrint(
          '[ContentCache] size mismatch ${item.id} ($size vs $expected) — invalidating');
      try {
        file.deleteSync();
      } catch (_) {}
      return false;
    }
    return true;
  }

  /// Get the local file for a content item (may not exist yet).
  Future<File> fileFor(ContentItem item) async {
    final path = await pathFor(item);
    final file = File(path);
    await file.parent.create(recursive: true);
    return file;
  }

  /// Total cache size across all content types.
  Future<int> totalSizeBytes() async {
    final base = await basePath;
    var total = 0;
    for (final subdir in ['wallpapers', 'live_wallpapers', 'tones', 'aura']) {
      final dir = Directory('$base/$subdir');
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
    }
    return total;
  }

  /// LRU eviction: remove oldest files until cache is under maxCacheMb.
  Future<void> trimIfNeeded() async {
    try {
      final base = await basePath;
      final allFiles = <File>[];
      for (final subdir in ['wallpapers', 'live_wallpapers', 'tones', 'aura']) {
        final dir = Directory('$base/$subdir');
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) allFiles.add(entity);
        }
      }

      var totalSize = 0;
      final fileSizes = <File, int>{};
      for (final f in allFiles) {
        final size = await f.length();
        fileSizes[f] = size;
        totalSize += size;
      }

      const maxBytes = maxCacheMb * 1024 * 1024;
      if (totalSize <= maxBytes) return;

      // Sort by last modified, oldest first
      allFiles
          .sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      for (final f in allFiles) {
        if (totalSize <= maxBytes) break;
        totalSize -= (fileSizes[f] ?? 0);
        await f.delete();
      }
      debugPrint('[ContentCache] Trimmed to ${totalSize ~/ (1024 * 1024)} MB');
    } catch (e) {
      debugPrint('[ContentCache] Trim error: $e');
    }
  }

  /// Clear all cached content.
  Future<void> clearAll() async {
    final base = await basePath;
    for (final subdir in ['wallpapers', 'live_wallpapers', 'tones', 'aura']) {
      final dir = Directory('$base/$subdir');
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    debugPrint('[ContentCache] All caches cleared');
  }
}
