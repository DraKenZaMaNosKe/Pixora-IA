// Integration test — flujo "abrir Pixora → tab LIVE → tap primera card →
// APLICAR" hasta el momento donde Flutter invoca el MethodChannel nativo.
//
// El test NO valida:
//   · Ad de AdMob (UI overlay nativa fuera del Flutter tree)
//   · Wallpaper picker de Android (UI sistema fuera de Pixora)
//   · Confirmación visual del wallpaper en home screen
// Esos 3 los validas en device manualmente — son APIs Google/Android,
// no de Pixora.
//
// SÍ valida:
//   · App bootstrap (Supabase, Hive, services) sin crashes
//   · Onboarding/terms skipping si están presentes
//   · Navegación bottom nav → tab LIVE
//   · Grid de live wallpapers carga (RefreshIndicator visible)
//   · Tap primera card abre preview page
//   · Botón APLICAR LIVE WALLPAPER visible y tappable
//   · Tap APLICAR dispara el flow sin throw
//
// Run local:   flutter test integration_test/apply_live_wallpaper_test.dart
// Run device:  flutter drive --driver=test_driver/integration_test.dart \
//                            --target=integration_test/apply_live_wallpaper_test.dart
// Test Lab:    flutter build apk
//              flutter build apk --target=integration_test/apply_live_wallpaper_test.dart
//              (sube ambos APKs como Instrumentation test)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pixora/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('apply live wallpaper end-to-end (Flutter side)', (tester) async {
    // ─── 1. Bootstrap ───────────────────────────────────────────
    app.main();
    // El bootstrap es async + carga catálogos. Le damos 8s holgados.
    await tester.pumpAndSettle(const Duration(seconds: 8));
    debugPrint('[test] App booted');

    // ─── 2. Skip onboarding si aparece ──────────────────────────
    // Onboarding tiene un PageView con botones "Siguiente" → "Comenzar".
    // Si NO aparece (user ya pasó por aquí en una run anterior),
    // continuamos. Damos 2s para que aparezca.
    for (int i = 0; i < 5; i++) {
      final next = find.text('Siguiente');
      final start =
          find.textContaining(RegExp(r'Comenzar|Empezar|Get Started'));
      if (start.evaluate().isNotEmpty) {
        await tester.tap(start.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        break;
      } else if (next.evaluate().isNotEmpty) {
        await tester.tap(next.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 800));
      } else {
        break;
      }
    }
    debugPrint('[test] Past onboarding');

    // ─── 3. Skip terms si aparece ───────────────────────────────
    final accept =
        find.textContaining(RegExp(r'Acepto|Acepto Términos|Accept'));
    if (accept.evaluate().isNotEmpty) {
      await tester.tap(accept.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      debugPrint('[test] Accepted terms');
    }

    // ─── 4. Skip subscription pitch si aparece ──────────────────
    final dismissSub =
        find.textContaining(RegExp(r'Tal vez|Maybe|Ahora no|Later'));
    if (dismissSub.evaluate().isNotEmpty) {
      await tester.tap(dismissSub.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      debugPrint('[test] Dismissed subscription pitch');
    }

    // ─── 5. Verificar que estamos en HomePage ───────────────────
    expect(find.byType(BottomNavigationBar), findsOneWidget,
        reason: 'BottomNavigationBar should be present on home');
    debugPrint('[test] HomePage rendered');

    // ─── 6. Tap tab LIVE ────────────────────────────────────────
    // El tab LIVE tiene icon play_arrow_rounded + tooltip 'LIVE'.
    // Tap directo en el ícono (segundo tab, index 1).
    final liveTab = find.byTooltip('LIVE');
    expect(liveTab, findsOneWidget,
        reason: 'LIVE tab tooltip should exist in BottomNavigationBar');
    await tester.tap(liveTab);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    debugPrint('[test] Switched to LIVE tab');

    // ─── 7. Esperar que el grid cargue ──────────────────────────
    // El grid usa GridView interno. Tras pumpAndSettle, debería tener
    // al menos 1 card visible. Si no, retry hasta 10s.
    bool gridReady = false;
    for (int attempt = 0; attempt < 5; attempt++) {
      await tester.pump(const Duration(seconds: 2));
      final grids = find.byType(GridView);
      if (grids.evaluate().isNotEmpty) {
        gridReady = true;
        break;
      }
    }
    expect(gridReady, isTrue,
        reason: 'LIVE wallpaper grid should load within 10s');
    debugPrint('[test] LIVE grid loaded');

    // ─── 8. Tap primera card del grid ───────────────────────────
    // Las cards no tienen Key específico — buscamos el primer
    // GestureDetector o InkWell hijo del GridView.
    final cards = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(InkWell),
    );
    if (cards.evaluate().isEmpty) {
      // Fallback: cualquier GestureDetector
      final altCards = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(GestureDetector),
      );
      expect(altCards, findsAtLeast(1),
          reason: 'LIVE grid should have at least 1 tappable card');
      await tester.tap(altCards.first);
    } else {
      await tester.tap(cards.first);
    }
    await tester.pumpAndSettle(const Duration(seconds: 4));
    debugPrint('[test] Tapped first LIVE card → preview page should open');

    // ─── 9. Verificar botón APLICAR LIVE WALLPAPER ──────────────
    final applyBtn = find.textContaining(
      RegExp(r'APLICAR LIVE WALLPAPER|APLICAR|APPLY'),
    );
    expect(applyBtn, findsAtLeast(1),
        reason: 'APLICAR button should be visible on live preview');
    debugPrint('[test] APLICAR button visible');

    // ─── 10. Tap APLICAR ────────────────────────────────────────
    // A partir de aquí AdService.showInterstitialAd se dispara. El ad
    // es UI nativa que NO podemos tocar desde tester.tap. Solo verificamos
    // que el tap NO crashea.
    await tester.tap(applyBtn.first);
    await tester.pump(const Duration(milliseconds: 500));
    debugPrint('[test] Tapped APLICAR — Flutter handed off to native ad layer');

    // ─── 11. Esperar 3s para confirmar que la app no crasheó ─────
    await tester.pump(const Duration(seconds: 3));
    debugPrint('[test] App still alive 3s after APLICAR tap');

    // Test PASS: el flujo Flutter completo se ejecutó sin throw.
    // El AdService + WallpaperManager native ya están cubiertos por
    // monkey test + manual QA + Crashlytics en producción.
  });
}
