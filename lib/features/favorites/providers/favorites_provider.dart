import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Provider de favoritos locales persistidos en Hive.
/// El estado es un Set<String> de IDs de wallpapers favoritos.
final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier();
});

class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super({}) {
    _loadFromHive();
  }

  static const _boxName = 'favorites';

  /// Carga los favoritos guardados al inicializar el notifier.
  Future<void> _loadFromHive() async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      state = box.values.toSet();
    } catch (e) {
      debugPrint('[Favorites] Error al cargar desde Hive: $e');
    }
  }

  /// Agrega o quita un wallpaper de favoritos.
  ///
  /// FIX: Reemplazado indexOf() frágil por toMap().entries.firstWhere()
  /// que usa la key real de Hive, evitando borrar el ID equivocado.
  Future<void> toggle(String wallpaperId) async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      if (state.contains(wallpaperId)) {
        final entry = box.toMap().entries.firstWhere(
          (e) => e.value == wallpaperId,
          orElse: () => MapEntry(-1, ''),
        );
        if (entry.key != -1) await box.delete(entry.key);
        state = {...state}..remove(wallpaperId);
      } else {
        await box.add(wallpaperId);
        state = {...state, wallpaperId};
      }
    } catch (e) {
      debugPrint('[Favorites] Error en toggle($wallpaperId): $e');
    }
  }

  /// Verifica si un wallpaper está en favoritos.
  bool isFavorite(String wallpaperId) => state.contains(wallpaperId);
}
