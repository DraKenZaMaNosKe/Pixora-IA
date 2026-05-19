import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/constants/supabase_config.dart';
import '../../../core/services/catalog_cache_store.dart';
import 'models/event.dart';

/// Fetches the seasonal events catalog from Supabase Storage.
/// Tier 3 (2026-05-18): migrado a CatalogCacheStore para que el cache sea
/// Hive-backed y soporte ETag + FCM invalidation.
///
/// Server flow to add a new event: edit
///   tools/events/events_catalog.json
/// then run
///   python tools/events/upload_events_catalog.py
/// no APK rebuild required.
class EventsService {
  EventsService._();
  static final instance = EventsService._();

  static const _catalogFile = 'events_catalog.json';
  static const _cacheKey = 'images:events_catalog.json';
  static const _cacheTtl = Duration(hours: 6);

  List<PixoraEvent>? _cached;
  DateTime? _cachedAt;

  String get _url =>
      '${SupabaseConfig.storageBase}/${SupabaseConfig.imagesBucket}/$_catalogFile';

  /// Limpia el cache (memoria + Hive). Lo dispara el FCM
  /// `catalog_invalidate` scope=events|all.
  Future<void> clearCache() async {
    _cached = null;
    _cachedAt = null;
    await CatalogCacheStore.instance.clear(_cacheKey);
  }

  /// Returns the events list. Uses in-memory cache when fresh; otherwise
  /// goes through CatalogCacheStore (Hive + ETag HEAD check + network).
  /// On total failure returns the last cache or empty list.
  Future<List<PixoraEvent>> getEvents({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null && _cachedAt != null) {
      if (DateTime.now().difference(_cachedAt!) < _cacheTtl) {
        return _cached!;
      }
    }
    final result = await CatalogCacheStore.instance.fetchWithCache(
      key: _cacheKey,
      url: _url,
      ttl: _cacheTtl,
      forceRefresh: forceRefresh,
    );
    if (result.hasBody) {
      try {
        final data = jsonDecode(result.body!) as Map<String, dynamic>;
        final raw = data['events'] as List<dynamic>? ?? const [];
        final events = raw
            .whereType<Map<String, dynamic>>()
            .map(PixoraEvent.fromJson)
            .toList();
        _cached = events;
        _cachedAt = DateTime.now();
        debugPrint(
            '[Events] catalog loaded (${result.source.name}): ${events.length}');
        return events;
      } catch (e) {
        debugPrint('[Events] parse error: $e');
      }
    }
    return _cached ?? const [];
  }

  /// Find a single event by id. Triggers a fetch if cache is empty.
  Future<PixoraEvent?> findById(String id) async {
    final events = await getEvents();
    for (final e in events) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Convenience: just the events currently active (today is between
  /// starts_at and ends_at). Most apps will only ever care about this set.
  Future<List<PixoraEvent>> activeEvents() async {
    final all = await getEvents();
    return all.where((e) => e.isActive).toList();
  }
}
