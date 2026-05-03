import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wallpaper stats with real-time updates via Supabase Realtime.
class WallpaperStatsService {
  WallpaperStatsService._();
  static final instance = WallpaperStatsService._();

  SupabaseClient get _client => Supabase.instance.client;

  // Cached app version, populated lazily once per session
  String? _appVersion;
  Future<String> _getAppVersion() async {
    if (_appVersion != null) return _appVersion!;
    try {
      final pkg = await PackageInfo.fromPlatform();
      _appVersion = pkg.version;
    } catch (_) {
      _appVersion = 'unknown';
    }
    return _appVersion!;
  }

  // In-memory cache: wallpaperId -> {likes, downloads, views}
  final Map<String, Map<String, int>> _cache = {};

  // Stream controllers for real-time updates
  final _statsController =
      StreamController<Map<String, Map<String, int>>>.broadcast();
  Stream<Map<String, Map<String, int>>> get statsStream =>
      _statsController.stream;

  RealtimeChannel? _channel;
  Box? _likesBox;
  bool _initialized = false;
  bool _disposed = false;

  /// Initialize: fetch all stats, subscribe to realtime, open likes box.
  Future<void> init() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    _likesBox = await Hive.openBox('wallpaper_likes');

    // Fetch all stats
    try {
      final data = await _client
          .from('wallpaper_stats')
          .select('wallpaper_id, likes, downloads, views');

      for (final row in data as List) {
        _cache[row['wallpaper_id'] as String] = {
          'likes': row['likes'] as int? ?? 0,
          'downloads': row['downloads'] as int? ?? 0,
          'views': row['views'] as int? ?? 0,
        };
      }
      _statsController.add(Map.from(_cache));
    } catch (e) {
      debugPrint('[Pixora] Stats fetch failed: $e');
    }

    // Subscribe to realtime changes
    _channel = _client.channel('wallpaper_stats_realtime');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'wallpaper_stats',
          callback: (payload) {
            final row = payload.newRecord;
            final id = row['wallpaper_id'] as String?;
            if (id != null) {
              _cache[id] = {
                'likes': row['likes'] as int? ?? 0,
                'downloads': row['downloads'] as int? ?? 0,
                'views': row['views'] as int? ?? 0,
              };
              _statsController.add(Map.from(_cache));
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'wallpaper_stats',
          callback: (payload) {
            final row = payload.newRecord;
            final id = row['wallpaper_id'] as String?;
            if (id != null) {
              _cache[id] = {
                'likes': row['likes'] as int? ?? 0,
                'downloads': row['downloads'] as int? ?? 0,
                'views': row['views'] as int? ?? 0,
              };
              _statsController.add(Map.from(_cache));
            }
          },
        )
        .subscribe();
  }

  /// Get stats for a wallpaper (from cache).
  Map<String, int> getStats(String wallpaperId) {
    return _cache[wallpaperId] ?? {'likes': 0, 'downloads': 0, 'views': 0};
  }

  /// Check if current device has liked this wallpaper.
  bool hasLiked(String wallpaperId) {
    return _likesBox?.get('liked_$wallpaperId', defaultValue: false) ?? false;
  }

  /// Device ID for anonymous like tracking.
  String get _deviceId {
    var id = _likesBox?.get('device_id') as String?;
    if (id == null) {
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      _likesBox?.put('device_id', id);
    }
    return id;
  }

  /// Toggle like on a wallpaper. Returns true if now liked.
  Future<bool> toggleLike(String wallpaperId) async {
    final liked = hasLiked(wallpaperId);

    if (liked) {
      // Unlike
      await _likesBox?.put('liked_$wallpaperId', false);
      try {
        await _client
            .rpc('decrement_likes', params: {'p_wallpaper_id': wallpaperId});
        await _client
            .from('wallpaper_likes')
            .delete()
            .eq('device_id', _deviceId)
            .eq('wallpaper_id', wallpaperId);
      } catch (e) {
        debugPrint('[Pixora] Unlike failed: $e');
      }
      // Optimistic local update
      final s = _cache[wallpaperId];
      if (s != null) {
        s['likes'] = ((s['likes'] ?? 0) - 1).clamp(0, 999999);
        _statsController.add(Map.from(_cache));
      }
      return false;
    } else {
      // Like
      await _likesBox?.put('liked_$wallpaperId', true);
      try {
        await _client
            .rpc('increment_likes', params: {'p_wallpaper_id': wallpaperId});
        await _client.from('wallpaper_likes').upsert({
          'device_id': _deviceId,
          'wallpaper_id': wallpaperId,
          'user_id': _client.auth.currentUser?.id,
        });
      } catch (e) {
        debugPrint('[Pixora] Like failed: $e');
      }
      // Optimistic local update
      final s = _cache[wallpaperId] ?? {'likes': 0, 'downloads': 0, 'views': 0};
      s['likes'] = ((s['likes'] ?? 0) + 1);
      _cache[wallpaperId] = s;
      _statsController.add(Map.from(_cache));
      return true;
    }
  }

  /// Log a granular event to wallpaper_events + bump cached counter.
  /// Single entry point for view/install/share/download/favorite/etc.
  Future<void> _logEvent(String wallpaperId, String eventType,
      {Map<String, dynamic>? metadata}) async {
    try {
      await _client.rpc('wp_log_event', params: {
        'p_wallpaper_id': wallpaperId,
        'p_event_type': eventType,
        'p_device_id': _deviceId,
        'p_app_version': await _getAppVersion(),
        if (metadata != null) 'p_metadata': metadata,
      });
    } catch (e) {
      debugPrint('[Pixora] wp_log_event($eventType) failed: $e');
    }
  }

  /// Increment download count.
  Future<void> trackDownload(String wallpaperId) async {
    // New analytics path
    await _logEvent(wallpaperId, 'download');
    // Legacy stats table (kept until migration is fully consolidated)
    try {
      await _client
          .rpc('increment_downloads', params: {'p_wallpaper_id': wallpaperId});
    } catch (e) {
      debugPrint('[Pixora] Track download (legacy) failed: $e');
    }
    final s = _cache[wallpaperId] ?? {'likes': 0, 'downloads': 0, 'views': 0};
    s['downloads'] = ((s['downloads'] ?? 0) + 1);
    _cache[wallpaperId] = s;
    _statsController.add(Map.from(_cache));
  }

  /// Increment view count.
  Future<void> trackView(String wallpaperId) async {
    await _logEvent(wallpaperId, 'view');
    try {
      await _client
          .rpc('increment_views', params: {'p_wallpaper_id': wallpaperId});
    } catch (e) {
      debugPrint('[Pixora] Track view (legacy) failed: $e');
    }
    final s = _cache[wallpaperId] ?? {'likes': 0, 'downloads': 0, 'views': 0};
    s['views'] = ((s['views'] ?? 0) + 1);
    _cache[wallpaperId] = s;
    _statsController.add(Map.from(_cache));
  }

  /// Track when a wallpaper is actually applied to the home screen.
  Future<void> trackInstall(String wallpaperId) async {
    await _logEvent(wallpaperId, 'install');
  }

  /// Track when a user shares a wallpaper.
  Future<void> trackShare(String wallpaperId) async {
    await _logEvent(wallpaperId, 'share');
  }

  /// Format number: 1500 -> "1.5K"
  static String formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  void dispose() {
    _disposed = true;
    _channel?.unsubscribe();
    _channel = null;
    if (!_statsController.isClosed) {
      _statsController.close();
    }
    _likesBox?.close();
    _likesBox = null;
    _initialized = false;
  }
}
