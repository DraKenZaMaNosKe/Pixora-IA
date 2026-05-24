import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/categories.dart';
import '../../../core/services/catalog_service.dart';
import '../data/models/wallpaper.dart';

/// Categories that have their own dedicated section in the app and must
/// NEVER bleed into the regular Wallpapers feed.
const _arcanoCategories = {'ARCANO'};

/// Tags that explicitly mark a wallpaper as ARCANO-section content.
/// Generic tags (`zodiac`, `livecalendar`) are too broad — many wallpapers
/// use them without being calendar/observatory content. Use `arcano` as
/// the dedicated marker tag when adding new content to this section.
const _arcanoTags = {'arcano'};

/// Hard whitelist of wallpaper IDs that belong in ARCANO. Use this for
/// wallpapers that pre-date the tagging convention. Add new items here
/// OR tag them with `arcano` in the Supabase catalog — either works.
const _arcanoIds = {'zodiac_cosmos'};

bool _isArcano(Wallpaper w) {
  if (_arcanoIds.contains(w.id)) return true;
  if (_arcanoCategories.contains(w.category.toUpperCase())) return true;
  for (final t in w.tags) {
    if (_arcanoTags.contains(t.toLowerCase())) return true;
  }
  return false;
}

/// Helper para comprobar si un wallpaper tiene un tag específico
/// (case-insensitive, sin acentos en convención).
bool _hasTag(Wallpaper w, String tag) {
  final needle = tag.toLowerCase();
  return w.tags.any((t) => t.toLowerCase() == needle);
}

/// Match para sección "Arte": tag `arte` O categoría ART/ARTE.
bool _isArte(Wallpaper w) {
  if (_hasTag(w, 'arte')) return true;
  final c = w.category.toUpperCase();
  return c == 'ART' || c == 'ARTE';
}

/// Match para sección "Mitología": tag `mitologia` O categoría MITOLOGIA.
/// NO incluye ARCANO porque tiene tab propia (LiveCalendar).
bool _isMitologia(Wallpaper w) {
  if (_hasTag(w, 'mitologia')) return true;
  return w.category.toUpperCase() == 'MITOLOGIA';
}

/// Categorías que NO deben aparecer en _CategoryRows porque ya tienen su
/// propio carousel curado arriba (Arte, Mitología). Evita duplicación
/// visual: un wallpaper "ARTE" no debe verse en 2 rows distintos.
const _curatedSectionCategories = {'ART', 'ARTE', 'MITOLOGIA'};

/// Raw catalog from Supabase (every wallpaper, used internally + by the
/// ARCANO provider). UI feeds should consume `catalogPublicProvider`.
final catalogProvider = FutureProvider<List<Wallpaper>>((ref) async {
  return CatalogService.instance.fetchCatalog();
});

/// Public catalog with ARCANO items stripped out. This is what the regular
/// Wallpapers/Live tabs see — keeps lunar/tarot content from polluting the
/// general grid (it has its own dedicated tab).
final catalogPublicProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final all = await ref.watch(catalogProvider.future);
  return all.where((w) => !_isArcano(w)).toList();
});

/// ARCANO-only feed for the new mystical/lunar/tarot section.
final arcanoCatalogProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final all = await ref.watch(catalogProvider.future);
  return all.where(_isArcano).toList();
});

/// Categoría actualmente seleccionada en los chips de filtro.
final selectedCategoryProvider =
    StateProvider<WallpaperCategory>((ref) => WallpaperCategory.all);

/// Wallpapers marcados como featured en el catálogo JSON.
final featuredWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  return wallpapers.where((w) => w.featured).toList();
});

/// Hero banner: featured wallpapers, fallback to first 5.
final heroBannerProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final featured = await ref.watch(featuredWallpapersProvider.future);
  if (featured.isNotEmpty) return featured.take(6).toList();
  final all = await ref.watch(catalogPublicProvider.future);
  return all.take(5).toList();
});

/// Trending: sorted by download count (highest first), fallback to sortOrder.
final trendingWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  final sorted = [...wallpapers]..sort((a, b) {
      // Primary: downloadCount descending
      if (a.downloadCount != b.downloadCount) {
        return b.downloadCount.compareTo(a.downloadCount);
      }
      // Fallback: sortOrder ascending
      return a.sortOrder.compareTo(b.sortOrder);
    });
  return sorted.take(15).toList();
});

