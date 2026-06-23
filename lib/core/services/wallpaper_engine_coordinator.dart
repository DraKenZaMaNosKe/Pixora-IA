import 'dart:async';
import 'package:flutter/foundation.dart';

import 'auto_rotate_service.dart';
import 'day_cycle_service.dart';
import 'story_rotation_service.dart';

/// Identifies which "rotation engine" currently owns the device wallpaper.
/// Pixora has THREE engines that all write the wallpaper periodically:
///
///   - **pixoraDaily**: AutoRotateService (rotates random wallpapers from
///     catalog every X minutes — like Bing Spotlight on Windows).
///   - **dayCycle**: DayCycleService (cycles morning/afternoon/evening/night
///     images based on real time of day).
///   - **story**: StoryRotationService (cycles a curated narrative sequence
///     of wallpapers, e.g. Goku transformation stages).
///
/// Only ONE engine should be active at a time. Activating a new one must
/// stop the others or they will fight over the wallpaper Surface and the
/// user will see flicker, drained battery, and inconsistent state.
enum WallpaperEngine { none, pixoraDaily, dayCycle, story }

/// Mutex coordinator for the three rotation engines. Every entry-point
/// service (`AutoRotateService.start`, `DayCycleService.activate`,
/// `StoryRotationService.startStory`) MUST `claim()` before activating its
/// own native side, so the others get gracefully stopped first.
///
/// Notifies listeners on engine change so any UI showing "active engine"
/// can update without polling.
class WallpaperEngineCoordinator extends ChangeNotifier {
  WallpaperEngineCoordinator._();
  static final instance = WallpaperEngineCoordinator._();

  WallpaperEngine _active = WallpaperEngine.none;
  String? _activeContext; // optional: storyId, themeId, etc. for UI

  WallpaperEngine get active => _active;
  String? get activeContext => _activeContext;

  /// Result of a `claim()` call. Carries which engine was preempted, so
  /// the caller can show a UX message like "Pixora Daily reemplazó a
  /// Day Cycle".
  bool _claiming = false;

  /// Atomically take ownership of the wallpaper Surface for `engine`.
  /// Stops whichever engine was active before, then marks `engine` as
  /// active. Re-entrant safe — if [engine] was already active, no-op.
  ///
  /// Returns the previously-active engine (for UX messaging). Returns
  /// [WallpaperEngine.none] if nothing was running.
  Future<WallpaperEngine> claim(
    WallpaperEngine engine, {
    String? context,
  }) async {
    if (_claiming) {
      // Another claim is in flight — wait briefly and merge in. This
      // shouldn't happen often but guards against UI button spam.
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _claiming = true;
    final previous = _active;
    try {
      if (previous == engine && _activeContext == context) {
        return WallpaperEngine.none; // no change, nothing preempted
      }
      // Stop whatever's running that ISN'T the engine we want to claim.
      if (previous != WallpaperEngine.none && previous != engine) {
        await _stopEngine(previous);
      }
      _active = engine;
      _activeContext = context;
      notifyListeners();
      debugPrint(
        '[EngineCoordinator] claim: $previous → $engine (ctx=$context)',
      );
      return previous;
    } finally {
      _claiming = false;
    }
  }

  /// Release the active engine — call when the user explicitly stops the
  /// rotation (toggle off in PixoraDailyPage, etc.). Does NOT stop the
  /// engine itself; the calling service should have already done that.
  Future<void> release(WallpaperEngine engine) async {
    if (_active == engine) {
      _active = WallpaperEngine.none;
      _activeContext = null;
      notifyListeners();
      debugPrint('[EngineCoordinator] release: $engine');
    }
  }

  /// Stop whichever rotation engine (if any) is currently active. Call
  /// before applying a wallpaper MANUALLY (setWallpaper, setLiveWallpaper,
  /// setShaderWallpaper, etc) so the rotation doesn't sobreescribe the
  /// user's pick at the next tick.
  ///
  /// No-op if no engine is active. Idempotent. Defensive — swallows
  /// any error from the underlying _stopEngine so callers (apply flow)
  /// never crash if the engine can't be stopped cleanly. Worst case
  /// the rotation keeps running, which is a UX glitch, not a crash.
  Future<WallpaperEngine> stopAll() async {
    final previous = _active;
    if (previous == WallpaperEngine.none) return WallpaperEngine.none;
    try {
      await _stopEngine(previous);
    } catch (e) {
      debugPrint('[EngineCoordinator] stopAll: _stopEngine failed: $e');
      // Continue anyway — we still want to mark coordinator as none so
      // future apply calls don't loop trying to stop a stuck engine.
    }
    _active = WallpaperEngine.none;
    _activeContext = null;
    try {
      notifyListeners();
    } catch (_) {/* ignore — listener errors must never break apply */}
    debugPrint('[EngineCoordinator] stopAll: stopped $previous');
    return previous;
  }

  /// Resync state from native side at app start. Each service's
  /// `getStatus()` is called and whichever returns `enabled=true` first
  /// wins (rare race, but possible if app crashed mid-switch).
  Future<void> syncFromNative() async {
    try {
      final auto = await AutoRotateService.instance.getStatus();
      if (auto['enabled'] == true) {
        _active = WallpaperEngine.pixoraDaily;
        _activeContext = auto['category'] as String?;
        notifyListeners();
        return;
      }
    } catch (_) {}
    try {
      final day = await DayCycleService.instance.getStatus();
      if (day['enabled'] == true) {
        _active = WallpaperEngine.dayCycle;
        _activeContext = day['themeId'] as String?;
        notifyListeners();
        return;
      }
    } catch (_) {}
    // Story service has no getStatus — treat as none on cold start.
    _active = WallpaperEngine.none;
    _activeContext = null;
    notifyListeners();
  }

  Future<void> _stopEngine(WallpaperEngine e) async {
    switch (e) {
      case WallpaperEngine.pixoraDaily:
        await AutoRotateService.instance.stop();
      case WallpaperEngine.dayCycle:
        await DayCycleService.instance.deactivate();
      case WallpaperEngine.story:
        await StoryRotationService.instance.stopStory();
      case WallpaperEngine.none:
        break;
    }
  }

  /// Human label for UX messages.
  static String labelEs(WallpaperEngine e) => switch (e) {
        WallpaperEngine.pixoraDaily => 'Pixora Daily',
        WallpaperEngine.dayCycle => 'Day Cycle',
        WallpaperEngine.story => 'Historia',
        WallpaperEngine.none => 'Ninguno',
      };
}
