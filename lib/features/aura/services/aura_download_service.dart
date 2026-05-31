import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../data/models/aura_track.dart';

/// Saves AURA tracks to the app's documents dir for offline playback.
class AuraDownloadService {
  AuraDownloadService._();
  static final instance = AuraDownloadService._();

  Future<File?> download(AuraTrack track) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final auraDir = Directory('${dir.path}/aura');
      if (!await auraDir.exists()) await auraDir.create(recursive: true);
      final file = File('${auraDir.path}/${track.id}.mp3');
      // Cache hit only if cached size matches remote Content-Length. This
      // makes the cache self-healing if the track is re-uploaded with new
      // bytes (re-encode, master change). HEAD request is cheap (~1 KB)
      // vs. re-downloading a multi-MB MP3 unnecessarily. If HEAD fails (no
      // network, etc.) and the file exists, fall back to using the cache.
      if (await file.exists()) {
        final cachedSize = await file.length();
        try {
          final head = await http
              .head(Uri.parse(track.audioUrl))
              .timeout(const Duration(seconds: 8));
          final remoteLen =
              int.tryParse(head.headers['content-length'] ?? '') ?? 0;
          if (head.statusCode == 200 &&
              remoteLen > 0 &&
              remoteLen == cachedSize) {
            return file;
          }
          if (head.statusCode == 200 && remoteLen != cachedSize) {
            debugPrint(
                '[Pixora] AURA size mismatch ${track.id} ($cachedSize vs $remoteLen) — re-downloading');
            // fall through to fresh download
          } else {
            // HEAD ambiguous (non-200, missing length) — trust the cache.
            return file;
          }
        } catch (_) {
          // HEAD failed → trust the cache (offline or transient).
          return file;
        }
      }
      final r = await http
          .get(Uri.parse(track.audioUrl))
          .timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) return null;
      await file.writeAsBytes(r.bodyBytes);
      return file;
    } catch (e) {
      debugPrint('[Pixora] AURA download failed: $e');
      return null;
    }
  }

  Future<bool> isDownloaded(AuraTrack track) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/aura/${track.id}.mp3').exists();
  }
}
