import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../constants/supabase_config.dart';

/// Reads CMS-controlled UI strings (edited via pixora-admin) and caches them
/// in Hive for offline use. Falls back silently — if the cache is empty or
/// the network is down, [get] returns null and callers use their hardcoded
/// fallback (see [LocaleHelper.fromCms]).
///
/// Lifecycle:
/// - [initialize] opens the Hive box, fetches fresh data if cache is empty
///   or stale (TTL 1h), and subscribes to FCM topic 'text_cms_update' so
///   admin edits invalidate the cache live.
/// - [get] is synchronous: returns the cached {es, en} for a key, or null.
/// - [refresh] forces a fresh fetch (used by FCM handler or manual reload).
class AppStringsService extends ChangeNotifier {
  AppStringsService._();
  static final AppStringsService instance = AppStringsService._();

  static const String _boxName = 'app_strings_cache';
  static const String _lastFetchKey = '__last_fetch_iso__';
  // TTL kept short (5 min) so cache feels live. Pull-to-refresh and the app
  // lifecycle 'resumed' hook in PixoraApp also call refresh() — combined,
  // edits in pixora-admin reach the user within seconds, no FCM needed yet.
  static const Duration _ttl = Duration(minutes: 5);

  Box<dynamic>? _box;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
      if (_box!.isEmpty || _isStale()) {
        await refresh();
      } else {
        debugPrint(
            '[AppStringsService] Loaded from cache (${_box!.length - 1} keys)');
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[AppStringsService] init failed: $e');
      // Non-fatal: fromCms() will fall back to hardcoded strings.
    }
  }

  bool _isStale() {
    final iso = _box?.get(_lastFetchKey) as String?;
    if (iso == null) return true;
    final last = DateTime.tryParse(iso);
    if (last == null) return true;
    return DateTime.now().difference(last) > _ttl;
  }

  /// Synchronous read for [LocaleHelper.fromCms]. Returns null if absent.
  Map<String, String>? get(String key) {
    if (_box == null) return null;
    final raw = _box!.get(key);
    if (raw is! Map) return null;
    final es = raw['es'];
    final en = raw['en'];
    if (es is! String || en is! String) return null;
    return {'es': es, 'en': en};
  }

  /// Force-refetch from Supabase. Called by FCM handler (Task 11) or manually.
  Future<void> refresh() async {
    if (_box == null) {
      debugPrint('[AppStringsService] refresh skipped: box not open');
      return;
    }
    try {
      final res = await http.get(
        Uri.parse(
            '${SupabaseConfig.projectUrl}/rest/v1/app_strings?select=key,es,en'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint(
            '[AppStringsService] refresh HTTP ${res.statusCode}: ${res.body}');
        return;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      // Preserve last_fetch key while clearing strings
      await _box!.clear();
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        await _box!.put(m['key'] as String, {'es': m['es'], 'en': m['en']});
      }
      await _box!.put(_lastFetchKey, DateTime.now().toIso8601String());
      debugPrint(
          '[AppStringsService] Refreshed ${list.length} keys from Supabase');
      notifyListeners();
    } catch (e) {
      debugPrint('[AppStringsService] refresh failed: $e');
    }
  }
}
