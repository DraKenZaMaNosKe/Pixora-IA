import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/aura_track.dart';

/// Fetches the AURA catalog from `public.aura_tracks`. 6h in-memory cache.
class AuraRepository {
  AuraRepository._();
  static final instance = AuraRepository._();

  List<AuraTrack>? _cache;
  DateTime? _lastFetch;
  static const _cacheHours = 6;

  Future<List<AuraTrack>> fetchCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cache != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inHours < _cacheHours) {
      return _cache!;
    }

    try {
      final rows = await Supabase.instance.client
          .from('aura_tracks')
          .select()
          .order('category')
          .order('sort_order');

      final tracks = (rows as List<dynamic>)
          .map((e) => AuraTrack.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache = tracks;
      _lastFetch = DateTime.now();
      return tracks;
    } catch (e) {
      debugPrint('[Pixora] AURA catalog fetch failed: $e');
      return _cache ?? [];
    }
  }

  /// Drop in-memory catalog cache so the next [fetchCatalog] call hits
  /// Postgres fresh. Called by [PushNotificationService] when an FCM
  /// `catalog_invalidate` push with scope `'aura'` arrives, after Eduardo
  /// adds/removes a track from the dashboard or backend script.
  Future<void> clearCache() async {
    _cache = null;
    _lastFetch = null;
  }

  List<AuraTrack> filterFrequencies(List<AuraTrack> all) =>
      all.where((t) => t.category == AuraCategory.frequency).toList();

  List<AuraTrack> filterNature(List<AuraTrack> all) =>
      all.where((t) => t.category == AuraCategory.nature).toList();
}
