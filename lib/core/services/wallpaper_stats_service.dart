import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_service.dart';
import 'mystery_exclusion_service.dart';
import 'presence_service.dart';

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

  // 2026-06-13 — Discrete event stream para alimentar animaciones.
  // statsStream emite snapshots completos del cache; las animaciones
  // necesitan SABER QUE PASO (like +1 vs view +1) para disparar el
  // efecto visual correcto. Este stream emite eventos atomicos cada
  // vez que algo cambia, con isLocal=true cuando el tap viene del
  // usuario actual (optimistic) y false cuando llego via Realtime
  // (otro device dio like).
  final _eventController = StreamController<StatEvent>.broadcast();
  Stream<StatEvent> get statsEventStream => _eventController.stream;

  RealtimeChannel? _channel;
  Box? _likesBox;
  bool _initialized = false;
  bool _disposed = false;

  /// Initialize: fetch all stats, subscribe to realtime, open likes box.
  Future<void> init() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    _likesBox = await Hive.openBox('wallpaper_likes');
    unawaited(_migrateDeviceIdOnce());

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
            debugPrint(
                '[PixoraStats] RT UPDATE recv: ${payload.newRecord['wallpaper_id']} '
                'L=${payload.newRecord['likes']} D=${payload.newRecord['downloads']} '
                'V=${payload.newRecord['views']}');
            _applyRealtimeStats(payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'wallpaper_stats',
          callback: (payload) {
            debugPrint(
                '[PixoraStats] RT INSERT recv: ${payload.newRecord['wallpaper_id']}');
            _applyRealtimeStats(payload.newRecord);
          },
        )
        .subscribe((status, [err]) {
      debugPrint(
          '[PixoraStats] channel status=$status${err != null ? " err=$err" : ""}');
    });
    debugPrint('[PixoraStats] init OK — ${_cache.length} rows cached, '
        'channel subscribing…');
  }

  /// 2026-06-13 — handler unico para UPDATE + INSERT del realtime.
  ///
  /// Ademas de actualizar el cache y emitir el snapshot via statsStream
  /// (comportamiento original), DIFFEA contra el valor previo del cache
  /// para emitir StatEvent discretos por cada delta detectado. Esto es
  /// lo que alimenta las animaciones de like/view en tiempo real:
  /// cuando otro usuario en otro device le da like a un wallpaper,
  /// Realtime trae el row actualizado, comparamos contra el cached
  /// anterior, y si subio likes -> emit StatEvent('like', delta, remote).
  ///
  /// IMPORTANTE: marca el evento como isLocal=false porque viene del
  /// servidor. Los optimistic updates locales emiten su propio evento
  /// con isLocal=true desde toggleLike() y _bumpLocalStat().
  void _applyRealtimeStats(Map<String, dynamic> row) {
    final id = row['wallpaper_id'] as String?;
    if (id == null) return;
    final prev = _cache[id] ?? const {'likes': 0, 'downloads': 0, 'views': 0};
    final next = {
      'likes': row['likes'] as int? ?? 0,
      'downloads': row['downloads'] as int? ?? 0,
      'views': row['views'] as int? ?? 0,
    };
    _cache[id] = next;
    _statsController.add(Map.from(_cache));

    // Diff vs prev → emit discrete events for animations.
    // Si el delta es 0 (el server confirma un cambio que ya hicimos
    // localmente con optimistic), NO emitimos otro evento — ya hubo uno
    // local que dispara la animacion.
    for (final type in ['likes', 'downloads', 'views']) {
      final delta = (next[type] ?? 0) - (prev[type] ?? 0);
      if (delta == 0) continue;
      final eventType = _eventTypeFor(type, delta);
      final ev = StatEvent(
        wallpaperId: id,
        type: eventType,
        delta: delta,
        newValue: next[type] ?? 0,
        isLocal: false,
      );
      debugPrint('[PixoraStats] EMIT realtime $ev');
      _eventController.add(ev);
    }
  }

  String _eventTypeFor(String counterKey, int delta) {
    switch (counterKey) {
      case 'likes':
        return delta > 0 ? 'like' : 'unlike';
      case 'views':
        return 'view';
      case 'downloads':
        return 'download';
      default:
        return counterKey;
    }
  }

  /// Get stats for a wallpaper (from cache).
  Map<String, int> getStats(String wallpaperId) {
    return _cache[wallpaperId] ?? {'likes': 0, 'downloads': 0, 'views': 0};
  }

  /// Check if current device has liked this wallpaper.
  bool hasLiked(String wallpaperId) {
    return _likesBox?.get('liked_$wallpaperId', defaultValue: false) ?? false;
  }

  /// Device ID for anonymous like/event tracking.
  ///
  /// 2026-07-26 — Unified with the canonical AnalyticsService id (same id the
  /// heartbeat/presence uses) so events + presence correlate. The old legacy
  /// key `device_id` in the likes box is preserved (not deleted) and used only
  /// by the one-shot server-side migration in [_migrateDeviceIdOnce].
  String get _deviceId => AnalyticsService.instance.deviceId;

  /// One-shot server-side migration of the legacy stats id → canonical id.
  /// Renames this device's wallpaper_likes + wallpaper_events rows so its
  /// history isn't split. Idempotent server-side; the local flag is only set
  /// on a 2xx so a failure retries next cold start. Legacy key is kept.
  Future<void> _migrateDeviceIdOnce() async {
    try {
      if (_likesBox?.get('device_id_migrated_v1') == true) return;
      final legacy = _likesBox?.get('device_id') as String?;
      final canonical = AnalyticsService.instance.deviceId;
      if (legacy == null || legacy.isEmpty || legacy == canonical) {
        await _likesBox?.put('device_id_migrated_v1', true);
        return;
      }
      await _client.rpc('migrate_device_identity', params: {
        'p_old': legacy,
        'p_new': canonical,
      });
      await _likesBox?.put('device_id_migrated_v1', true);
    } catch (e) {
      debugPrint('[Stats] device_id migration deferred: $e');
      // do NOT set the flag → retried on next cold start
    }
  }

  /// 2026-06-13 — Set the absolute liked state for a wallpaper.
  ///
  /// Use this when an EXTERNAL system (favoritesProvider) has already
  /// decided the new state and just wants WallpaperStatsService to follow.
  /// Without this method, calling toggleLike() would consult ITS OWN Hive
  /// box (which can be out-of-sync with favorites) and end up incrementing
  /// when it should decrement (or vice versa), making the global counter
  /// drift opposite to the heart icon the user sees.
  ///
  /// Idempotent: if the desired state already matches local state, no-ops.
  Future<void> setLiked(String wallpaperId, bool liked) async {
    final currentlyLiked = hasLiked(wallpaperId);
    if (currentlyLiked == liked) return; // already in sync, nothing to do
    // Delegate to toggleLike — it will flip from currentlyLiked → !currentlyLiked
    // which equals the desired `liked`. We just verified the precondition.
    await toggleLike(wallpaperId);
  }

  /// 2026-06-13 — Anti double-tap mutex. Si dos taps rapidos disparan dos
  /// toggleLike concurrentes para el MISMO wallpaper, ambos leen hasLiked()
  /// = false ANTES de que cualquiera haga el Hive put, y ambos aplican
  /// optimistic +1 → cache muestra +2 aunque server queda en +1 (porque el
  /// segundo .put true ya no cambia nada y el segundo RPC tampoco mueve el
  /// stat de manera coherente). Serializamos por wallpaperId: el segundo
  /// tap espera al primero y retorna su resultado sin duplicar.
  final Map<String, Future<bool>> _toggleLocks = {};

  /// Toggle like on a wallpaper. Returns true if now liked.
  Future<bool> toggleLike(String wallpaperId) async {
    final pending = _toggleLocks[wallpaperId];
    if (pending != null) return pending;
    final future = _doToggleLike(wallpaperId);
    _toggleLocks[wallpaperId] = future;
    try {
      return await future;
    } finally {
      _toggleLocks.remove(wallpaperId);
    }
  }

  Future<bool> _doToggleLike(String wallpaperId) async {
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
        // 2026-06-13 — emit StatEvent local para alimentar animaciones.
        _eventController.add(StatEvent(
          wallpaperId: wallpaperId,
          type: 'unlike',
          delta: -1,
          newValue: s['likes'] ?? 0,
          isLocal: true,
        ));
      }
      return false;
    } else {
      // Like
      await _likesBox?.put('liked_$wallpaperId', true);
      try {
        await _client
            .rpc('increment_likes', params: {'p_wallpaper_id': wallpaperId});
        // 2026-06-13 fix — sin onConflict, Supabase usaba el PK (id) por
        // default; como no enviamos id, se generaba nuevo cada vez → INSERT
        // → chocaba con UNIQUE(device_id, wallpaper_id) y throw → el
        // try/catch lo silenciaba. Resultado: el RPC subia el contador en
        // wallpaper_stats pero la tabla wallpaper_likes seguia vacia.
        // Especificar onConflict matchea el constraint correcto y el upsert
        // se vuelve idempotente.
        await _client.from('wallpaper_likes').upsert(
          {
            'device_id': _deviceId,
            'wallpaper_id': wallpaperId,
            'user_id': _client.auth.currentUser?.id,
          },
          onConflict: 'device_id,wallpaper_id',
        );
      } catch (e) {
        debugPrint('[Pixora] Like failed: $e');
      }
      // Optimistic local update
      final s = _cache[wallpaperId] ?? {'likes': 0, 'downloads': 0, 'views': 0};
      s['likes'] = ((s['likes'] ?? 0) + 1);
      _cache[wallpaperId] = s;
      _statsController.add(Map.from(_cache));
      // 2026-06-13 — emit StatEvent local para alimentar animaciones.
      _eventController.add(StatEvent(
        wallpaperId: wallpaperId,
        type: 'like',
        delta: 1,
        newValue: s['likes'] ?? 0,
        isLocal: true,
      ));
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
    _eventController.add(StatEvent(
      wallpaperId: wallpaperId,
      type: 'download',
      delta: 1,
      newValue: s['downloads'] ?? 0,
      isLocal: true,
    ));
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
    _eventController.add(StatEvent(
      wallpaperId: wallpaperId,
      type: 'view',
      delta: 1,
      newValue: s['views'] ?? 0,
      isLocal: true,
    ));
  }

  /// Track when a wallpaper is actually applied to the home screen.
  ///
  /// Side effect: 2026-06-24 — agrega el ID al MysteryExclusionService
  /// para que NUNCA vuelva a aparecer como mystery card (ya lo viste y
  /// te lo gustaba lo suficiente para instalarlo). Defensive try-catch
  /// para que un fallo de Hive no rompa el tracking principal.
  Future<void> trackInstall(String wallpaperId) async {
    await _logEvent(wallpaperId, 'install');
    // 2026-07-26 — report the active wallpaper to presence so "En Vivo" shows
    // it. Skip ringtones/stories/ai (not wallpapers). The precise kind is
    // corrected shortly after by UsageAccountant (wallpaper service).
    if (!wallpaperId.startsWith('tone_') &&
        !wallpaperId.startsWith('story_') &&
        wallpaperId != 'ai_generated') {
      unawaited(
          PresenceService.instance.reportApplied(wallpaperId, kind: 'static'));
    }
    try {
      unawaited(MysteryExclusionService.instance.exclude(wallpaperId));
    } catch (e) {
      debugPrint('[Stats] mystery exclude failed: $e');
    }
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
    if (!_eventController.isClosed) {
      _eventController.close();
    }
    _likesBox?.close();
    _likesBox = null;
    _initialized = false;
  }
}

