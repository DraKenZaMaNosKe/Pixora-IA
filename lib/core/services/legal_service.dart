import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_service.dart';

/// Tracks Terms & Privacy acceptance per user/device.
///
/// Acceptance is **versioned**: bumping `kCurrentTermsVersion` makes every
/// existing user re-accept on next launch. The accepted version is stored in
/// Hive (so it survives app restarts) and asynchronously mirrored to a
/// Supabase table for legal evidence.
///
/// This service is intentionally tiny — the gate UI lives in
/// `lib/features/legal/terms_acceptance_page.dart`.
class LegalService extends ChangeNotifier {
  LegalService._();
  static final instance = LegalService._();

  /// Bump this constant whenever the published Terms or Privacy doc changes
  /// in a way that requires re-consent. Cosmetic edits that don't add new
  /// data uses or new clauses don't need a bump.
  static const int kCurrentTermsVersion = 1;

  /// Public URLs for the full legal documents. These point to Supabase
  /// Storage where the HTML versions of `docs/legal/terms_v1.md` and
  /// `docs/legal/privacy_v1.md` will be uploaded once the lawyer reviews.
  /// Until then we keep the URLs configurable here so we can swap them
  /// without touching the UI.
  static const String kTermsUrl =
      'https://intrapcsolutions.com/legal/terms_v1.html';
  static const String kPrivacyUrl =
      'https://intrapcsolutions.com/legal/privacy_v1.html';

  static const String _hiveBoxName = 'legal';
  static const String _versionKey = 'terms_accepted_version';
  static const String _acceptedAtKey = 'terms_accepted_at';

  Box<dynamic>? _box;
  bool _initialized = false;
  String? _appVersion;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _box = await Hive.openBox<dynamic>(_hiveBoxName);
    } catch (e) {
      debugPrint('[Legal] Hive init failed: $e');
    }
    try {
      final pkg = await PackageInfo.fromPlatform();
      _appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}
  }

  /// True if the device has already accepted the current Terms version.
  bool hasAcceptedCurrent() {
    final v = _box?.get(_versionKey);
    if (v is int) return v >= kCurrentTermsVersion;
    return false;
  }

  /// The version the user previously accepted (null if they never accepted).
  int? get acceptedVersion {
    final v = _box?.get(_versionKey);
    return v is int ? v : null;
  }

  /// Persist acceptance locally and mirror to Supabase. The Supabase write
  /// is fire-and-forget — if it fails we still consider the acceptance
  /// valid because Hive is the local source of truth and we can re-sync
  /// later. The user's tap is what counts; persistence is bookkeeping.
  Future<void> markAccepted() async {
    final now = DateTime.now().toUtc();
    try {
      await _box?.put(_versionKey, kCurrentTermsVersion);
      await _box?.put(_acceptedAtKey, now.toIso8601String());
    } catch (e) {
      debugPrint('[Legal] Hive write failed: $e');
    }
    notifyListeners();

    // Mirror to Supabase + analytics. Both are best-effort.
    unawaited(_logAcceptanceServer(now));
    AnalyticsService.instance.track('terms_accepted', {
      'version': kCurrentTermsVersion,
    });
  }

  /// Clears local acceptance — for QA/dev use, re-shows the gate next launch.
  Future<void> resetForDev() async {
    if (!kDebugMode) return;
    try {
      await _box?.delete(_versionKey);
      await _box?.delete(_acceptedAtKey);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _logAcceptanceServer(DateTime acceptedAt) async {
    try {
      final client = Supabase.instance.client;
      await client.rpc('log_terms_acceptance', params: {
        'p_terms_version': kCurrentTermsVersion,
        'p_device_id': AnalyticsService.instance.deviceId,
        'p_app_version': _appVersion,
        'p_accepted_at': acceptedAt.toIso8601String(),
      });
      debugPrint('[Legal] Acceptance logged to Supabase');
    } catch (e) {
      // RPC may not exist yet (migration not applied) or network fail —
      // silent. Hive already has the record.
      debugPrint('[Legal] Supabase log failed (non-fatal): $e');
    }
  }
}
