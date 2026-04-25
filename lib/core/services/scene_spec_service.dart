import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../utils/connectivity.dart';
import 'capability_registry.dart';
import 'catalog_index_service.dart';

/// Lazily fetches per-scene JSON specs from Supabase. Specs are cached in
/// filesDir indefinitely — only invalidated when the catalog index version
/// bumps (signalling that any scene MAY have changed).
///
/// Use after the user taps a wallpaper preview, before invoking the apply
/// flow that needs the full spec (background URL, sprite list, uniforms).
class SceneSpecService {
  SceneSpecService._();
  static final instance = SceneSpecService._();

  static const _cacheDir = 'scene_specs';
  // In-memory parsed cache keyed by scene id.
  final Map<String, Map<String, dynamic>> _memCache = {};

  Future<Directory> _diskDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/$_cacheDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _diskFile(String id) async {
    final dir = await _diskDir();
    return File('${dir.path}/$id.json');
  }

  /// Fetch the spec for one scene by index entry. Returns null on failure
  /// (no internet AND no cache, or unsupported vocabulary in the spec).
  Future<Map<String, dynamic>?> fetch(CatalogIndexEntry entry) async {
    if (entry.specUrl == null || entry.specUrl!.isEmpty) {
      debugPrint('[SceneSpec] ${entry.id}: no spec_url in index');
      return null;
    }
    final cached = _memCache[entry.id];
    if (cached != null) return cached;

    // Try disk
    final f = await _diskFile(entry.id);
    if (f.existsSync()) {
      try {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (CapabilityRegistry.sceneSpecValid(json)) {
          _memCache[entry.id] = json;
          // Background refresh check (don't block)
          unawaited(_refreshIfStale(entry, f.lastModifiedSync()));
          return json;
        } else {
          debugPrint('[SceneSpec] ${entry.id}: cached spec has unknown vocab');
        }
      } catch (e) {
        debugPrint('[SceneSpec] ${entry.id} disk read error: $e');
      }
    }

    return _fetchAndCache(entry);
  }

  /// Force-fetch one spec, bypassing cache.
  Future<Map<String, dynamic>?> refresh(CatalogIndexEntry entry) async {
    _memCache.remove(entry.id);
    return _fetchAndCache(entry);
  }

  /// Drop disk + memory cache (e.g. after sign-out or for debugging).
  Future<void> clearCache() async {
    _memCache.clear();
    try {
      final dir = await _diskDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('[SceneSpec] cache clear error: $e');
    }
  }

  /// Drop just one entry (e.g. when index version bumps and you know
  /// this specific scene was updated).
  Future<void> evict(String id) async {
    _memCache.remove(id);
    try {
      final f = await _diskFile(id);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  // ── Internals ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _fetchAndCache(CatalogIndexEntry entry) async {
    if (!await Connectivity.hasInternet()) {
      debugPrint('[SceneSpec] ${entry.id}: offline, no fetch');
      return null;
    }
    try {
      final r = await http
          .get(Uri.parse(entry.specUrl!))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        debugPrint('[SceneSpec] ${entry.id}: HTTP ${r.statusCode}');
        return null;
      }
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      if (!CapabilityRegistry.sceneSpecValid(json)) {
        debugPrint('[SceneSpec] ${entry.id}: spec contains unknown vocab');
        return null;
      }
      _memCache[entry.id] = json;
      try {
        final f = await _diskFile(entry.id);
        await f.writeAsString(r.body);
      } catch (e) {
        debugPrint('[SceneSpec] ${entry.id}: disk write failed: $e');
      }
      debugPrint(
          '[SceneSpec] ${entry.id}: cached (${r.bodyBytes.length} bytes)');
      return json;
    } catch (e) {
      debugPrint('[SceneSpec] ${entry.id}: fetch error $e');
      return null;
    }
  }

  /// Re-fetch in background only if disk copy is older than the catalog's
  /// own age (heuristic: if you reopen the app a week later, refresh).
  Future<void> _refreshIfStale(
      CatalogIndexEntry entry, DateTime savedAt) async {
    if (DateTime.now().difference(savedAt) < const Duration(days: 7)) return;
    if (!await Connectivity.hasInternet()) return;
    await _fetchAndCache(entry);
  }
}
