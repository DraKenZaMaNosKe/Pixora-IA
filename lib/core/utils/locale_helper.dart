import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../services/app_strings_service.dart';

/// Tiny helper for picking ES vs EN strings without a full l10n setup.
/// Reads the device locale via `Platform.localeName` (e.g. "es_MX", "en_US").
class LocaleHelper {
  LocaleHelper._();

  static bool get isSpanish {
    final name = Platform.localeName.toLowerCase();
    return name.startsWith('es');
  }

  static String pick({required String es, required String en}) =>
      isSpanish ? es : en;

  static bool isSpanishContext(BuildContext context) {
    final l = Localizations.maybeLocaleOf(context);
    if (l != null) return l.languageCode == 'es';
    return isSpanish;
  }

  /// Reads a CMS-controlled string by [key]. If the key isn't in the CMS
  /// cache (offline, first launch, or never seeded), returns the hardcoded
  /// fallback for the current locale. Safe to use anywhere [pick] is used.
  ///
  /// Migrate gradually: replace `LocaleHelper.pick(es:, en:)` with
  /// `LocaleHelper.fromCms('key.path', fallbackEs:, fallbackEn:)` for any
  /// string that should be editable from pixora-admin.
  static String fromCms(
    String key, {
    required String fallbackEs,
    required String fallbackEn,
  }) {
    final remote = AppStringsService.instance.get(key);
    final lang = isSpanish ? 'es' : 'en';
    final fallback = isSpanish ? fallbackEs : fallbackEn;
    if (remote == null) return fallback;
    final value = remote[lang];
    if (value == null || value.isEmpty) return fallback;
    return value;
  }
}
