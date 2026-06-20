import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/presentation/settings_page.dart';

/// Snackbar tip que recuerda al user que puede activar el reloj,
/// equalizer y demás overlays desde Settings. Solo se muestra una vez
/// por día como máximo — el counter vive en SharedPreferences.
///
/// 2026-06-20 — Por default Pixora aplica wallpapers SIN overlays
/// para minimizar GPU/RAM y dejar la imagen como protagonista.
/// Esta pista invita a opt-in sin ser invasiva.
class HudHintHelper {
  static const _kLastShownDayKey = 'hud_hint_last_shown_day';

  /// Llamar después de aplicar exitosamente un wallpaper. Internamente
  /// gatea por SharedPreferences para no spammear: máximo 1 vez por día.
  static Future<void> maybeShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final lastDay = prefs.getInt(_kLastShownDayKey) ?? 0;
    final today =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ (24 * 60 * 60 * 1000);
    if (lastDay >= today) return;
    await prefs.setInt(_kLastShownDayKey, today);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Tip: activa reloj, equalizer y otros extras en Ajustes',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Ajustes',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SettingsPage(),
              ),
            );
          },
        ),
      ),
    );
  }
}
