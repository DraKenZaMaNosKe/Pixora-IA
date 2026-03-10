import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../constants/supabase_config.dart';
import '../../features/stories/data/models/story.dart';

class StoryCatalogService {
  StoryCatalogService._();
  static final instance = StoryCatalogService._();

  static const _cacheHours = 6;
  static const _catalogFile = 'stories_catalog.json';

  List<Story> _stories = [];
  DateTime? _lastFetch;

  List<Story> get stories => _stories;

  bool get _isCacheValid =>
      _lastFetch != null &&
      DateTime.now().difference(_lastFetch!) < const Duration(hours: _cacheHours);

  Future<List<Story>> fetchCatalog({bool forceRefresh = false}) async {
    if (_stories.isNotEmpty && _isCacheValid && !forceRefresh) {
      return _stories;
    }

    try {
      // Try loading from network
      final url = '${SupabaseConfig.storageBase}/${SupabaseConfig.imagesBucket}/$_catalogFile';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final json = jsonDecode(body) as Map<String, dynamic>;
        final list = json['stories'] as List<dynamic>;
        _stories = list
            .map((e) => Story.fromJson(e as Map<String, dynamic>))
            .toList();
        _lastFetch = DateTime.now();

        // Save to local cache
        await _saveToCache(body);

        debugPrint('[Pixora] Stories catalog loaded: ${_stories.length} stories');
        return _stories;
      }
    } catch (e) {
      debugPrint('[Pixora] Stories network fetch failed: $e');
    }

    // Fallback to local cache
    final cached = await _loadFromCache();
    if (cached != null) {
      _stories = cached;
      debugPrint('[Pixora] Loaded ${_stories.length} stories from cache');
    }

    return _stories;
  }

  Future<void> _saveToCache(String json) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/stories_cache.json');
      await file.writeAsString(json);
    } catch (_) {}
  }

  Future<List<Story>?> _loadFromCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/stories_cache.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final list = json['stories'] as List<dynamic>;
        return list
            .map((e) => Story.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return null;
  }
}
