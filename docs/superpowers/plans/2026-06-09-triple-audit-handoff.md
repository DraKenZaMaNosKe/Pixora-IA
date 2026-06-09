# Handoff 2026-06-09 — Triple audit (AdMob status, v2 progress, smoke test)

> **Contexto del handoff**
> Generado al final de una sesión work-PC el 2026-06-09. Eduardo va de regreso
> a casa y va a continuar la sesión en su otra máquina pidiendole a Claude que
> revise esta propuesta y aplique lo que esté correcto. Este documento es
> autosuficiente — el próximo Claude no necesita contexto del chat previo.
>
> **Estado del repo cuando esto se escribió**
> - Branch: `play-store-estable` @ `acb7ab5` (Tue Jun 9 00:01:07 2026)
> - Branch paralelo: `pixora-v2-compose` @ `9d3304d` (port nativo en progreso)
> - Working tree limpio (acabamos de hacer `git reset --hard origin/play-store-estable` + `git clean -fd`)
> - Device de pruebas (Samsung RF8X903KZ3K) NO conectado en el momento de escribir esto

---

## 0. Decisiones que necesito de Eduardo

Antes de aplicar nada, contesta estas 4 preguntas — cada una destraba una acción concreta:

1. **AdMob**: ¿flipeamos a production unit IDs YA, o esperamos más confirmación de stability con test ads?
   _→ Ver §1.4 para los cambios exactos si decides flip._

2. **v2 priority**: del long-tail pendiente en v2 (Arcano · Pixora Daily · Auto-Rotate · Text CMS · AI Generate · IAP), ¿cuál sigue?
   _→ Sugerencia mía abajo en §2.4._

3. **Smoke test**: cuando conectes el Samsung, ¿lo corremos contra `acb7ab5` solo (los 3 presets nuevos), o capturamos también el flujo de apply de wallpaper para portarlo a v2 (estilo logcat-driven port)?

4. **AdMob audit en v2-compose**: ¿quieres que también audite cómo quedó el AdMob interstitial del commit v2 `0df0352`? (No lo hice en esta pasada).

---

## 1. AdMob — audit del commit `1412c71` (2026-06-03)

### 1.1. Lo que cambió textualmente

```diff
-  static bool get _debugDisableAds => true;
+  static bool get _debugDisableAds => false;
+
+  static bool get adsDisabledForUser =>
+      _debugDisableAds || SubscriptionService.instance.hasAccess;
```

Y se añadió **`NativeAdService`** + **`NativeAdCard`** widget que inyecta una tarjeta de anuncio cada 6 wallpaper cards en los carruseles horizontales (TRENDING, NEW, ARTE, etc.). Estilo: gold-framed, 280×260, "AD" pill top-right por policy de AdMob, shimmer mientras carga, oculta en failure.

### 1.2. 🚨 Hallazgo crítico — Mensaje vs realidad

**El commit message dice**: *"Real users get real ads = revenue restored."*
**La realidad del código**: **revenue NO restaurado.** Ambos unit IDs siguen siendo los de Google para TEST ads.

| Tipo | Unit ID en código | Es | Origen |
|---|---|---|---|
| Interstitial | `ca-app-pub-3940256099942544/1033173712` | **TEST de Google** | `lib/core/services/ad_service.dart:30` |
| Native | `ca-app-pub-3940256099942544/2247696110` | **TEST de Google** | `lib/core/services/native_ad_service.dart:26` |
| Production interstitial | `ca-app-pub-6734758230109098/6687118537` | documentado en comentario, NO usado | `ad_service.dart:29` |
| Production native | `_prodAdUnitIdAndroid = ''` | **string vacío** | `native_ad_service.dart:30` |

Hay un comentario en `ad_service.dart:23-29` del 2026-05-09 que dice:

> *"2026-05-09 TEMPORAL — Google test interstitial... REVERTIR a 'ca-app-pub-6734758230109098/6687118537' cuando confirmemos [si el stuttering es problema de inventory]."*

