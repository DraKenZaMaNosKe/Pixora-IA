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

  // Config (defaults = OFF / launch-safe). Fixed daily happy hour at
  // _cfgHour:_cfgMinute LOCAL time (8:00 PM) — same wall-clock everywhere, so
  // across Mexico/LATAM it lands in each user's evening at home.
  bool _cfgEnabled = false;
  int _cfgDurationMin = 7;
  int _cfgHour = 20;
  int _cfgMinute = 0;
  bool _cfgNotify = true;

  Box<dynamic>? _box;
  Timer? _ticker;
  int _clockOffsetMs = 0;
  bool _initialized = false;
  bool _tzReady = false;
  // Debug 'soon' mode: forces a Free Hour to start ~1 min from app launch, so
  // the whole flow (notification → active window → no ads) can be tested now.
  DateTime? _debugStart;
  // True once we've fired the "window started" notification for the current
  // window (reset when it ends). Prevents duplicates on every 30s tick.
  bool _notifiedThisWindow = false;

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
    _initialized = true;
    // Debug modes (debug/profile only): force the feature on for testing.
    if (!kReleaseMode && _debugOverride == 'soon') {
      _cfgEnabled = true;
      _cfgNotify = true;
      // Start in ~1 min to test the full flow (countdown → notif → no ads).
      _debugStart = DateTime.now().add(const Duration(minutes: 1));
    } else if (!kReleaseMode && _debugOverride == 'active') {
      _cfgEnabled = true;
    }
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
      final debugSoon = !kReleaseMode && _debugStart != null;
      final startToday = debugSoon ? _debugStart! : _scheduleForDay(now).start;
      // Today's window (or the debug one), only if still ahead.
      if (startToday.isAfter(now)) {
        await plugin.zonedSchedule(
          _notifIdToday,
          title,
          body,
          tz.TZDateTime.from(startToday, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
      // Tomorrow's — so a user who doesn't open the app tomorrow still gets it.
      // Skipped in debug 'soon' (we only want the one imminent test notif).
      if (!debugSoon) {
        final tomorrow = _scheduleForDay(now.add(const Duration(days: 1)));
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
      }
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

  // ── Fixed daily happy hour at _cfgHour:_cfgMinute LOCAL time ──
  ({DateTime start, DateTime end}) _scheduleForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day, _cfgHour, _cfgMinute);
    return (start: start, end: start.add(Duration(minutes: _cfgDurationMin)));
  }

  FreeHourState _compute() {
    // Debug 'active' wins — always inside the window (debug/profile only).
    if (!kReleaseMode && _debugOverride == 'active') {
      final now = DateTime.now();
      return FreeHourState(
        enabled: true,
        isActive: true,
        nextStart: now,
        timeToNext: Duration.zero,
        remaining: Duration(minutes: _cfgDurationMin),
      );
    }
    // Debug 'soon' — real countdown to _debugStart, then a real window, so the
    // whole flow (notif → active → no ads) plays out in ~2 min.
    if (!kReleaseMode && _debugStart != null) {
      final now = DateTime.now();
      final start = _debugStart!;
      final end = start.add(Duration(minutes: _cfgDurationMin));
      if (now.isBefore(start)) {
        return FreeHourState(
            enabled: true,
            isActive: false,
            nextStart: start,
            timeToNext: start.difference(now),
            remaining: Duration.zero);
      }
      if (now.isBefore(end)) {
        return FreeHourState(
            enabled: true,
            isActive: true,
            nextStart: start,
            timeToNext: Duration.zero,
            remaining: end.difference(now));
      }
      // Past the debug window → fall through (disabled unless remote cfg on).
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
    final today = _scheduleForDay(now);
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
    // Past today's window → tomorrow at the same fixed time.
    final tomorrow = _scheduleForDay(now.add(const Duration(days: 1)));
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

    // Window just started (app is alive) → fire an IMMEDIATE local notification.
    // This is the reliable path on MIUI/Huawei where scheduled-inexact notifs
    // get killed; the scheduled one is a best-effort fallback for app-closed.
    if (!prev.isActive && s.isActive && shouldNotify && !_notifiedThisWindow) {
      _notifiedThisWindow = true;
      unawaited(_showNowNotif());
    }
    if (prev.isActive && !s.isActive) _notifiedThisWindow = false;
  }

  Future<void> _showNowNotif() async {
    try {
      await PushNotificationService.instance.localPlugin.show(
        9103,
        LocaleHelper.pick(
            es: '¡Ya es tu Hora Free! 🎉', en: 'Your Free Hour is on! 🎉'),
        LocaleHelper.pick(
            es: '$_cfgDurationMin minutos sin anuncios. Aprovecha.',
            en: '$_cfgDurationMin ad-free minutes. Enjoy.'),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'pixora_free_hour',
            'Pixora · Hora Free',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (_) {}
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
      final dur = (j['duration_min'] as num?)?.toInt() ?? 7;
      final hour = (j['hour'] as num?)?.toInt() ?? 20;
      final minute = (j['minute'] as num?)?.toInt() ?? 0;
      final notify = j['notify'] != false;
      // Validate — invalid config = OFF. Window must fit before midnight.
      final valid = dur >= 1 &&
          dur <= 240 &&
          hour >= 0 &&
          hour <= 23 &&
          minute >= 0 &&
          minute < 60 &&
          (hour * 60 + minute + dur) <= 24 * 60;
      if (!valid) {
        _cfgEnabled = false;
        return;
      }
      _cfgEnabled = enabled;
      _cfgDurationMin = dur;
      _cfgHour = hour;
      _cfgMinute = minute;
      _cfgNotify = notify;
    } catch (_) {
      _cfgEnabled = false;
    }
  }

  bool get shouldNotify => _cfgEnabled && _cfgNotify;
  int get durationMin => _cfgDurationMin;
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
