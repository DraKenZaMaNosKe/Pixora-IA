import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier();
});

class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super({}) {
    _loadFromHive();
  }

  static const _boxName = 'favorites';

  Future<void> _loadFromHive() async {
    final box = await Hive.openBox<String>(_boxName);
    state = box.values.toSet();
  }

  Future<void> toggle(String wallpaperId) async {
    final box = await Hive.openBox<String>(_boxName);
    if (state.contains(wallpaperId)) {
      state = {...state}..remove(wallpaperId);
      final key = box.values.toList().indexOf(wallpaperId);
      if (key >= 0) await box.deleteAt(key);
    } else {
      state = {...state, wallpaperId};
      await box.add(wallpaperId);
    }
  }

  bool isFavorite(String wallpaperId) => state.contains(wallpaperId);
}
