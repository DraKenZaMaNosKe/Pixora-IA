import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_service.dart';

/// Presence heartbeat (F1) — reports "this device is alive right now" to the
/// `usage_report` RPC every 60s while the app is in the FOREGROUND. Credits are
/// ALWAYS empty here: real usage-time accounting is the wallpaper service's job
/// (UsageAccountant). This only keeps `device_presence.last_seen` fresh so the
/// admin's "En Vivo" panel shows who is online in real time.
///
/// Reuses AnalyticsService's `device_id` (same Hive box) so a device is the
/// same identity across app_events / wallpaper_events / presence.
///
/// Design by a Fable 5 subagent. See project_presence_usage_tracking memory.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final instance = PresenceService._();

  static const Duration _interval = Duration(seconds: 60);
  Timer? _timer;
  String? _appVersion;
  bool _started = false;

  Future<void> init() async {
    if (_started || !Platform.isAndroid) return;
    _started = true;
    try {
      final pkg = await PackageInfo.fromPlatform();
      _appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}
    WidgetsBinding.instance.addObserver(this);
    _startTicking();
    unawaited(_ping()); // immediate first beat
  }

  void _startTicking() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _ping());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTicking();
      unawaited(_ping());
    } else {
      // paused / inactive / detached / hidden → stop pinging (device isn't
      // "actively online"; the wallpaper service keeps its own accounting).
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _ping() async {
    try {
      final did = AnalyticsService.instance.deviceId;
      if (did.isEmpty) return;
      await Supabase.instance.client.rpc('usage_report', params: {
        'p_device_id': did,
        'p_state': {
          'source': 'app',
          if (_appVersion != null) 'app_version': _appVersion,
        },
        'p_credits': const <dynamic>[],
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Presence] ping failed: $e');
    }
  }

  /// Fire an immediate heartbeat that INCLUDES the active wallpaper, called the
  /// moment the user applies one. The periodic beat deliberately omits active_*
  /// (would go stale vs Daily rotation); usage_report merges by key presence,
  /// so this partial state only touches active_kind/active_wallpaper_id.
  Future<void> reportApplied(String contentId, {required String kind}) async {
    try {
      final did = AnalyticsService.instance.deviceId;
      if (did.isEmpty || contentId.isEmpty) return;
      await Supabase.instance.client.rpc('usage_report', params: {
        'p_device_id': did,
        'p_state': {
          'source': 'app',
          if (_appVersion != null) 'app_version': _appVersion,
          'active_kind': kind,
          'active_wallpaper_id': contentId,
          'wallpaper_set_at': DateTime.now().toUtc().toIso8601String(),
        },
        'p_credits': const <dynamic>[],
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Presence] reportApplied failed: $e');
    }
  }
}
