import 'package:hive_flutter/hive_flutter.dart';

import 'mystery_exclusion_service.dart';

/// Selección PROPORCIONAL de Mystery cards (tap-to-reveal).
///
/// 2026-07-05 — Eduardo: el viejo "1 de cada 12" fallaba en listas chicas
/// (5 wallpapers × 8% = 0 cartas → nunca salía ninguna). Ahora la cantidad
/// escala con el total, con un mínimo garantizado:
///
///   | total | cartas |
///   |-------|--------|
///   |   5   |   1    |
///   |  10   |   3    |
///   |  20   |   6    |
///   |  30   |   8    |
///   |  50   |  14    |
///
/// ~28% del pool elegible, redondeado, con mínimo 1 (si hay ≥4 items) y un
/// techo absoluto para que catálogos enormes no se llenen de cartas.
const double kMysteryRatio = 0.28;
const int kMysteryMin = 1; // al menos 1 carta...
const int kMysteryMinPool = 4; // ...pero solo si el pool tiene ≥4 items
const int kMysteryMaxCards = 40; // techo duro para catálogos muy grandes

const String _kFavoritesBox = 'favorites';

bool _isFavorite(String id) {
  try {
    return Hive.box<String>(_kFavoritesBox).values.contains(id);
  } catch (_) {
    return false; // box not open → treat as not favorite
  }
}

/// Devuelve el subconjunto de `ids` que deben mostrarse como Mystery card.
///
/// Determinístico y estable: el mismo set de ids → el mismo resultado. El
/// ranking por hash decide CUÁLES caen; la proporción decide CUÁNTAS.
///
///   - Excluye instalados/revelados ([MysteryExclusionService]) y, si
///     [checkFavorites] (solo wallpapers/3D comparten la box `favorites`),
///     también los favoritos — ANTES de calcular la proporción, para que la
///     cuenta se base en el pool realmente "sorpresa-able".
///   - target = round(elegibles × [kMysteryRatio]), con mínimo [kMysteryMin]
///     (si hay ≥[kMysteryMinPool]) y tope [kMysteryMaxCards].
Set<String> pickMysteryIds(
  Iterable<String> ids, {
  bool checkFavorites = false,
}) {
  final eligible = <String>[];
  for (final id in ids) {
    if (MysteryExclusionService.instance.isExcluded(id)) continue;
    if (checkFavorites && _isFavorite(id)) continue;
    eligible.add(id);
  }
  final n = eligible.length;
  if (n == 0) return const <String>{};

  var target = (n * kMysteryRatio).round();
  if (n >= kMysteryMinPool && target < kMysteryMin) target = kMysteryMin;
  if (target > kMysteryMaxCards) target = kMysteryMaxCards;
  if (target <= 0) return const <String>{};
  if (target >= n) return eligible.toSet();

  // Ranking estable por hash del id (desempate lexicográfico para que dos
  // ids con el mismo hashCode no bailen entre builds).
  eligible.sort((a, b) {
    final ha = a.hashCode.abs();
    final hb = b.hashCode.abs();
    return ha != hb ? ha.compareTo(hb) : a.compareTo(b);
  });
  return eligible.take(target).toSet();
}