/// Evento discreto disparado cada vez que cambia un counter (likes/views/
/// downloads) — alimenta las animaciones de reactividad en tiempo real.
///
/// Diferencia clave vs statsStream: este emite UN evento por mutacion
/// con delta y origen claro, en lugar de snapshots completos del cache.
/// Asi las animaciones saben si fue un +1 like, un +1 view, o un -1
/// unlike, y si vino del tap del usuario actual o de Realtime.
class StatEvent {
  /// Wallpaper afectado.
  final String wallpaperId;

  /// 'like' / 'unlike' / 'view' / 'download'.
  final String type;

  /// Diferencia aplicada (+1, -1, +3 si es catch-up de varios likes).
  final int delta;

  /// Valor nuevo del counter despues de aplicar el delta.
  final int newValue;

  /// true = el evento lo disparo el usuario actual (optimistic local).
  /// false = llego via Supabase Realtime (otro device dio like/view).
  ///
  /// Las animaciones pueden tratar distinto cada caso: el like local
  /// suele tener un efecto MAS impactante (Heart Burst grande) porque
  /// el usuario lo provoco; el like remoto es mas sutil (Pulse Border)
  /// porque es ambient (alguien mas existe).
  final bool isLocal;

  const StatEvent({
    required this.wallpaperId,
    required this.type,
    required this.delta,
    required this.newValue,
    required this.isLocal,
  });

  @override
  String toString() =>
      'StatEvent($type ${delta > 0 ? '+' : ''}$delta on $wallpaperId → $newValue, ${isLocal ? "local" : "remote"})';
}
