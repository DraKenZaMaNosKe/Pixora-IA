import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists FCM catalog_invalidate scopes when the app is backgrounded.
/// The foreground isolate consumes them on resume (bg handler has no singletons).
class CatalogInvalidateStore {
  CatalogInvalidateStore._();

  static const _fileName = 'pending_catalog_invalidate.json';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> recordPending(String scope) async {
    try {
      final f = await _file();
      Map<String, dynamic> data = {};
      if (f.existsSync()) {
        try {
          data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        } catch (_) {
          data = {};
        }
      }
      final scopes = <String>{
        ...((data['scopes'] as List?)?.cast<String>() ?? const []),
        scope,
      };
      if (scope == 'all') {
        scopes.add('all');
      }
      await f.writeAsString(jsonEncode({
        'scopes': scopes.toList(),
        'ts': DateTime.now().toUtc().toIso8601String(),
      }));
      debugPrint('[CatalogInvalidate] pending scope=$scope');
    } catch (e) {
      debugPrint('[CatalogInvalidate] recordPending error: $e');
    }
  }

  /// Returns scopes to process; clears the pending file.
  static Future<List<String>> consumePending() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return [];
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      await f.delete();
      final scopes =
          (data['scopes'] as List?)?.cast<String>().toList() ?? const [];
      if (scopes.isEmpty) return [];
      debugPrint('[CatalogInvalidate] consume scopes=$scopes');
      return scopes;
    } catch (e) {
      debugPrint('[CatalogInvalidate] consumePending error: $e');
      return [];
    }
  }
}