Es decir, el flag se prendió pero los IDs se quedaron como test. **Tu app en Play Store muestra ads test = 0 USD de revenue por interstitial.**

### 1.3. Lo que SÍ está bien

- **Test devices registrados** (`_testDeviceIds` con el Samsung `RF8X903KZ3K`) — aunque flipees a production IDs mañana, tu Samsung seguirá viendo test creatives → cero riesgo de suspensión por self-clicks tuyos.
- **Subscription gate unificado** con `adsDisabledForUser` — interstitial y native consultan la misma fuente de verdad para el bypass por suscripción. Buena hygiene.
- **Lifecycle del NativeAd correcto** — cada widget posee y disposes su `NativeAd` en unmount, sin pool compartido. Más simple y correcto para Material 3 + lazy lists.
- **Política AdMob respetada**: "AD" pill arriba a la derecha en cada native card (cumple "clear ad disclosure").
- **Validator del native template** confirmó "No implementation issues" en el Samsung A15.

### 1.4. Cambios exactos si decides flipear a producción

**Paso A — Interstitial** (`lib/core/services/ad_service.dart` línea 30):
```diff
-  static const _interstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712';
+  static const _interstitialAdUnitId = 'ca-app-pub-6734758230109098/6687118537';
```

**Paso B — Native** (`lib/core/services/native_ad_service.dart` línea 30):
1. Primero crear el ad unit en AdMob console (Native, app `com.orbix.pixora`).
2. Anotar el unit ID resultante.
3. Pegarlo así:
```diff
-  static const _prodAdUnitIdAndroid = '';
+  static const _prodAdUnitIdAndroid = 'ca-app-pub-6734758230109098/<NEW_NATIVE_ID>';
```

**Paso C — Limpiar comentario temporal** en `ad_service.dart:23-29` (eliminar referencia al test ID porque ya no aplica).

**Paso D — Smoke test obligatorio en el Samsung**:
- Verificar que TUS impressions aparecen como "test impressions" en AdMob console (no facturadas, no flagged).
- Si por error alguna aparece como real impression, **abortar** y revertir `_testDeviceIds` antes de cualquier release.

### 1.5. Recomendación

**No flipear todavía si en los últimos 2 días viste stuttering o crashes con los test ads.** Esos serían señal de que el inventory de producción va a tener problemas peores.

**Sí flipear si los test ads corrieron limpios y quieres empezar a recolectar revenue.** Las nuevas instalaciones desde Play Store ya están en bola de nieve.

---

## 2. v2 Compose — progreso de la rama `pixora-v2-compose`

### 2.1. Snapshot cuantitativo

- Comparado con `692edf5` (Sprint S2, donde lo dejamos hace ~16 días): **+22 commits**.
- Velocidad: ~1.4 commits/día.
- Cobertura aprox. de feature parity v1 ↔ v2: **~70%**.
- Archivos Kotlin bajo `android/app/src/main/kotlin/com/orbix/pixora/`: **76**.
- Screens Compose en `features/`: **18** (los 13 tabs + 5 detalles).

### 2.2. Lo que ya está construido en v2

| Sprint / Feature | Commit | Estado |
|---|---|---|
| Wallpapers grid Supabase | `692edf5` | ✅ |
| Static wallpaper apply (tap card → detail → setBitmap) | `194fa20` | ✅ |
| Panoramic-aware apply | `15766a4` | ✅ |
| AURA player con Media3 + mini-player persistente | `95e45ff` | ✅ |
| Ringtones preview con MediaPlayer | `bdc09f9` | ✅ |
| Pixora Cosmos design system (fonts + theme + nav) | `b7968d8` | ✅ |
| Ember Nav horizontal con los 13 tabs | `fabb3a5` | ✅ |
| Visual passes: editorial hero, avatar, shimmer, download HUD | `68c786f` | ✅ |
| Live Frosted Stage + Ringtone Cassette A/B | `a9d9978` | ✅ |
| AURA Sacred Geometry Mandala per-frequency | `c0e909e` | ✅ |
| Control Deck Settings + Wunderkammer Favs + Comic Stories | `507b454` | ✅ |
| DayCycle Hour Slider Time Scrubber | `8044059` | ✅ |
| Favoritos end-to-end con Room | `1f2030d` | ✅ |
| Stats tracking + AURA polish (scrubber, sleep, loop) | `1c3651b` | ✅ |
| Google Sign-In via Credential Manager | `761043b` | ✅ |
| Live wallpapers apply MediaPlayer end-to-end | `c6657e7` | ✅ |
| Stories viewer + DayCycle detail + Live re-apply kill-process | `8d0e23f` | ✅ |
| Panoramic native scroll + HUD chips + hero swipe + 3D tilt | `caa66c5` | ✅ |
| Apply target sheet + panoramic FLAG_SYSTEM attempts | `3b7be35` | 🚧 WIP |
| Port v1 PanoramicWallpaperRenderer + StaticWallpaperService | `9d3304d` | ✅ |

