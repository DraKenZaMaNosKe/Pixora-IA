import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/supabase_config.dart';
import '../utils/locale_helper.dart';
import 'analytics_service.dart';
import 'push_notification_service.dart';

/// Immutable snapshot of the Free Hour state, consumed by the UI chip.
@immutable
class FreeHourState {
  const FreeHourState({
    required this.enabled,
    required this.isActive,
    required this.nextStart,
    required this.timeToNext,
    required this.remaining,
  });

  /// Feature is on (remote flag + valid config + service initialised).
  final bool enabled;

  /// We're inside the 30-minute ad-free window right now.
  final bool isActive;

  /// When the next (or current) Free Hour starts — local time. Null when the
  /// feature is disabled.
  final DateTime? nextStart;

  /// Countdown to [nextStart] (Duration.zero when active).
  final Duration timeToNext;

  /// Time left in the window (Duration.zero when idle).
  final Duration remaining;

  static const disabled = FreeHourState(
    enabled: false,
    isActive: false,
    nextStart: null,
    timeToNext: Duration.zero,
    remaining: Duration.zero,
  );
}

/// "Free Hour" — a daily 30-minute ad-free happy hour at a random time
/// (per-device, deterministic, computed OFFLINE). Designed by a Fable 5
/// subagent, reviewed by Opus. See tech memory when written.
///
/// Ships DORMANT: [enabled] is false unless a remote `free_hour_config.json`
/// with `"enabled": true` exists in Supabase Storage. No JSON / no network /
/// parse error → OFF → app behaves exactly as before. Kill-switch = edit the
/// JSON. This makes the feature purely additive and launch-safe.
class FreeHourService {
  FreeHourService._();
  static final FreeHourService instance = FreeHourService._();

  static const _boxName = 'free_hour';
  static const _kClockOffset = 'clock_offset_ms';
  static const _kConfig = 'config_json';

  // Remote config URL (public bucket, same base as the catalogs).
  static String get _configUrl =>
      '${SupabaseConfig.storageBase}/${SupabaseConfig.imagesBucket}/free_hour_config.json';

  // Config (defaults = OFF / launch-safe).
  bool _cfgEnabled = false;
  int _cfgDurationMin = 30;
  int _cfgStartHour = 7;
  int _cfgEndHour = 23;
  bool _cfgNotify = true;

  Box<dynamic>? _box;
  Timer? _ticker;
  int _clockOffsetMs = 0;
  bool _initialized = false;
  bool _tzReady = false;
  String _deviceId = 'unknown';

  static const _notifIdToday = 9101;
  static const _notifIdTomorrow = 9102;

  /// Debug override via --dart-define=FREE_HOUR_DEBUG=active|soon|off.
  /// Only honoured in debug/profile builds.
  static const _debugOverride =
      String.fromEnvironment('FREE_HOUR_DEBUG', defaultValue: '');

  final ValueNotifier<FreeHourState> state =
      ValueNotifier<FreeHourState>(FreeHourState.disabled);

  /// SAFE before init: returns false until initialised + enabled. Fail-safe
  /// is always "ads behave normally", never "ads off by mistake".
  bool get isActive {
    if (!_initialized) return false;
    return _compute().isActive;
  }

