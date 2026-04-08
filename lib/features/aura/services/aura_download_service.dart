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
      if (await file.exists()) return file;
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
