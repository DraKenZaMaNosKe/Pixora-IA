import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../constants/supabase_config.dart';
import '../utils/connectivity.dart';
import 'capability_registry.dart';

/// Lightweight unified catalog. ONE JSON file lists every renderable item
/// (wallpapers, scenes, ringtones, stories, AURA tracks…) with just the
/// metadata needed for browsing — no per-item heavy specs.
///
/// Heavy per-item data (sprites, shaders, scene specs) is fetched lazily
/// via SceneSpecService when the user actually taps an item.
///
/// Cache rules:
///   - In-memory: holds the parsed list until app restart
///   - On-disk: filesDir/catalog_index.json + version stamp; refreshed when
///     remote `version` increments OR cache is older than 6h
///   - Items unsupported by this app build are filtered out at parse time
class CatalogIndexService {
  CatalogIndexService._();
  static final instance = CatalogIndexService._();

  static const _filename = 'catalog_index.json';
  static const _bucket = SupabaseConfig.imagesBucket;
  static const _refreshAfter = Duration(hours: 6);

  static String get _remoteUrl =>
      '${SupabaseConfig.storageBase}/$_bucket/$_filename';

  List<CatalogIndexEntry>? _items;
  int? _version;

  /// Returns the parsed catalog. Pulls from disk first, then network if
  /// the disk copy is stale or missing.
  Future<List<CatalogIndexEntry>> getItems({bool forceRefresh = false}) async {
    if (!forceRefresh && _items != null) return _items!;

    if (!forceRefresh) {
      final cached = await _readDisk();
      if (cached != null) {
        _items = cached.items;
        _version = cached.version;
        // Fire-and-forget refresh check if cache is older than _refreshAfter
        unawaited(_maybeRefresh(cached.savedAt));
        return _items!;
      }
    }
    return _fetchAndCache();
  }

  /// Force a fresh fetch + persist.
  Future<List<CatalogIndexEntry>> refresh() async => _fetchAndCache();

  /// Current index version, or null if not loaded yet.
  int? get version => _version;

  /// Find a single entry by id. Returns null if unknown OR if the item's
  /// type/schema isn't supported by this client build.
  Future<CatalogIndexEntry?> findById(String id) async {
    final items = await getItems();
    for (final it in items) {
      if (it.id == id) return it;
    }
    return null;
  }

  /// Returns items filtered to one type (e.g. 'canvas_scene').
  Future<List<CatalogIndexEntry>> ofType(String type) async {
    final items = await getItems();
    return items.where((it) => it.type == type).toList(growable: false);
  }

  Future<void> clearCache() async {
    _items = null;
    _version = null;
    try {
      final f = await _diskFile();
      if (f.existsSync()) await f.delete();
    } catch (e) {
      debugPrint('[CatalogIndex] cache clear error: $e');
    }
  }

  // ── Internals ──────────────────────────────────────────────────────