### 2.3. Lo que NO está aún en v2 (long-tail)

Comparando contra el feature set completo de v1:
- ❌ **AI Generate** — `AiGenerateScreen.kt` existe pero solo scaffold (no veo commit feature)
- ❌ **Arcano** — solo scaffold, no veo Tarot/sessions
- ❌ **Eventos** — solo scaffold
- ❌ **Cultura** — solo scaffold
- ❌ **Pixora Daily** — no veo `PixoraDailyScreen.kt` ni features de daily auto-rotate
- ❌ **Auto-Rotate** — no veo
- ❌ **Text CMS** — sistema de strings dinámicos vía Supabase, no veo
- ❌ **AdMob native ads en carruseles** — v1 los tiene desde commit `1412c71`; v2 solo interstitial (`0df0352`)
- ❌ **In-app billing / Premium** — solo referencia a `SubscriptionService.hasAccess` en v1; no veo `billing-ktx` integrado
- ❌ **Theme switcher iOS ↔ Black & Gold** — no veo en commits

### 2.4. Recomendación de prioridad para el próximo sprint

Mi sugerencia por orden de **impacto/esfuerzo**:

1. **AdMob native ads en v2** (alto impacto revenue, bajo esfuerzo — ya tienes el patrón en v1, port directo). Especialmente si flipeas IDs de producción en §1.4.
2. **In-app billing** (revenue + value prop del Premium tier). Sin Premium, los users con buena conexión seguirán viendo ads y cobrar suscripción es la única vía de revenue alternativa.
3. **Pixora Daily** (alta visibility — es un differentiator visible en bottom nav).
4. **Auto-Rotate** (relacionado a Daily, comparte infra de scheduling).
5. **Text CMS** (low impact en usuario final pero te ahorra un release cada vez que cambia un copy).
6. **AI Generate / Arcano / Eventos / Cultura** — features de discovery/contenido; bajos en prioridad porque son nice-to-have, no core loop.

Razón del orden: **revenue primero (1+2), después features visibles (3+4), después infraestructura (5), al final long-tail de contenido (6)**.

---

## 3. Smoke test del commit `acb7ab5` en device

### 3.1. Contexto

El commit `acb7ab5` agrega 3 cambios visuales al wallpaper engine nativo:
- **CRT preset**: nuevo `HudStyle.PILLAR_STACK` (3 capacitores verticales cyan top-right) + remueve la onda sinusoidal blanca de las barras del visualizador.
- **Cyber preset**: prende `showSystemHud=true` → ahora se ven los hex shields amarillos.
- **CLASICO preset Diamond Plasma**: paleta refinada (rango hue `[0.50, 0.97]` → solo cyan/pink/magenta/violeta; saturación 0.45→0.95; 2 hue phases por partícula; radio halved).

Análisis estático ya hecho en sesión anterior; conclusión: **bajo riesgo, requiere smoke test visual obligatorio**.

### 3.2. Pre-requisitos

- Samsung RF8X903KZ3K conectado por USB con depuración USB activada.
- APK con commit `acb7ab5` (o más reciente) instalado.
- Live wallpaper de Pixora activado con un canvas_scene (recomendado: `mictlantecuhtli` o `goku_genkidama`).

