import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/auth_service.dart';

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier();
});

/// Favorites state with cloud-first-when-signed-in semantics:
///
/// | State         | Source of truth      | Local Hive role          |
/// |---------------|----------------------|--------------------------|
/// | Anonymous     | Local Hive           | Source of truth          |
/// | Signed-in     | Supabase cloud       | Read-through cache only  |
///
/// Transitions:
/// 1. Startup signed-in   → fetch cloud, replace local cache.
/// 2. Startup anonymous   → read local Hive as state.
/// 3. Sign-in + cloud ∅   → seed cloud from local (onboarding gift: keep
///    the favorites the user gathered before registering).
/// 4. Sign-in + cloud ≠ ∅ → cloud wins, local cache overwritten.
/// 5. Sign-out            → clear local cache + state (anonymous restart).
/// 6. Account A → B       → clear A's cache, load B's cloud. Zero leak.
class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super({}) {
    _init();
  }

  static const _boxName = 'favorites';
  Box<String>? _box;
  StreamSubscription<AuthState>? _authSub;
  String? _currentUid;

  Future<void> _init() async {
    try {
      _box = await Hive.openBox<String>(_boxName);
      _currentUid = AuthService.instance.currentUser?.id;
      await _loadInitial();

      _authSub = AuthService.instance.authStateChanges.listen((_) {
        final newUid = AuthService.instance.currentUser?.id;
        final oldUid = _currentUid;
        if (newUid == oldUid) return;
        _currentUid = newUid;
        _handleAuthChange(oldUid, newUid);
      });
    } catch (e) {
      debugPrint('[Favorites] Init failed: $e');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  // ── Load paths ────────────────────────────────────────────────────

  /// Initial load on app startup. Anonymous → local Hive; signed-in →
  /// cloud (authoritative, overwrites the local cache from a prior session).
  Future<void> _loadInitial() async {
    if (AuthService.instance.isLoggedIn) {
      await _replaceLocalWithCloud(seedIfEmpty: false);
    } else {
      await _loadAnonymous();
    }
  }

  Future<void> _handleAuthChange(String? oldUid, String? newUid) async {
    if (newUid == null) {
      // Sign-out: clear everything and restart anonymous.
      await _clearLocalCache();
      debugPrint('[Favorites] Sign-out: local cache cleared');
    } else if (oldUid == null) {
      // Anonymous → sign-in: seed cloud if empty, else cloud replaces.
      await _replaceLocalWithCloud(seedIfEmpty: true);
    } else {
      // Account switch: discard A's cache, load B's cloud fresh.
      await _clearLocalCache();
      await _replaceLocalWithCloud(seedIfEmpty: false);
    }
  }

  Future<void> _loadAnonymous() async {
    final box = _box ?? await Hive.openBox<String>(_boxName);
    state = box.values.toSet();
    debugPrint('[Favorites] Loaded ${state.length} (anonymous, local)');
  }

  /// Read cloud into local cache + state. If [seedIfEmpty] and cloud is
  /// empty but the current local cache has items, upload them as the
  /// seed for the user's cloud record.
  Future<void> _replaceLocalWithCloud({required bool seedIfEmpty}) async {
    final box = _box ?? await Hive.openBox<String>(_boxName);
    final local = box.values.toSet();

    final cloudFavs = await AuthService.instance.fetchRemoteFavorites();

    if (seedIfEmpty && cloudFavs.isEmpty && local.isNotEmpty) {
      // First sign-in gift: push local → cloud as the seed.
      for (final id in local) {
        unawaited(AuthService.instance.addFavoriteRemote(id));
      }
      state = local;
      debugPrint(
          '[Favorites] Seeded cloud with ${local.length} local favorites');
      return;
    }

    // Cloud wins: wipe cache and rewrite with cloud contents.
    await box.clear();
    for (final id in cloudFavs) {
      await box.add(id);
    }
    state = cloudFavs;
    debugPrint('[Favorites] Loaded ${cloudFavs.length} from cloud');
  }

  Future<void> _clearLocalCache() async {
    final box = _box ?? await Hive.openBox<String>(_boxName);
    await box.clear();
    state = {};
  }

  // ── Mutations ──────────────────────────────────────────────────────

  Future<void> toggle(String wallpaperId) async {
    try {
      final box = _box ?? await Hive.openBox<String>(_boxName);
      if (state.contains(wallpaperId)) {
        final entry = box.toMap().entries.firstWhere(
              (e) => e.value == wallpaperId,
              orElse: () => MapEntry(-1, ''),
            );
        if (entry.key != -1) await box.delete(entry.key);
        state = {...state}..remove(wallpaperId);
        unawaited(
          AuthService.instance.removeFavoriteRemote(wallpaperId).catchError(
                (e) => debugPrint('[Favorites] Remote remove failed: $e'),
              ),
        );
      } else {
        await box.add(wallpaperId);
        state = {...state, wallpaperId};
        unawaited(
          AuthService.instance.addFavoriteRemote(wallpaperId).catchError(
                (e) => debugPrint('[Favorites] Remote add failed: $e'),
              ),
        );
      }
    } catch (e) {
      debugPrint('[Favorites] toggle($wallpaperId) failed: $e');
    }
  }

  /// Kept for API compatibility with call sites that still invoke it.
  void reset() {
    state = {};
  }

  bool isFavorite(String wallpaperId) => state.contains(wallpaperId);
}
