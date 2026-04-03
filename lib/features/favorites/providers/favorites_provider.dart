import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/services/auth_service.dart';

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier();
});

class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super({}) {
    _init();
  }

  static const _boxName = 'favorites';
  Box<String>? _box;

  Future<void> _init() async {
    try {
      _box = await Hive.openBox<String>(_boxName);
      state = _box!.values.toSet();

      // If user is logged in, sync with Supabase
      if (AuthService.instance.isLoggedIn) {
        await syncWithCloud();
      }
    } catch (e) {
      debugPrint('[Favorites] Error loading from Hive: $e');
    }
  }

  /// Sync local favorites with Supabase (merge both ways).
  Future<void> syncWithCloud() async {
    try {
      final merged = await AuthService.instance.syncFavorites(state);
      if (merged != state) {
        state = merged;
        // Save merged set back to Hive
        final box = _box ?? await Hive.openBox<String>(_boxName);
        await box.clear();
        for (final id in merged) {
          await box.add(id);
        }
        debugPrint('[Favorites] Cloud sync complete: ${merged.length} favorites');
      }
    } catch (e) {
      debugPrint('[Favorites] Cloud sync failed: $e');
    }
  }

  Future<void> toggle(String wallpaperId) async {
    try {
      final box = _box ?? await Hive.openBox<String>(_boxName);
      if (state.contains(wallpaperId)) {
        // Remove
        final entry = box.toMap().entries.firstWhere(
          (e) => e.value == wallpaperId,
          orElse: () => MapEntry(-1, ''),
        );
        if (entry.key != -1) await box.delete(entry.key);
        state = {...state}..remove(wallpaperId);
        // Sync to cloud in background (don't block UI)
        AuthService.instance.removeFavoriteRemote(wallpaperId).catchError(
          (e) => debugPrint('[Favorites] Remote remove failed: $e'),
        );
      } else {
        // Add
        await box.add(wallpaperId);
        state = {...state, wallpaperId};
        AuthService.instance.addFavoriteRemote(wallpaperId).catchError(
          (e) => debugPrint('[Favorites] Remote add failed: $e'),
        );
      }
    } catch (e) {
      debugPrint('[Favorites] Error in toggle($wallpaperId): $e');
    }
  }

  /// Clear local state (call on logout for privacy).
  void reset() {
    state = {};
  }

  bool isFavorite(String wallpaperId) => state.contains(wallpaperId);
}
