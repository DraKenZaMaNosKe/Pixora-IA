import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../constants/supabase_config.dart';

class DownloadService {
  DownloadService._();
  static final instance = DownloadService._();

  /// Download wallpaper image and return local file path.
  /// Returns cached file if already downloaded.
  Future<String?> downloadWallpaper(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/wallpapers/$filename');

      if (await file.exists()) {
        return file.path;
      }

      await file.parent.create(recursive: true);

      final url = SupabaseConfig.imageUrl(filename);
      final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('[Pixora] Downloaded: $filename (${response.bodyBytes.length} bytes)');
        return file.path;
      }
    } catch (e) {
      debugPrint('[Pixora] Download failed: $e');
    }
    return null;
  }

  /// Clear all downloaded wallpapers
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
