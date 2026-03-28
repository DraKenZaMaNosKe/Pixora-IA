import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../constants/supabase_config.dart';
import '../../features/day_cycle/data/models/day_cycle_theme.dart';

class DayCycleCatalogService {
  DayCycleCatalogService._();
  static final instance = DayCycleCatalogService._();

  static const _cacheHours = 6;
  static const _catalogFile = 'day_cycle_catalog.json';

  List<DayCycleTheme> _themes = [];
  DateTime? _lastFetch;

  bool get _isCacheValid =>
      _lastFetch != null &&
      DateTime.now().difference(_lastFetch!) < const Duration(hours: _cacheHours);

  Future<List<DayCycleTheme>> fetchCatalog({bool forceRefresh = false}) async {
    if (_themes.isNotEmpty && _isCacheValid && !forceRefresh) return _themes;

    try {
      final url = '${SupabaseConfig.storageBase}/${SupabaseConfig.imagesBucket}/$_catalogFile';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final json = jsonDecode(body) as Map<String, dynamic>;
        final list = json['themes'] as List<dynamic>;
        _themes = list
            .map((e) => DayCycleTheme.fromJson(e as Map<String, dynamic>))
            .toList();
        _lastFetch = DateTime.now();
        await _saveToCache(body);
        debugPrint('[Pixora] Day cycle catalog loaded: ${_themes.length} themes');
        return _themes;
      }
    } catch (e) {
      debugPrint('[Pixora] Day cycle network fetch failed: $e');
    }

    final cached = await _loadFromCache();
    if (cached != null) {
      _themes = cached;
      debugPrint('[Pixora] Loaded ${_themes.length} day cycle themes from cache');
    }
    return _themes;
  }

  Future<void> _saveToCache(String json) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/day_cycle_cache.json');
      await file.writeAsString(json);
    } catch (_) {}
  }

  Future<List<DayCycleTheme>?> _loadFromCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/day_cycle_cache.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final list = json['themes'] as List<dynamic>;
        return list.map((e) => DayCycleTheme.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return null;
  }
}