### 3.3. Setup del logcat

```powershell
$env:PATH += ";$env:LOCALAPPDATA\Android\Sdk\platform-tools"
adb devices                                       # verificar device
adb shell dumpsys package com.orbix.pixora |      # verificar versión
    Select-String "versionName|versionCode"
adb logcat -c                                     # limpiar buffer
adb logcat -v time *:E flutter:V "*:I" > "$env:TEMP\pixora_smoke_acb7ab5.txt"
# (Ctrl+C cuando termines el ejercicio)
```

### 3.4. Casos de prueba

| # | Caso | Esperado | Verifica |
|---|---|---|---|
| 1 | Activar **preset CRT TERMINAL** | 3 pilares verticales cyan top-right, fill desde abajo, valor arriba/label abajo. EQ bars cyan SIN onda sinusoidal blanca encima. | `drawPillarStack` + remoción del sine wave en `drawCrtBars` |
| 2 | Activar **preset CYBER GLITCH** | Hex shields amarillos (`#FCEE0A`) visibles top-right. EQ con RGB-split igual que antes. | `showSystemHud=true` flip |
| 3 | Activar **preset CLASICO Diamond Plasma** | Partículas con paleta cyan + pink + magenta + violeta (cero rojos/naranjas/amarillos/verdes). Cada wisp visiblemente bicolor. Partículas más chiquitas y vivas. | Palette refinement en `EqualizerRenderer.kt:488-496` |
| 4 | Alternar 3 presets 20× | Sin leaks: `adb shell dumpsys meminfo com.orbix.pixora:wallpaper` no crece monotónicamente. | Re-uso de Paint objects (`shapePaint`, `strokePaint`, `textPaint`) |
| 5 | Tap pantalla durante CRT | Touch interaction intacto (si aplica al preset). | Sin regresiones del touch system |

### 3.5. Métricas a extraer del logcat post-captura

```powershell
# Errores graves
Get-Content $env:TEMP\pixora_smoke_acb7ab5.txt |
    Select-String -Pattern "FATAL|AndroidRuntime|HudRenderer|PILLAR_STACK"

# Memoria del wallpaper proc al final
adb shell dumpsys meminfo com.orbix.pixora:wallpaper |
    findstr "TOTAL Native Dalvik"
```

### 3.6. Criterios de pass/fail

- ✅ **PASS** si los 5 casos visuales se ven como se describen Y la memoria no crece monotónicamente Y no hay `FATAL` en el logcat.
- ❌ **FAIL** si algún preset no renderiza el HUD esperado, hay crash en el wallpaper proc, o hay leak observable (>50MB de crecimiento en 20 alternaciones).

---

## 4. Resumen ejecutivo

| Workstream | Veredicto | Acción siguiente |
|---|---|---|
| (1) AdMob | Habilitado pero con TEST IDs → **cero revenue real** (vs lo que dice el commit message) | Decisión #1: ¿flipeamos IDs ahora? Pasos exactos en §1.4 |
| (2) v2-compose | Avanzó 22 commits, ~70% feature parity. Lo grueso (browse/apply/audio/favs/auth) listo. Falta long-tail (Arcano, Daily, Text CMS, IAP) | Decisión #2: ¿qué del long-tail sigue? Sugerencia en §2.4 |
| (3) Smoke test acb7ab5 | Plan listo, pendiente device | Conectar Samsung y dispararlo cuando puedas |

## 5. Anexos — ubicaciones de archivos relevantes

- AdMob código v1: `lib/core/services/ad_service.dart`, `lib/core/services/native_ad_service.dart`, `lib/features/wallpapers/presentation/widgets/native_ad_card.dart`
- HUD renderer v1: `android/app/src/main/kotlin/com/orbix/pixora/renderers/HudRenderer.kt`, `HudPreset.kt`, `EqualizerRenderer.kt`
- v2 Compose: `android/app/src/main/kotlin/com/orbix/pixora/features/`
- Plan original v2: `PIXORA_V2_PLAN.md` en rama `pixora-v2-compose`