  DateTime get nextFreeStart => _compute().nextStart ?? DateTime.now();
  Duration get remainingInWindow => _compute().remaining;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
      _clockOffsetMs = (_box?.get(_kClockOffset) as int?) ?? 0;
      _loadCachedConfig();
    } catch (_) {}
    try {
      _deviceId = AnalyticsService.instance.deviceId;
    } catch (_) {}
    _initialized = true;
    // Fire-and-forget: refresh remote config + clock offset, then schedule
    // notifications once the config is known. Doesn't block startup.
    unawaited(
        _refreshConfig().then((_) => _initTz().then((_) => _scheduleNotifs())));
    // Ticker recomputes state every 30s (minute-granular countdown is enough).
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _publish());
    _publish();
  }

  /// Called from the app lifecycle 'resumed' hook.
  Future<void> onAppResumed() async {
    if (!_initialized) return;
    await _refreshConfig();
    await _initTz();
    await _scheduleNotifs();
    _publish();
  }

  // ── Local scheduled notification (per-device, per-local-time) ──
  Future<void> _initTz() async {
    if (_tzReady) return;
    try {
      tzdata.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
      _tzReady = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[FreeHour] tz init failed: $e');
    }
  }

  Future<void> _scheduleNotifs() async {
    if (!_tzReady || !shouldNotify) return;
    try {
      final plugin = PushNotificationService.instance.localPlugin;
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final allowed = await android?.areNotificationsEnabled() ?? false;
      if (!allowed) return; // user denied — chip is still the source of truth

      await plugin.cancel(_notifIdToday);
      await plugin.cancel(_notifIdTomorrow);

      final title = LocaleHelper.pick(
          es: '¡Ya es tu Hora Free! 🎉', en: 'Your Free Hour is on! 🎉');
      final body = LocaleHelper.pick(
          es: '$_cfgDurationMin minutos sin anuncios. Aprovecha.',
          en: '$_cfgDurationMin ad-free minutes. Enjoy.');
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'pixora_free_hour',
          'Pixora · Hora Free',
          channelDescription: 'Aviso cuando empieza tu Hora Free sin anuncios',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      );

      final now = _now();
      final today = _scheduleFor(now);
      // Today's, only if still ahead.
      if (now.isBefore(today.start)) {
        await plugin.zonedSchedule(
          _notifIdToday,
          title,
          body,
          tz.TZDateTime.from(today.start, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
      // Tomorrow's — so a user who doesn't open the app tomorrow still gets it.
      final tomorrow = _scheduleFor(now.add(const Duration(days: 1)));
      await plugin.zonedSchedule(
        _notifIdTomorrow,
        title,
        body,
        tz.TZDateTime.from(tomorrow.start, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[FreeHour] schedule notifs failed: $e');
    }
  }

  // ── Clock (anti-cheat, pragmatic) ──
  // Uses a server-time offset only if it's big (>5 min) — normal jitter trusts
  // the local clock. Airplane-mode + clock tampering can still force a window,
  // but the downside is 30 ad-free minutes, not worth more engineering.
  DateTime _now() {
    if (_clockOffsetMs.abs() > 5 * 60 * 1000) {
      return DateTime.now().add(Duration(milliseconds: _clockOffsetMs));
    }
    return DateTime.now();
  }

  // ── Deterministic schedule for a given local calendar day ──
  ({DateTime start, DateTime end}) _scheduleFor(DateTime day) {
    final dateKey =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final h = _fnv1a('$_deviceId|$dateKey');
    final minStart = _cfgStartHour * 60;
    final maxStart = _cfgEndHour * 60 - _cfgDurationMin;
    final span = (maxStart - minStart) <= 0 ? 1 : (maxStart - minStart + 1);
    final startMin = minStart + (h % span);
    final midnight = DateTime(day.year, day.month, day.day);
    final start = midnight.add(Duration(minutes: startMin));
    return (start: start, end: start.add(Duration(minutes: _cfgDurationMin)));
  }

  FreeHourState _compute() {
    // Debug override wins (debug/profile only).
    if (!kReleaseMode && _debugOverride.isNotEmpty) {
      final now = DateTime.now();
      if (_debugOverride == 'active') {
        return FreeHourState(
          enabled: true,
          isActive: true,
          nextStart: now,
          timeToNext: Duration.zero,
          remaining: Duration(minutes: _cfgDurationMin),
        );
      }
      if (_debugOverride == 'soon') {
        final s = now.add(const Duration(minutes: 2));
        return FreeHourState(
          enabled: true,
          isActive: false,
          nextStart: s,
          timeToNext: s.difference(now),
          remaining: Duration.zero,
        );
      }
      // 'off' falls through to disabled below.
    }

    if (!_cfgEnabled) {
      return FreeHourState(
        enabled: false,
        isActive: false,
        nextStart: _now(),
        timeToNext: Duration.zero,
        remaining: Duration.zero,
      );
    }

    final now = _now();
    final today = _scheduleFor(now);
    if (now.isBefore(today.start)) {
      return FreeHourState(
        enabled: true,
        isActive: false,
        nextStart: today.start,
        timeToNext: today.start.difference(now),
        remaining: Duration.zero,
      );
    }
    if (now.isBefore(today.end)) {
      return FreeHourState(
        enabled: true,
        isActive: true,
        nextStart: today.start,
        timeToNext: Duration.zero,
        remaining: today.end.difference(now),
      );
    }
    // Past today's window → tomorrow's (different hash → different time).
    final tomorrow = _scheduleFor(now.add(const Duration(days: 1)));
    return FreeHourState(
      enabled: true,
      isActive: false,
      nextStart: tomorrow.start,
      timeToNext: tomorrow.start.difference(now),
      remaining: Duration.zero,
    );
  }

  void _publish() {
    final s = _compute();
    final prev = state.value;
    // Only notify listeners on a visible change (minute countdown / active flip).
    final changed = prev.enabled != s.enabled ||
        prev.isActive != s.isActive ||
        prev.timeToNext.inMinutes != s.timeToNext.inMinutes ||
        prev.remaining.inMinutes != s.remaining.inMinutes;
    if (changed) state.value = s;
  }

  // ── Remote config + clock offset ──
  Future<void> _refreshConfig() async {
    try {
      final resp = await http
          .get(Uri.parse(
              '$_configUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 8));
      // Clock offset from the server Date header (best-effort anti-cheat).
      final dateHdr = resp.headers['date'];
      if (dateHdr != null) {
        try {
          final serverUtc = _httpDateParse(dateHdr);
          if (serverUtc != null) {
            _clockOffsetMs = serverUtc.millisecondsSinceEpoch -
                DateTime.now().toUtc().millisecondsSinceEpoch;
            _box?.put(_kClockOffset, _clockOffsetMs);
          }
        } catch (_) {}
      }
      if (resp.statusCode == 200) {
        _applyConfig(resp.body);
        _box?.put(_kConfig, resp.body);
      } else {
        // 404 / other → keep defaults (OFF). Do NOT wipe cache.
      }
    } catch (_) {
      // No network → keep cached config (loaded in init).
    }
    _publish();
  }

  void _loadCachedConfig() {
    final raw = _box?.get(_kConfig) as String?;
    if (raw != null) _applyConfig(raw);
  }

  void _applyConfig(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final enabled = j['enabled'] == true;
      final dur = (j['duration_min'] as num?)?.toInt() ?? 30;
      final sh = (j['window_start_hour'] as num?)?.toInt() ?? 7;
      final eh = (j['window_end_hour'] as num?)?.toInt() ?? 23;
      final notify = j['notify'] != false;
      // Validate — invalid config = OFF (structurally prevents cross-midnight).
      final valid = dur >= 5 &&
          dur <= 120 &&
          sh >= 0 &&
          sh < eh &&
          eh <= 24 &&
          (eh * 60 - dur) > (sh * 60);
      if (!valid) {
        _cfgEnabled = false;
        return;
      }
      _cfgEnabled = enabled;
      _cfgDurationMin = dur;
      _cfgStartHour = sh;
      _cfgEndHour = eh;
      _cfgNotify = notify;
    } catch (_) {
      _cfgEnabled = false;
    }
  }

  bool get shouldNotify => _cfgEnabled && _cfgNotify;
  int get durationMin => _cfgDurationMin;

  // FNV-1a 32-bit — stable across Dart SDK versions (String.hashCode isn't).
  int _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (final c in s.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}

/// Minimal RFC-1123 HTTP date parser (e.g. "Sun, 12 Jul 2026 20:40:35 GMT").
/// Returns UTC DateTime or null. Avoids adding an intl dependency here.
DateTime? _httpDateParse(String s) {
  try {
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(s);
    if (m == null) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      months[m.group(2)]!,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  } catch (_) {
    return null;
  }
}
