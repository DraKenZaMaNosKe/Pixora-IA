import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/services/analytics_service.dart';

/// Tracks whether the user has seen the guided tutorial (coach marks tour
/// in the HomePage that points at each tab + first wallpaper card).
///
/// Persisted in Hive so the tour only fires once per fresh install. The
/// version suffix on the key (`_v1`) lets us re-trigger it later by bumping
/// to `_v2` when we add new sections worth showing.
///
/// Settings has an entry "Reabrir tutorial guiado" that calls `reset()` —
/// next HomePage build will re-fire the tour.
class TrainingService extends ChangeNotifier {
  TrainingService._();
  static final instance = TrainingService._();

  static const _hiveBox = 'pixora_settings';
  static const _hiveKey = 'tutorial_seen_v1';

  bool _seen = false;
  bool _initialised = false;

  /// True when the tour should NOT auto-start (already seen). The HomePage
  /// reads this on first build to decide whether to show coach marks.
  bool get seen => _seen;

  /// First-time loading from Hive — call once during app init (or it'll
  /// happen lazily on first `seen` access).
  Future<void> init() async {
    if (_initialised) return;
    try {
      final box = await Hive.openBox(_hiveBox);
      _seen = box.get(_hiveKey, defaultValue: false) as bool;
    } catch (_) {
      _seen = false;
    }
    _initialised = true;
  }

  /// Mark as seen (after the user finishes or skips the tour).
  Future<void> markSeen() async {
    if (_seen) return;
    _seen = true;
    notifyListeners();
    AnalyticsService.instance.trackTutorialFinished();
    try {
      final box = await Hive.openBox(_hiveBox);
      await box.put(_hiveKey, true);
    } catch (e) {
      debugPrint('[Training] markSeen error: $e');
    }
  }

  /// Call when the tour first starts (HomePage decides when).
  void trackStarted() {
    AnalyticsService.instance.trackTutorialStarted();
  }

  /// Call when the user advances to a new step in the tour.
  void trackStep(int index, String label) {
    AnalyticsService.instance.trackTutorialStep(index, label);
  }

  /// Reset the seen flag — used by the Settings entry "Reabrir tutorial".
  /// The next time the HomePage builds, the tour will auto-start.
  Future<void> reset() async {
    _seen = false;
    notifyListeners();
    try {
      final box = await Hive.openBox(_hiveBox);
      await box.delete(_hiveKey);
    } catch (e) {
      debugPrint('[Training] reset error: $e');
    }
  }
}
