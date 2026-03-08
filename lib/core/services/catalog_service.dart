import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../constants/supabase_config.dart';
import '../../features/wallpapers/data/models/wallpaper.dart';

class CatalogService {
  CatalogService._();
  static final instance = CatalogService._();

  static const _cacheHours = 6;
  List<Wallpaper> _wallpapers = [];
  DateTime? _lastFetch;

  List<Wallpaper> get wallpapers => _wallpapers;

  bool get _isCacheValid =>
      _lastFetch != null &&
      DateTime.now().difference(_lastFetch!) < const Duration(hours: _cacheHours);

  Future<List<Wallpaper>> fetchCatalog({bool forceRefresh = false}) async {
    if (_wallpapers.isNotEmpty && _isCacheValid && !forceRefresh) {
      return _wallpapers;
    }

    try {
      // Try loading from network
      final url = SupabaseConfig.catalogUrl();
      final response = await http.get(
        Uri.parse(url),
        headers: {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['wallpapers'] as List<dynamic>;
        _wallpapers = list
            .map((e) => Wallpaper.fromJson(e as Map<String, dynamic>))
            .toList();
        _wallpapers.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        _lastFetch = DateTime.now();

        // Save to local cache
        await _saveToCache(response.body);

        debugPrint('[Pixora] Catalog loaded: ${_wallpapers.length} wallpapers');
        return _wallpapers;
      }
    } catch (e) {
      debugPrint('[Pixora] Network fetch failed: $e');
    }

    // Fallback to local cache
    final cached = await _loadFromCache();
    if (cached != null) {
      _wallpapers = cached;
      debugPrint('[Pixora] Loaded ${_wallpapers.length} wallpapers from cache');
    }

    return _wallpapers;
  }

  Future<void> _saveToCache(String json) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/catalog_cache.json');
      await file.writeAsString(json);
    } catch (_) {}
  }

  Future<List<Wallpaper>?> _loadFromCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/catalog_cache.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final list = json['wallpapers'] as List<dynamic>;
        final wallpapers = list
            .map((e) => Wallpaper.fromJson(e as Map<String, dynamic>))
            .toList();
        wallpapers.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return wallpapers;
      }
    } catch (_) {}
    return null;
  }
}
