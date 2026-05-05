import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/supabase_config.dart';
import 'models/event.dart';

/// Fetches the seasonal events catalog from Supabase Storage.
/// Same pattern as LiveWallpaperCatalogService: single JSON file in the
/// wallpaper-images bucket, 6h in-memory cache, refreshed on demand.
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
  static const _cacheTtl = Duration(hours: 6);

  List<PixoraEvent>? _cached;
  DateTime? _cachedAt;

  String get _url =>
      '${SupabaseConfig.storageBase}/${SupabaseConfig.imagesBucket}/$_catalogFile';

  /// Returns the events list. Uses in-memory cache when fresh; fetches
  /// from network otherwise. On network failure, returns the last cache
  /// (even if stale) — never throws to the UI layer.
  Future<List<PixoraEvent>> getEvents({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null && _cachedAt != null) {
      if (DateTime.now().difference(_cachedAt!) < _cacheTtl) {
        return _cached!;
      }
    }
    try {
      final r =
          await http.get(Uri.parse(_url)).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) {
        debugPrint('[Events] catalog HTTP ${r.statusCode}');
        return _cached ?? const [];
      }
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final raw = json['events'] as List<dynamic>? ?? const [];
      final events = raw
          .whereType<Map<String, dynamic>>()
          .map(PixoraEvent.fromJson)
          .toList();
      _cached = events;
      _cachedAt = DateTime.now();
      debugPrint('[Events] catalog loaded: ${events.length} events');
      return events;
    } catch (e) {
      debugPrint('[Events] fetch error: $e');
      return _cached ?? const [];
    }
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
