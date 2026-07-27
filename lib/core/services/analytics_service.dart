import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/supabase_config.dart';

/// Generic engagement analytics. One singleton, one queue, one flush loop.
///
/// Why this exists separately from `WallpaperStatsService`: that service
/// owns wallpaper-specific event tracking (view/install/share). This one
/// owns *everything else* — tab navigation, AURA listening time, tutorial
/// progress, subscription funnel, welcome gift redemption, event-section
/// engagement, etc.
///
/// Server contract: each event becomes a row in `public.app_events` via the
/// `app_log_events_batch` RPC. Schema is intentionally generic — `event_name`
/// is the catalog key, `props` is free-form JSON.
///
/// Usage:
/// ```dart
/// AnalyticsService.instance.track('tab_viewed', {'section': 'cultura'});
/// AnalyticsService.instance.track('event_followed', {'event_id': 'halloween_2026'});
/// ```
///
/// Flush triggers:
///   - Queue reaches `_flushAtSize` events
///   - Every `_flushInterval` (30s)
///   - App pause / lifecycle hint via `flushNow()`
///
/// On flush failure: events are kept in memory and retried on the next tick.
/// If the queue grows past `_maxQueueSize`, oldest events are dropped — we
/// would rather lose old engagement data than crash the app from OOM.
class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  static const String _hiveBoxName = 'analytics';
  static const String _deviceIdKey = 'device_id';
  static const Duration _flushInterval = Duration(seconds: 30);
  static const int _flushAtSize = 20;
  static const int _maxQueueSize = 500;

  Box<dynamic>? _box;
  String? _deviceIdCache;
  Timer? _timer;
  bool _initialized = false;
  bool _flushing = false;
  String? _appVersion;
  String? _sessionId;
  final List<_Event> _queue = [];

  /// Whether to print debug logs.
  final bool _verbose = kDebugMode;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _box = await Hive.openBox<dynamic>(_hiveBoxName);
    } catch (_) {
      // If Hive isn't ready, we still let track() queue in memory and try
      // to persist later. Device id will fall back to ephemeral.
    }
    _sessionId = _generateSessionId();
    try {
      final pkg = await PackageInfo.fromPlatform();
      _appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}
    _timer = Timer.periodic(_flushInterval, (_) => _flush());
    _log('init session=$_sessionId device=$deviceId version=$_appVersion');
    // Bridge our identity (device_id) + Supabase config to the isolated
    // :wallpaper process, which can't reach Hive. The UsageAccountant there
    // reads this flat file to attribute + report real usage time.
    unawaited(_writeIdentityFile());
  }

  /// Writes `pixora_identity.json` into the app support dir (== Android
  /// `context.filesDir`, the same dir the native side already reads for
  /// `auto_rotate_cache/` and `scene_specs/`). The isolated `:wallpaper`
  /// process reads it to get our `device_id` + the anon key needed to POST
  /// to the `usage_report` RPC — so the secret stays in one place (Supabase
  /// config) and never lands in a committed `.kt`.
  ///
  /// Atomic (tmp + rename). Rewritten every cold start so a regenerated
  /// device_id or a rotated anon key propagates. Best-effort: failures are
  /// swallowed — usage tracking degrades to offline accumulation, never a
  /// crash.
  Future<void> _writeIdentityFile() async {
    if (!Platform.isAndroid) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final payload = <String, dynamic>{
        'v': 1,
        'device_id': deviceId,
        'supabase_url': SupabaseConfig.projectUrl,
        'anon_key': SupabaseConfig.anonKey,
        'app_version': _appVersion,
        'written_at': DateTime.now().millisecondsSinceEpoch,
      };
      final tmp = File('${dir.path}/pixora_identity.json.tmp');
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      await tmp.rename('${dir.path}/pixora_identity.json');
      _log('identity file written');
    } catch (e) {
      _log('identity file write failed: $e');
    }
  }

  String get deviceId {
    final mem = _deviceIdCache;
    if (mem != null && mem.isNotEmpty) return mem;
    final cached = _box?.get(_deviceIdKey) as String?;
    if (cached != null && cached.isNotEmpty) {
      _deviceIdCache = cached;
      return cached;
    }
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        Random().nextInt(1 << 32).toRadixString(36);
    _deviceIdCache = id; // stable for this process even if Hive is down
    _box?.put(_deviceIdKey, id); // best-effort persist
    return id;
  }

  String _generateSessionId() {
    final r = Random();
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rnd = r.nextInt(1 << 32).toRadixString(36);
    return 's_${ts}_$rnd';
  }

  /// Queue a single event. Safe to call before init() — it just buffers
  /// in memory and will flush after init.
  void track(String eventName, [Map<String, dynamic>? props]) {
    if (eventName.isEmpty || eventName.length > 60) return;
    final event = _Event(
      name: eventName,
      props: props ?? const {},
      ts: DateTime.now(),
    );
    _queue.add(event);
    _log('track $eventName ${event.props}');

    // Drop oldest if queue is too big.
    while (_queue.length > _maxQueueSize) {
      _queue.removeAt(0);
    }

    if (_queue.length >= _flushAtSize) {
      // Don't await — keep track() synchronous-feeling.
      unawaited(_flush());
    }
  }

  // ── Convenience wrappers (named to make instrumentation sites obvious) ──

  void trackTabView(String section) =>
      track('tab_viewed', {'section': section});

  void trackEventOpened(String eventId) =>
      track('event_opened', {'event_id': eventId});

  void trackEventFollowed(String eventId) =>
      track('event_followed', {'event_id': eventId});

  void trackPitchShown(String source) =>
      track('pitch_shown', {'source': source});

  void trackPitchCtaTap() => track('pitch_cta_tap');

  void trackPitchPaid({String? productId}) =>
      track('pitch_paid', {if (productId != null) 'product_id': productId});

  void trackTutorialStarted() => track('tutorial_started');
  void trackTutorialStep(int index, String label) =>
      track('tutorial_step', {'index': index, 'label': label});
  void trackTutorialFinished() => track('tutorial_finished');
  void trackTutorialSkipped(int atStep) =>
      track('tutorial_skipped', {'at_step': atStep});

  void trackWelcomeGiftShown(String wallpaperId) =>
      track('welcome_gift_shown', {'wallpaper_id': wallpaperId});
  void trackWelcomeGiftRedeemed(String wallpaperId) =>
      track('welcome_gift_redeemed', {'wallpaper_id': wallpaperId});

  /// Heartbeat for AURA listening — call once every 30s while a track plays.
  /// One row per tick → server-side aggregation can compute approx minutes.
  void trackAuraPlayTick(String trackId, {String? frequency}) =>
      track('aura_play_tick', {
        'track_id': trackId,
        if (frequency != null) 'frequency': frequency,
      });

  void trackAuraStarted(String trackId) =>
      track('aura_started', {'track_id': trackId});

  /// Force a flush — use on app pause, on screen exit before push, etc.
  Future<void> flushNow() => _flush();

  Future<void> _flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    final batch = List<_Event>.from(_queue);
    try {
      final payload = batch
          .map((e) => {
                'name': e.name,
                'props': e.props,
                'ts': e.ts.toUtc().toIso8601String(),
              })
          .toList(growable: false);
      await Supabase.instance.client.rpc('app_log_events_batch', params: {
        'p_events': payload,
        'p_device_id': deviceId,
        'p_session_id': _sessionId,
        'p_app_version': _appVersion,
      });
      // Only remove the events we actually flushed. Keep ones that came in
      // during the flush — they'll go in the next batch.
      _queue.removeRange(0, batch.length);
      _log('flushed ${batch.length} events');
    } catch (e) {
      _log('flush failed: $e (will retry next tick)');
      // Don't drain the queue on failure. Next periodic tick will retry.
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_flush());
  }

  void _log(String msg) {
    if (_verbose) debugPrint('[Analytics] $msg');
  }
}

class _Event {
  _Event({required this.name, required this.props, required this.ts});
  final String name;
  final Map<String, dynamic> props;
  final DateTime ts;
}
