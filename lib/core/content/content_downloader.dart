import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/connectivity.dart';
import 'content_cache.dart';
import 'content_types.dart';
import 'content_url_resolver.dart';

/// Unified downloader with deduplication, retry, progress, and validation.
/// If the same item is requested twice concurrently, the second call waits
/// for the first instead of starting a duplicate download.
class ContentDownloader {
  ContentDownloader._();
  static final instance = ContentDownloader._();

  static const _maxRetries = 3;
  static const _timeoutSeconds = 120;
  static const _minValidBytes = 512;

  /// Active downloads — prevents duplicate concurrent downloads of the same item.
  final _active = <String, Completer<String?>>{};

  /// Download a content item. Returns local file path on success, null on failure.
  Future<String?> download(
    ContentItem item, {
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
  }) async {
    // Cache hit
    if (await ContentCache.instance.isCached(item)) {
      final path = await ContentCache.instance.pathFor(item);
      onProgress?.call(1.0);
      return path;
    }

    // Dedup: if this item is already being downloaded, wait for it
    if (_active.containsKey(item.id)) {
      debugPrint('[ContentDownloader] Dedup: waiting for ${item.id}');
      return _active[item.id]!.future;
    }

    // Start new download
    final completer = Completer<String?>();
    _active[item.id] = completer;

    try {
      final result =
          await _doDownload(item, onProgress: onProgress, onError: onError);
      completer.complete(result);
      if (result != null) {
        // Trim cache in background after successful download
        ContentCache.instance.trimIfNeeded();
      }
      return result;
    } catch (e) {
      completer.complete(null);
      onError?.call('Download failed');
      return null;
    } finally {
      _active.remove(item.id);
    }
  }

  Future<String?> _doDownload(
    ContentItem item, {
    void Function(double)? onProgress,
    void Function(String)? onError,
  }) async {
    if (!await Connectivity.hasInternet()) {
      onError?.call('No internet connection');
      return null;
    }

    final url = ContentUrlResolver.resolve(item);
    final file = await ContentCache.instance.fileFor(item);

    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final path = await _streamDownload(url, file, onProgress);
        if (path != null) return path;
      } catch (e) {
        debugPrint(
            '[ContentDownloader] Attempt $attempt/$_maxRetries for ${item.id}: $e');
        if (await file.exists()) await file.delete();
        if (attempt < _maxRetries) {
          await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
          onProgress?.call(0.0);
        }
      }
    }
    onError?.call('Download failed after $_maxRetries attempts');
    return null;
  }

  Future<String?> _streamDownload(
    String url,
    File file,
    void Function(double)? onProgress,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request).timeout(
            const Duration(seconds: _timeoutSeconds),
          );

      if (response.statusCode != 200) {
        debugPrint('[ContentDownloader] HTTP ${response.statusCode} for $url');
        return null;
      }

      final totalBytes = response.contentLength ?? -1;
      var receivedBytes = 0;
      final sink = file.openWrite();

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) onProgress?.call(receivedBytes / totalBytes);
        }
        await sink.flush();
        await sink.close();

        final fileSize = await file.length();
        if (fileSize < _minValidBytes) {
          debugPrint('[ContentDownloader] File too small ($fileSize bytes)');
          await file.delete();
          return null;
        }
        if (totalBytes > 0 && fileSize != totalBytes) {
          debugPrint(
              '[ContentDownloader] Size mismatch: expected $totalBytes, got $fileSize');
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
}
