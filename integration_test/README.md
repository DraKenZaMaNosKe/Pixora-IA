# Pixora — Integration tests

Tests end-to-end que ejecutan el app real (no mocks de widgets) y validan
flujos críticos. Útiles para Firebase Test Lab Instrumentation tests.

## Qué valida cada test

| Archivo | Flujo validado | Cubre hasta |
|---|---|---|
| `apply_live_wallpaper_test.dart` | Open → tab LIVE → primera card → APLICAR | Tap del botón APLICAR (antes del ad nativo) |

Los tests NO validan ads de AdMob ni el wallpaper picker de Android — esos
son UI sistema/Google fuera del Flutter tree.

## Correr local

```bash
# 1) Conecta tu device por USB (adb devices debe mostrarlo)
adb devices

# 2) Run el test
flutter test integration_test/apply_live_wallpaper_test.dart

# Variante con driver explícito (igual de válido):
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/apply_live_wallpaper_test.dart
```

Si `test_driver/integration_test.dart` no existe, créalo con este contenido
de una línea:

```dart
import 'package:integration_test/integration_test_driver.dart';
Future<void> main() => integrationDriver();
```

Los `debugPrint('[test] ...')` aparecen en el output — útil para ver
exactamente qué paso pasó.

## Subir a Firebase Test Lab

Test Lab corre estos tests como **Instrumentation tests** (más control que
Robo). Pasos:

```bash
# 1) Build el APK de la app
flutter build apk

# 2) Build el APK del test runner (separado, contiene los integration tests)
flutter build apk --target=integration_test/apply_live_wallpaper_test.dart

# 3) Verás 2 APKs:
#    build/app/outputs/flutter-apk/app-debug.apk           (la app)
#    build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk (los tests)
```

En Firebase Test Lab:

1. Console → Test Lab → **Run a test → Instrumentation**
2. **Upload your app APK**: sube `app-debug.apk`
3. **Upload your test APK**: sube `app-debug-androidTest.apk`
4. Selecciona devices (recomendado: Pixel 7 / Galaxy A53 / Pixel 5 para
   cubrir API 33 / 33 / 30)
5. Click **Start test**

15-20 min después tienes reporte por cada device con:
- ✅/❌ status de cada `testWidgets()` call
- Video MP4 del run completo
- Screenshots en cada paso
- Stacktrace si algo falla

## Por qué hay 2 APKs

Flutter compila los integration tests como una app aparte que se monta
sobre tu app real durante el test. El "test runner APK" contiene solo el
código de los tests + el binding; reusa todo lo demás del app APK.

## Agregar nuevos tests

Cada flow crítico = 1 archivo. Convención sugerida:

| Flujo | Archivo |
|---|---|
| Apply static wallpaper | `apply_static_wallpaper_test.dart` |
| Apply ringtone | `apply_ringtone_test.dart` |
| AURA play + stop | `aura_play_stop_test.dart` |
| Apply day cycle | `apply_day_cycle_test.dart` |

Plantilla base: copia `apply_live_wallpaper_test.dart`, cambia la sección
6-10 con los pasos del flujo nuevo.

## Limitaciones conocidas

- Los `debugPrint` solo aparecen en stdout del runner, NO se guardan en
  artefactos del Test Lab (usa `expect()` con `reason:` descriptivo si
  quieres mensajes que sobrevivan al run).
- El test usa `pumpAndSettle()` con timeouts holgados (8s bootstrap, 3s
  navegación). Si Test Lab tiene devices lentos, sube los timeouts.
- Si la app cambia el texto de los botones (ej. "APLICAR" → "ENCENDER"),
  el test falla — actualiza los `find.text()` correspondientes.
