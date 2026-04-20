import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

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
}