  Future<File> _diskFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/$_filename');
  }

  Future<_DiskCache?> _readDisk() async {
    try {
      final f = await _diskFile();
      if (!f.existsSync()) return null;
      final raw = await f.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = f.lastModifiedSync();
      return _DiskCache(
        version: json['version'] as int? ?? 0,
        items: _parseItems(json),
        savedAt: savedAt,
      );
    } catch (e) {
      debugPrint('[CatalogIndex] disk read failed: $e');
      return null;
    }
  }

  Future<void> _maybeRefresh(DateTime savedAt) async {
    if (DateTime.now().difference(savedAt) < _refreshAfter) return;
    if (!await Connectivity.hasInternet()) return;
    try {
      await _fetchAndCache();
    } catch (_) {}
  }

  Future<List<CatalogIndexEntry>> _fetchAndCache() async {
    if (!await Connectivity.hasInternet()) {
      // Fall back to whatever the in-memory copy is, or empty.
      return _items ?? const [];
    }
    final r = await http
        .get(Uri.parse(_remoteUrl))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      debugPrint('[CatalogIndex] HTTP ${r.statusCode}');
      return _items ?? const [];
    }
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    _version = json['version'] as int? ?? 0;
    _items = _parseItems(json);
    try {
      final f = await _diskFile();
      await f.writeAsString(r.body);
    } catch (e) {
      debugPrint('[CatalogIndex] disk write failed: $e');
    }
    debugPrint(
        '[CatalogIndex] v$_version loaded with ${_items!.length} supported items');
    return _items!;
  }

  /// Parses raw JSON, filtering out items unsupported by this app build and
  /// items the admin has unpublished.
  ///
  /// This is the single chokepoint every consumer funnels through (getItems,
  /// findById, ofType, disk and network alike), so filtering here covers them
  /// all — and any future consumer is protected by default. Per-consumer
  /// filtering is what produced the hardcoded hide-lists this replaces.
  ///
  /// Note the admin normally OMITS unpublished items from the index entirely,
  /// which is what makes hiding work on already-shipped clients. This check is
  /// defence in depth for an index written by an older tool.
  List<CatalogIndexEntry> _parseItems(Map<String, dynamic> json) {
    final raw = (json['items'] as List?) ?? const [];
    final out = <CatalogIndexEntry>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final m = entry.cast<String, dynamic>();
      if (m['published'] == false) continue;
      if (!CapabilityRegistry.itemSupported(m)) continue;
      try {
        out.add(CatalogIndexEntry.fromJson(m));
      } catch (e) {
        debugPrint('[CatalogIndex] skip malformed entry ${m['id']}: $e');
      }
    }
    return out;
  }
}

/// Surfaces a catalog item can be curated out of, one at a time, without
/// hiding it everywhere. Values are the strings stored in the scene spec's
/// `hidden_in` array — keep them in sync with the admin's scene editor.
///
/// Distinct from `published:false`, which removes an item from the app
/// entirely. These let a scene stay reachable (e.g. Cultura, Daily) while
/// disappearing from a browsing tab it doesn't fit.
abstract final class CatalogSurface {
  static const parallaxTab = 'parallax_tab';
  static const cultura = 'cultura';
  static const daily = 'daily';
  static const events = 'events';
}

class CatalogIndexEntry {
  final String id;
  final String type;
  final int schema;
  final Map<String, String> title; // {lang: text}
  final String previewUrl;
  final List<String> tags;
  final String? category;
  final bool featured;
  final String? specUrl;
  final String? minAppVersion;

  /// Surfaces this item is curated out of. See [CatalogSurface].
  final Set<String> hiddenIn;
  // Pass-through for type-specific simple fields (e.g. videoFile for
  // video_wallpaper). Keeps the index extensible without subclassing.
  final Map<String, dynamic> raw;

  const CatalogIndexEntry({
    required this.id,
    required this.type,
    required this.schema,
    required this.title,
    required this.previewUrl,
    required this.tags,
    required this.category,
    required this.featured,
    required this.specUrl,
    required this.minAppVersion,
    required this.hiddenIn,
    required this.raw,
  });

  String titleFor(String lang) => title[lang] ?? title['en'] ?? id;

  /// True when this item should not be listed on [surface].
  bool isHiddenIn(String surface) => hiddenIn.contains(surface);

  factory CatalogIndexEntry.fromJson(Map<String, dynamic> j) {
    final titleField = j['title'];
    final title = <String, String>{};
    if (titleField is Map) {
      for (final e in titleField.entries) {
        title[e.key.toString()] = e.value.toString();
      }
    } else if (titleField is String) {
      title['en'] = titleField;
    } else {
      title['en'] = j['id'].toString();
    }
    return CatalogIndexEntry(
      id: j['id'].toString(),
      type: j['type'].toString(),
      schema: j['schema'] as int,
      title: title,
      previewUrl: j['preview_url']?.toString() ?? '',
      tags: ((j['tags'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      category: j['category']?.toString(),
      featured: j['featured'] as bool? ?? false,
      specUrl: j['spec_url']?.toString(),
      minAppVersion: j['min_app_version']?.toString(),
      hiddenIn: ((j['hidden_in'] as List?) ?? const [])
          .map((e) => e.toString())
          .toSet(),
      raw: Map<String, dynamic>.from(j),
    );
  }
}

class _DiskCache {
  final int version;
  final List<CatalogIndexEntry> items;
  final DateTime savedAt;
  _DiskCache(
      {required this.version, required this.items, required this.savedAt});
}
