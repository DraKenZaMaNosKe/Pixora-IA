import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// "Grace pass" — a one-time free pass that lets the user install one
/// wallpaper WITHOUT seeing the interstitial ad.
///
/// Used as the welcome-gift mechanic shown at the end of the guided tour:
/// the user gets one ad-free install (Volcano Dragon recommended in the
/// gift sheet, but they can spend it on whichever wallpaper they install
/// first). After consuming, behavior returns to the normal alternating-ad
/// rules in AdService.
///
/// Persisted in Hive so it survives reinstalls / device restarts. Default
/// state is "available" (true) on first launch — set false once consumed.
class GracePassService extends ChangeNotifier {
  GracePassService._();
  static final instance = GracePassService._();

  static const _hiveBox = 'pixora_settings';
  static const _hiveKey = 'first_install_grace_remaining_v1';

  bool _available = true;
  bool _initialised = false;

  /// True when there's still a pass available. AdService checks this BEFORE
  /// running the alternating-counter logic, so a grace pass always wins.
  bool get hasGrace => _available;

  /// Lazy init — call once during app startup, or it'll happen on first
  /// `hasGrace` access via `ensureLoaded()`.
  Future<void> init() async {
    if (_initialised) return;
    try {
      final box = await Hive.openBox(_hiveBox);
      // First launch: key doesn't exist → default to true (grace available).
      // Subsequent launches: read whatever was last stored.
      _available = box.get(_hiveKey, defaultValue: true) as bool;
    } catch (e) {
      debugPrint('[GracePass] init error: $e');
      _available = false; // safer: don't accidentally give grace on error
    }
    _initialised = true;
  }

  /// Consume the pass. Call this when the user actually triggers an install
  /// that would have shown an ad. After this, hasGrace returns false and
  /// the normal ad rules take over for all subsequent installs.
  Future<void> consume() async {
    if (!_available) return;
    _available = false;
    notifyListeners();
    try {
      final box = await Hive.openBox(_hiveBox);
      await box.put(_hiveKey, false);
      debugPrint('[GracePass] consumed — welcome gift used');
    } catch (e) {
      debugPrint('[GracePass] consume error: $e');
    }
  }

  /// Restore the pass. Useful for testing the gift flow during dev or for
  /// admin-driven promos ("everyone gets one free install this weekend").
  Future<void> restore() async {
    _available = true;
    notifyListeners();
    try {
      final box = await Hive.openBox(_hiveBox);
      await box.put(_hiveKey, true);
    } catch (e) {
      debugPrint('[GracePass] restore error: $e');
    }
  }
}
