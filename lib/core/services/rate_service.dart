import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/rate/presentation/rate_app_sheet.dart';
import '../navigation/app_navigator.dart';
import 'ad_service.dart';

/// Decides when to ask the user for a Play Store review, and asks.
///
/// The rules exist to keep the ask from becoming the reason someone leaves
/// one star: it only fires once the user has applied a few wallpapers (so
/// they have an opinion worth giving), never on an apply that just showed an
/// ad (two interruptions back to back read as one rude app), and it gives up
/// permanently after three refusals.
///
/// Policy: the sheet must never reward a review or route users by sentiment.
/// See docs/superpowers/specs/2026-07-15-rate-app-modal-design.md.
class RateService {
  RateService._();
  static final RateService instance = RateService._();

  static const _boxName = 'pixora_settings'; // shared with onboarding
  static const _kApplied = 'rate_applied_count';
  static const _kFirstSeen = 'rate_first_seen_at';
  static const _kPrompts = 'rate_prompt_count';
  static const _kSnooze = 'rate_snooze_until';
  static const _kDone = 'rate_done';

  static const _minApplies = 3;
  static const _minAge = Duration(days: 2);
  static const _snooze = Duration(days: 14);
  static const _maxPrompts = 3;

  static const _marketUrl = 'market://details?id=com.orbix.pixora';
  static const _webUrl =
      'https://play.google.com/store/apps/details?id=com.orbix.pixora';

  Box? _box;

  /// Opens the box and stamps the install date on the first ever run. The
  /// stamp is what the "app is at least [_minAge] old" rule measures against,
  /// so it has to be written before the first apply can happen.
  Future<void> init() async {
    try {
      _box = await Hive.openBox(_boxName);
      if (_box!.get(_kFirstSeen) == null) {
        await _box!.put(_kFirstSeen, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (_) {
      _box = null; // stay silent; the app must launch regardless
    }
  }

  /// Call after a wallpaper is successfully applied. Counts it, then asks if
  /// this is a good moment. Callers report the fact; the rules live here.
  Future<void> recordApplied() async {
    final box = _box;
    if (box == null) return;
    try {
      if (box.get(_kDone, defaultValue: false) as bool) return;
      final n = (box.get(_kApplied, defaultValue: 0) as int) + 1;
      await box.put(_kApplied, n);
      if (_isEligible()) await _present();
    } catch (_) {}
  }

  bool _isEligible() {
    final box = _box;
    if (box == null) return false;

    // Checked first, and it must stay first: markRated() sets it, and the
    // sheet's dismiss handler writes a snooze even when the user tapped
    // "¡Calificar!". Reordering these would let that stale snooze matter.
    if (box.get(_kDone, defaultValue: false) as bool) return false;

    final applied = box.get(_kApplied, defaultValue: 0) as int;
    if (applied < _minApplies) return false;

    final now = DateTime.now().millisecondsSinceEpoch;

    final firstSeen = box.get(_kFirstSeen, defaultValue: now) as int;
    if (now - firstSeen < _minAge.inMilliseconds) return false;

    final snoozeUntil = box.get(_kSnooze, defaultValue: 0) as int;
    if (now < snoozeUntil) return false;

    // The apply that just happened carried an ad. Asking now would make the
    // review prompt land as a second interstitial. Wait for a clean one — the
    // alternating cadence means that is usually the very next apply.
    if (AdService.instance.lastActionShowedAd) return false;

    return true;
  }

  /// True when there is a live context to show into and nothing already on
  /// top of it — don't stack the sheet over another sheet or a dialog.
  bool get _canPresent {
    final ctx = pixoraNavigatorKey.currentContext;
    if (ctx == null) return false;
    final route = ModalRoute.of(ctx);
    return route == null || route.isCurrent;
  }

  /// Shows the sheet. Counters are left untouched when we bail early, so the
  /// next qualifying apply simply tries again.
  Future<void> _present() async {
    final box = _box;
    if (box == null || !_canPresent) return;

    // Burn the budget on SHOW, not on answer: a sheet the user ignores has
    // still been spent, and counting only answers would let us show it more
    // than _maxPrompts times.
    final shown = (box.get(_kPrompts, defaultValue: 0) as int) + 1;
    await box.put(_kPrompts, shown);
    if (shown >= _maxPrompts) {
      await box.put(_kDone, true);
    }

    // Re-resolve after those awaits rather than reusing a context captured
    // before them: the app can be backgrounded or the route popped while
    // Hive writes, and showing into a dead context throws.
    final ctx = pixoraNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await RateAppSheet.show(ctx);
  }

  /// User tapped "¡Calificar!". Opens the Store and never asks again.
  ///
  /// We cannot tell whether they actually left a review — neither market://
  /// nor the In-App Review API reports that — so tapping the button is
  /// treated as done. Pestering someone who did us the favour is worse than
  /// missing a second chance with someone who didn't.
  Future<void> markRated() async {
    final ok = await _openStore();
    if (!ok) return; // couldn't open anything; leave the door open
    try {
      await _box?.put(_kDone, true);
    } catch (_) {}
  }

  /// User tapped "Ahora no", or swiped the sheet away. Same handling: someone
  /// who flicks a sheet off mid-scroll is busy, not offended.
  Future<void> markDismissed() async {
    try {
      await _box?.put(
        _kSnooze,
        DateTime.now().add(_snooze).millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<bool> _openStore() async {
    try {
      final ok = await launchUrl(
        Uri.parse(_marketUrl),
        mode: LaunchMode.externalApplication,
      );
      if (ok) return true;
    } catch (_) {}
    // No Play Store app, or a debug build sideloaded over adb — market://
    // resolves to nothing there. The web listing works everywhere, which is
    // also what makes this testable before release.
    try {
      return await launchUrl(
        Uri.parse(_webUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// Device-testing hook: shows the sheet ignoring every gate. Does not touch
  /// the prompt budget, so it can be fired repeatedly.
  Future<void> debugForceShow() async {
    final ctx = pixoraNavigatorKey.currentContext;
    if (ctx == null) return;
    await RateAppSheet.show(ctx);
  }

  /// Device-testing hook: wipes all rate state so the real trigger path can
  /// be exercised from scratch.
  Future<void> debugReset() async {
    try {
      await _box?.delete(_kApplied);
      await _box?.delete(_kPrompts);
      await _box?.delete(_kSnooze);
      await _box?.delete(_kDone);
      await _box?.put(_kFirstSeen, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}
