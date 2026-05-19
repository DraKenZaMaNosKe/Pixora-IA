import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_config.dart';
import '../../features/wallpapers/data/models/wallpaper.dart';
import 'catalog_cache_store.dart';

/// Catalog service — reads wallpapers from Postgres `wallpapers_v` view.
///
/// Loading order on each `fetchCatalog()`:
///   1. In-memory cache (if fresh, < 6h)
///   2. Postgres via Supabase client (preferred — indexed, server-side filters)
///   3. Local file cache (`catalog_cache.json`)
///   4. Legacy `catalog.json` HTTP fallback (last resort, kept as safety net)
///
/// The third and fourth paths only run when Supabase is unreachable.
class CatalogService {
  CatalogService._();
  static final instance = CatalogService._();

  static const _cacheMinutes = 30;
  static const _cacheKey = 'postgres:wallpapers_v';
  List<Wallpaper> _wallpapers = [];
  DateTime? _lastFetch;

  Future<List<Wallpaper>>? _activeFetch;

  List<Wallpaper> get wallpapers => _wallpapers;

  /// Limpia el cache (memoria + Hive). Lo dispara el FCM `catalog_invalidate`
  /// scope=wallpapers|all y el pull-to-refresh del grid de WALLPAPERS.
  Future<void> clearCache() async {
    _wallpapers = [];
    _lastFetch = null;
    await CatalogCacheStore.instance.clear(_cacheKey);
  }

  /// Cold-start optimization: lee el catalog_cache.json de disco ANTES de
  /// runApp() y popula el cache in-memory. Resultado: la primera pantalla
  /// que pide el catálogo (WallpapersPage) recibe data al instante en vez
  /// de mostrar el skeleton de loading 1-3s mientras Postgres responde.
  ///
  /// Idempotente — si ya hay data en memoria, no hace nada. Silencioso ante
  /// cualquier error (primera instalación = no cache = comportamiento normal
  /// con loading skeleton).
  Future<void> preloadFromDiskCache() async {
    if (_wallpapers.isNotEmpty) return;
    try {
      final entry = await CatalogCacheStore.instance.read(_cacheKey);
      if (entry == null) return;
      final list = _parseFromJsonBody(entry.body);
      if (list.isEmpty) return;
      _wallpapers = list;
      // Tratamos la cache como recién obtenida — el TTL de 30 min empieza
      // a contar desde el cold start. La próxima request fresca pasará el
      // _isCacheValid check; al expirar, Riverpod / pull-to-refresh
      // dispararán el fetch real a Postgres.
      _lastFetch = DateTime.now();
      debugPrint(
          '[Pixora] Catalog preloaded from Hive: ${_wallpapers.length} wallpapers');
    } catch (e) {
      debugPrint('[Pixora] Hive preload failed: $e');
    }
  }

  bool get _isCacheValid =>
      _lastFetch != null &&
      DateTime.now().difference(_lastFetch!) <
          const Duration(minutes: _cacheMinutes);

  Future<List<Wallpaper>> fetchCatalog({bool forceRefresh = false}) async {
    if (_wallpapers.isNotEmpty && _isCacheValid && !forceRefresh) {
      return _wallpapers;
    }
    if (_activeFetch != null) return _activeFetch!;
    _activeFetch = _doFetch();
    try {
      return await _activeFetch!;
    } finally {
      _activeFetch = null;
    }
  }

  Future<List<Wallpaper>> _doFetch() async {
    // 1) Try Postgres first — indexed reads
    final fromSupabase = await _fetchFromSupabase();
    if (fromSupabase != null && fromSupabase.isNotEmpty) {
      _wallpapers = fromSupabase;
      _lastFetch = DateTime.now();
      await _persistToHive(_wallpapers);
      debugPrint(
          '[Pixora] Catalog loaded from Postgres: ${_wallpapers.length}');
      return _wallpapers;
    }

    // 2) Try the legacy JSON in Storage (in case Postgres is offline)
    final fromJson = await _fetchFromJson();
    if (fromJson != null && fromJson.isNotEmpty) {
      _wallpapers = fromJson;
      _lastFetch = DateTime.now();
      debugPrint(
          '[Pixora] Catalog loaded from legacy JSON: ${_wallpapers.length}');
      return _wallpapers;
    }

    // 3) Fallback to Hive cache
    final entry = await CatalogCacheStore.instance.read(_cacheKey);
    if (entry != null) {
      final cached = _parseFromJsonBody(entry.body);
      if (cached.isNotEmpty) {
        _wallpapers = cached;
        debugPrint(
            '[Pixora] Catalog loaded from Hive cache: ${_wallpapers.length}');
      }
    }
    return _wallpapers;
  }

  /// Read from `wallpapers_v` view via Supabase client. Returns null on error.
  ///
  /// Filtra `published = true` para respetar el toggle visible/oculto
  /// del dashboard. Los wallpapers ocultos siguen existiendo en la DB pero
  /// no aparecen en el catálogo público.
  Future<List<Wallpaper>?> _fetchFromSupabase() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('wallpapers_v')
          .select()
          .eq('published', true)
          .order('sort_order', ascending: true)
          .timeout(const Duration(seconds: 12));
      final list = (rows as List)
          .map((r) => Wallpaper.fromSupabase(r as Map<String, dynamic>))
          .toList();
      return list;
    } catch (e) {
      debugPrint('[Pixora] Supabase catalog fetch failed: $e');
      return null;
    }
  }

  /// Legacy fallback: read the old catalog.json from storage.
  Future<List<Wallpaper>?> _fetchFromJson() async {
    try {
      final url = SupabaseConfig.catalogUrl();
      final response = await http.get(Uri.parse(url), headers: {
        'Cache-Control': 'no-cache'
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final parsed = _parseFromJsonBody(body);
        // Persist a Hive con el ETag por si Postgres falla en una próxima
        // visita — el fallback usará este snapshot.
        await CatalogCacheStore.instance
            .write(_cacheKey, body, response.headers['etag']);
        return parsed;
      }
    } catch (e) {
      debugPrint('[Pixora] Legacy JSON fetch failed: $e');
    }
    return null;
  }

  /// Serializa la lista actual y la guarda en Hive como JSON sin ETag
  /// (los rows vienen de Postgres, no de Storage, por eso no hay ETag).
  Future<void> _persistToHive(List<Wallpaper> list) async {
    try {
      final body = jsonEncode({
        'wallpapers': list.map((w) => w.toJson()).toList(),
        'cachedAt': DateTime.now().toIso8601String(),
      });
      await CatalogCacheStore.instance.write(_cacheKey, body, null);
    } catch (e) {
      debugPrint('[Pixora] Hive write error: $e');
    }
  }

  /// Parsea un body JSON con la forma `{wallpapers: [...]}` y devuelve la
  /// lista ordenada por sortOrder. Devuelve [] ante cualquier error.
  List<Wallpaper> _parseFromJsonBody(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final list = (data['wallpapers'] as List<dynamic>?) ?? [];
      final wallpapers = list
          .map((e) => Wallpaper.fromJson(e as Map<String, dynamic>))
          .toList();
      wallpapers.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return wallpapers;
    } catch (e) {
      debugPrint('[Pixora] Catalog parse error: $e');
      return [];
    }
  }
}