/// New wallpapers: added within last 14 days or badge == 'NEW'.
final newWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  final newOnes = wallpapers.where((w) => w.isNew).toList();
  // Sort newest first
  newOnes.sort((a, b) {
    final aDate = a.createdAt ?? DateTime(2000);
    final bDate = b.createdAt ?? DateTime(2000);
    return bDate.compareTo(aDate);
  });
  return newOnes.take(15).toList();
});

/// Sección "Arte" — wallpapers de arte/galería (curados via tag `arte`
/// o categoría ART/ARTE). Multi-categoría real: un wallpaper PANORAMIC
/// con tag `arte` aparece tanto en su categoría natural como aquí.
final arteWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  return wallpapers.where(_isArte).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

/// Sección "Mitología" — wallpapers de mitologías (Aztec, Egipto, Griega,
/// Norse, etc.). Curados via tag `mitologia` o categoría MITOLOGIA.
final mitologiaWallpapersProvider =
    FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  return wallpapers.where(_isMitologia).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

/// Sección "Panoramic" — chip 5. Cualquier wallpaper que califique como
/// panorámico (por ratio >= 3:1 o por categoría PANORAMIC manual). Fase 2
/// del dimension-agnostic system: incluye los items "escondidos" en otras
/// categorías que tienen ratio panorámico (ej. calendarios panorámicos).
/// iOS no soporta panorámicos — se filtra en categoryRowsProvider, aquí
/// devolvemos todos y el chip se oculta en iOS via WallpaperChipsRow.
final panoramicWallpapersProvider =
    FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  return wallpapers.where((w) => w.isPanoramic).toList()
    ..sort((a, b) {
      // Featured primero, luego sortOrder ascendente.
      if (a.featured != b.featured) return a.featured ? -1 : 1;
      return a.sortOrder.compareTo(b.sortOrder);
    });
});

/// Sección "Gaming" — chip 6. Wallpapers de category GAMING. Es la 2da
/// categoría más grande (~56 items): pixel art, fighting games, retro,
/// classic console aesthetics.
final gamingWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  return wallpapers.where((w) => w.category.toUpperCase() == 'GAMING').toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

/// Sección "Anime" — chip 7. Wallpapers de category ANIME. Personajes,
/// series, mangas, fan art.
final animeWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  return wallpapers.where((w) => w.category.toUpperCase() == 'ANIME').toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

/// Sección "Calendar" — chip 8. Wallpapers funcionales con calendarios
/// mensuales/semestrales (refrigerador MX, doctor, vintage parchment,
/// sci-fi AMOLED, SpongeBob, etc.). Categoría chica pero muy utilitaria.
final calendarWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  return wallpapers
      .where((w) => w.category.toUpperCase() == 'CALENDAR')
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

/// Category rows: grouped by category, min 3 items per row.
/// Excluye las categorías que ya tienen su propio carousel curado arriba
/// (Arte, Mitología) para evitar duplicación visual.
final categoryRowsProvider =
    FutureProvider<List<({String title, List<Wallpaper> items})>>((ref) async {
  final wallpapers = await ref.watch(catalogPublicProvider.future);
  final map = <String, List<Wallpaper>>{};
  for (final w in wallpapers) {
    if (Platform.isIOS && w.isPanoramic) continue;
    // Skip categorías que ya tienen sección dedicada arriba (Arte, Mitología).
    if (_curatedSectionCategories.contains(w.category.toUpperCase())) continue;
    map.putIfAbsent(w.category, () => []).add(w);
    // Cross-list: cualquier wallpaper con ratio panorámico (>=3:1) también
    // aparece en la sección PANORAMIC, sin importar su categoría temática.
    // Así un wallpaper ANIME con ratio 4:1 sale en ANIME y en PANORAMIC.
    // Items con category='PANORAMIC' ya están agregados arriba (no duplicar).
    if (w.isPanoramic && w.category.toUpperCase() != 'PANORAMIC') {
      map.putIfAbsent('PANORAMIC', () => []).add(w);
    }
  }
  return map.entries
      .where((e) => e.value.length >= 3)
      .map((e) => (
            title: e.key[0].toUpperCase() + e.key.substring(1).toLowerCase(),
            items: e.value
          ))
      .toList();
});
