# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Pixora IA — Flutter app for Android/iOS offering wallpapers (static, live video, interactive, shader, day-cycle), stories, ringtones, and the AURA wellness audio module. Android is the primary target; iOS builds a reduced feature set (only `WallpapersPage`, `FavoritesPage`, `SettingsPage` — everything else is gated behind `if (!Platform.isIOS)`).

- Package: `com.orbix.pixora`
- Current branch: `play-store-estable`
- Version source of truth: `pubspec.yaml` (`version: X.Y.Z+N`)

## Common commands

```bash
flutter pub get                                 # install deps
flutter analyze lib/features/<feature>          # scope analyzer to a feature for speed
flutter build apk --debug                       # debug APK at build/app/outputs/flutter-apk/app-debug.apk
flutter build appbundle                         # release AAB for Play Store
flutter run                                     # run on connected device

# Install debug APK on a specific device (when multiple attached)
adb devices
adb -s <SERIAL> install -r build/app/outputs/flutter-apk/app-debug.apk
# If INSTALL_FAILED_UPDATE_INCOMPATIBLE, uninstall first (release signature conflict):
adb -s <SERIAL> uninstall com.orbix.pixora

# Debug a native crash on device
adb -s <SERIAL> logcat -c && adb -s <SERIAL> shell am start -n com.orbix.pixora/.MainActivity
adb -s <SERIAL> logcat -d | grep -E "flutter|Pixora|AndroidRuntime|FATAL"
```

Tests: no `test/` suite is wired up — validation is manual on device.

## Architecture big picture

**Feature-folder layout.** `lib/features/<name>/{data,presentation,providers,services}` — each feature owns its model, Supabase catalog service, Riverpod providers, pages and widgets. Cross-cutting singletons live in `lib/core/services/` and are accessed as `SomeService.instance` (plain Dart singletons, not Riverpod).

**Singletons you should reuse (never reimplement):**
- `AdService.instance.showInterstitialAd(onAdDismissed:)` — alternating interstitial: 1st action shows, 2nd doesn't, 3rd shows… Internally awards credits on dismissal via `CreditService.earnFromAd()`. Any "install / apply / download" action across the app must go through this wrapper so ads and diamond rewards stay consistent. There's a `_debugDisableAds = true` flag that bypasses ads during development.
- `CreditService.instance` — Hive-backed ChangeNotifier. Use `earnFromAd()` (called automatically by `AdService`) and `spend(amount)`. Never mutate the balance directly.
- `AuthService.instance` — optional Google Sign-In; the app works fully signed-out.
- `WallpaperStatsService.instance.trackView(id)` / `trackDownload(id)` — used by every feature for the stats badges; ID prefixes are conventional (`tone_xxx`, `aura_xxx`, `tone_pack_xxx`, etc.).
- `AuraPlayerService.instance` — singleton wrapper around `just_audio` + `just_audio_background` with sleep-timer + loop state. Only place that owns the AudioPlayer; pages read from its streams and call methods.

**Catalog fetching — two different patterns, do not mix them up:**
1. **Static JSON in Supabase Storage** (older pattern, used by wallpapers, live wallpapers, stories, day cycles, ringtones): a catalog service does `http.get('${SupabaseConfig.storageBase}/<bucket>/<catalog>.json')` with a 6h in-memory cache, then parses into models via `fromJson`. See `live_wallpaper_catalog_service.dart` as the canonical template.
2. **Postgres table via supabase_flutter** (newer, used only by AURA so far): `Supabase.instance.client.from('aura_tracks').select()`. Used because AURA benefits from bilingual columns and indexable sort order. See `lib/features/aura/data/repositories/aura_repository.dart`.

When adding a new content vertical, pick one pattern and stick with it — don't invent a third.

**Main nav lives in `lib/features/home/presentation/home_page.dart`** as three parallel lists kept in sync manually: `_pages`, `_title` titles, and `BottomNavigationBar.items`. Every non-iOS tab is wrapped in `if (!Platform.isIOS)`. When adding a tab, insert into all three lists in the same position.

**Android native bridge.** `MainActivity.kt` extends `AudioServiceActivity` (NOT `FlutterActivity` — required by `just_audio_background`, bug bit us once) and exposes a `com.orbix.pixora/wallpaper` MethodChannel. All native actions (setWallpaper, setLiveWallpaper, setRingtone, startStory, startDayCycle, startAutoRotate, setShaderWallpaper, resetEngine) are routed through this single channel. `PixoraWallpaperService` runs in an isolated `:wallpaper` process (`android:process=":wallpaper"` in the manifest) — see section below.

### WallpaperService Surface pitfall (hard-learned)

A `WallpaperService` Engine's Surface can only have **one producer** at a time: either Canvas (via `lockCanvas`) or MediaPlayer (via `setSurface`). Once Canvas has touched it, `MediaPlayer.setSurface()` fails with `setVideoSurfaceTexture -22 (EINVAL)` and `unlockCanvasAndPost()` does not release the producer binding. Switching wallpaper modes therefore requires killing the `:wallpaper` process so Android respawns the Engine with a fresh Surface. This is what `MainActivity.killWallpaperProcess()` does, and it is called from `setLiveWallpaper()` on every mode switch. **Don't try to share a Surface between Canvas and MediaPlayer** — it can't be done.

Related: this is why `PixoraWallpaperService` lives in `android:process=":wallpaper"`. Putting it in the main process caused Surface producer conflicts with the main Activity. Don't revert this.

Related commits if you need context: `cc9da25` (process split), `e871c31` (ExoPlayer → MediaPlayer switch), `061aa1c` (codec cleanup).

### AURA module (wellness audio)

- Content catalog: 9 Solfeggio frequency MP3s + 15 nature sounds, hosted in Supabase bucket `aura-audio`, metadata in table `public.aura_tracks` (bilingual en/es columns).
- Content pipeline lives under `tools/aura/` (Python + ffmpeg scripts). `tracks_manifest.json` there is the single source of truth; regenerating content = edit manifest → run the relevant script → run `upload_supabase.py` (needs `Service Role Key` in `KEYS_LOCAL.md`).
- Background playback works because `MainActivity` extends `AudioServiceActivity` AND `JustAudioBackground.init(...)` is called in `main.dart` BEFORE `runApp`. Removing either breaks background audio.
- See `docs/superpowers/plans/2026-04-07-aura-content-pipeline.md` and `2026-04-07-aura-app-integration.md` for the design.

## Bilingual strings

No `flutter_localizations` `.arb` setup — `lib/core/utils/locale_helper.dart` reads `Platform.localeName` and exposes `isSpanish` / `pick(es:, en:)`. Models like `AuraTrack` have `displayName` / `displayDescription` getters that pick the right one. Most other features are English-only with occasional inline Spanish. If you add user-facing strings to AURA, use the helper; for other features follow what's already in that file.

## Key config references

- Supabase project: `vzuwvsmlyigjtsearxym` — URL and anon key in `lib/core/constants/supabase_config.dart`. Service role key and other secrets are in `KEYS_LOCAL.md` (gitignored).
- AdMob unit IDs are hard-coded in `lib/core/services/ad_service.dart`.
- Android min/target SDK, NDK version, signing: `android/app/build.gradle`. Release signing reads from `android/key.properties` (gitignored).
- Project master doc: `G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx` — section 14 tracks AURA status and decisions.

## Conventions

- Commit messages use Conventional Commits prefixes scoped by feature: `feat(aura):`, `fix(live):`, `chore:`, etc.
- Don't commit the service role key, debug APKs, `android/key.properties`, or anything under `tools/aura/out/` and `tools/aura/raw/` (all gitignored).
- When `Edit`-ing Kotlin files under `android/`, remember CRLF warnings are expected on Windows — ignore them unless git itself errors out.

---

# Master Document (Pixora IA Documento Maestro)

> Verbatim snapshot of `G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx` — the product / business / admin source of truth. Read this to understand *why* decisions were made and *what's next*. For *how things work today*, the code wins.

# PIXORA IA — Documento Maestro del Proyecto

Orbix Studio — Abril 2026 — v1.0

## Indice
1. Introduccion
2. Nuestra Historia
3. Justificacion
4. Mision, Vision y Valores
5. Objetivos
6. Objetivos Especificos
7. Arquitectura del Producto
8. Modelo de Negocio
9. Plan de Lanzamiento
10. Metricas y KPIs
11. Seguridad: Credenciales y Llaves
12. Registro de Versiones
13. Anexos

## 1. Introduccion
Pixora IA es una aplicacion movil de personalizacion para Android que ofrece wallpapers estaticos, live wallpapers con video, fondos de pantalla interactivos, ciclos de dia/noche automaticos, stories visuales y tonos de llamada. Desarrollada por Orbix Studio, Pixora IA nace con la mision de llevar contenido visual de alta calidad a todos los usuarios del mundo.
Lo que distingue a Pixora IA es su compromiso con la innovacion: el modo Explore permite controlar cada frame de un video wallpaper con el dedo, el sistema de creditos prepara el terreno para la generacion con inteligencia artificial, y cada detalle esta disenado para ofrecer una experiencia unica.
Este documento sirve como guia maestra del proyecto. Es un documento vivo que se actualiza conforme el proyecto evoluciona.

## 2. Nuestra Historia
Todo comenzo con una idea simple: ofrecer contenido genial a todos los usuarios del mundo. Con esa ilusion, nos inspiramos a crear grandes aplicaciones para todos.
Los primeros dias fueron de experimentacion. Creamos wallpapers estaticos de alta calidad, descubriendo que la personalizacion del telefono es una forma de expresion personal. De ahi surgieron los live wallpapers con video, las stories que cuentan historias, los ciclos de dia/noche, y los tonos de llamada.
Cada nueva funcion nacio de la misma pregunta: como hacemos que la experiencia del usuario sea mas especial? Esa pregunta nos llevo a crear el modo Explore, el sistema de creditos, y la futura generacion con IA.
Hoy, Pixora IA es mas que una app. Es el reflejo de un equipo que cree que la tecnologia debe ser accesible, bella y divertida. Y esto apenas comienza.

## 3. Justificacion
El mercado de personalizacion movil es uno de los mas grandes en Google Play Store. Sin embargo, la mayoria de las aplicaciones ofrecen contenido generico, estan plagadas de anuncios invasivos, o cobran precios excesivos.
- Demanda creciente de contenido visual personalizado
- Diferenciacion a traves de funciones innovadoras (Explore mode, IA)
- Modelo de monetizacion equilibrado: ads alternados que respetan al usuario
- Mercado global: el contenido visual trasciende barreras de idioma
- Posicionamiento temprano en generacion con IA
Nuestro principal competidor es Zedge. Sin embargo, Zedge no ofrece live wallpapers interactivos, modo Explore, ni ciclos de dia/noche. Pixora IA entra con funciones que el lider no tiene.

## 4. Mision, Vision y Valores

### Mision
Crear productos de software innovadores y de alta calidad que transformen la experiencia digital de los usuarios, haciendo que la personalizacion sea accesible, divertida y unica para todos.

### Vision
Ser la plataforma lider mundial en personalizacion movil con inteligencia artificial, donde cada usuario pueda expresar su identidad a traves de contenido visual de la mas alta calidad.

### Valores
- Calidad — Cada producto refleja nuestro compromiso con la excelencia
- Innovacion — Nuevas formas de sorprender y deleitar
- Respeto al usuario — Ads no invasivos, experiencia fluida, privacidad protegida
- Accesibilidad — Contenido de primera para todos
- Esfuerzo — Dedicacion genuina por entregar algo triunfador
- Comunidad — Construimos junto con nuestros usuarios

## 5. Objetivos
- Posicionar a Pixora IA como alternativa innovadora en personalizacion movil
- Alcanzar 25,000 descargas en los primeros 6 meses
- Mantener rating de 4.5+ estrellas en Google Play Store
- Generar ingresos sostenibles a traves de publicidad y servicios premium
- Lanzar generacion de wallpapers con IA antes del mes 6

## 6. Objetivos Especificos

### Producto
- Catalogo de 300+ wallpapers de alta calidad para el mes 6
- 15+ video wallpapers con modo Explore
- Generacion con IA usando Replicate (Flux)
- Soporte para 50+ modelos de dispositivos Android

### Negocio
- $300 USD/mes en ingresos AdMob para el mes 6
- Sistema de compra de creditos via Google Play Billing
- Suscripcion Pixora Pro ($49 MXN/mes)

### Crecimiento
- 3+ videos promocionales/semana en TikTok/Reels
- ASO optimizado para busquedas clave
- 100% de resenas respondidas en < 48 horas

## 7. Arquitectura del Producto

### Stack Tecnologico
- Frontend: Flutter (Dart)
- Backend: Supabase (PostgreSQL, Auth, Storage, Realtime)
- Engine: Kotlin nativo (WallpaperService, ExoPlayer, Canvas)
- Ads: Google AdMob (interstitial alternados)
- IA (futuro): Replicate API (Flux/SDXL)

### Modulos
- Wallpapers — Catalogo con descarga, cache y aplicacion
- HOT — Videos en loop + modo Explore con frames
- Stories — Secuencias de wallpapers que rotan
- Day Cycle — 4 wallpapers segun hora del dia
- Tones — Packs de ringtones y alarmas
- AI Generate — Generacion con IA (Coming Soon)
- Credits — Sistema de creditos por ads

## 8. Modelo de Negocio

### Publicidad (actual)
Ads alternados: uno si, uno no. Cada ad visto otorga 15 creditos.

### Creditos y Suscripciones (futuro)
- 500 creditos: $29 MXN
- 1,500 creditos: $69 MXN
- 5,000 creditos: $149 MXN
- 15,000 creditos: $299 MXN
- 50,000 creditos: $699 MXN
- Pixora Pro: $49 MXN/mes (100 creditos/semana + sin ads)
- Pixora Ultra: $99 MXN/mes (ilimitado + 4K)

### Costos
- Supabase: $0-25 USD/mes
- Replicate (IA): ~$0.005 USD/imagen
- Google Play: $25 USD (pagado)

## 9. Plan de Lanzamiento

### Fase 1: Contenido (Semana 1-2)
- 30+ wallpapers
- 15+ videos
- 3+ stories
- 3+ day cycles
- 3+ packs tonos

### Fase 2: Publicacion (Semana 2-3)
- AAB v1.5.1 a Play Store
- Screenshots y video promo
- ASO optimizado
- Testing 3+ dispositivos

### Fase 3: Promocion (Semana 3-5)
- TikTok/Reels 3/semana
- Reddit communities
- YouTube Shorts

### Fase 4: Monetizacion (Semana 5-8)
- Verificar AdMob
- Cuenta de pagos
- Registro fiscal SAT
- Control ingresos/gastos

### Fase 5: Crecimiento (Mes 2-3)
- Contenido tematico
- Features segun feedback
- Comunidad y votacion

### Fase 6: IA y Premium (Mes 3-6)
- Creditos en Supabase
- Edge Function + Replicate
- In-app purchases
- Generacion IA wallpapers y tonos

## 10. Metricas y KPIs
Metrica
Mes 1
Mes 3
Mes 6
Descargas
500
5,000
25,000
DAU
50
500
2,500
Ingresos/mes
$5 USD
$50 USD
$300 USD
Rating
4.0+
4.2+
4.5+
Wallpapers
50
150
300+

## 11. Seguridad: Credenciales y Llaves
SECCION CONFIDENCIAL — No compartir publicamente.

### Supabase
Project ID: vzuwvsmlyigjtsearxym
URL: https://vzuwvsmlyigjtsearxym.supabase.co
Anon Key: <REDACTED — see KEYS_LOCAL.md or master .docx>
Service Role Key: <REDACTED — see KEYS_LOCAL.md or master .docx>

### Google Play / Signing
Package: com.orbix.pixora
Keystore / Key Alias passwords: <REDACTED — see KEYS_LOCAL.md>
SHA-1 Release: FF:0F:46:D4:E2:86:25:D1:14:C6:81:03:11:E4:6B:E4:47:2A:CD:79
SHA-1 Debug: 6C:1B:78:30:54:39:67:0B:B1:54:B4:E0:E6:10:8B:E8:75:27:F3:4D
SHA-1 Play Store: 8C:42:66:C0:7B:90:21:2D:A3:BA:CB:35:18:1A:57:86:02:CF:AE:46

### Google OAuth
<REDACTED — Web/Android Debug/Release/Play Store client IDs + Web secret live in KEYS_LOCAL.md and the master .docx, not in the repo.>

### AdMob
Interstitial Unit ID: ca-app-pub-6734758230109098/6687118537

### Repositorio
GitHub: github.com/DraKenZaMaNosKe/Pixora-IA
Rama produccion: play-store-estable
Rama premium: pixora-premium

## 12. Registro de Versiones
Version
Fecha
Cambios
v1.4.2
Mar 2026
Stats, calendario, rediseno tonos
v1.5.0
Abr 2026
Auditoria codigo, creditos, hero banners, descargas robustas
v1.5.1
Abr 2026
Explore mode, optimizacion renderers, reset engine

## 13. Anexos
Seccion para documentos adicionales, diagramas expandidos, mockups, y referencias.

### A. Estructura del proyecto
Pixora-IA/  lib/core/ — Servicios, constantes, utilidades  lib/features/ — Modulos por funcionalidad  android/app/src/main/kotlin/ — Codigo nativo  assets/ — Recursos estaticos

### B. Enlaces
- Play Console: play.google.com/console
- Supabase: supabase.com/dashboard
- AdMob: apps.admob.com
- Drive Admin: G:/Mi unidad/pixoraIA_admin/admin
Pixora IA — Orbix Studio 2026

## 14. Especificaciones Tecnicas de Contenido
Esta seccion documenta las dimensiones, formatos y requisitos tecnicos para producir contenido compatible con Pixora IA. Se actualiza conforme se descubren nuevos parametros.

### Wallpapers Estaticos
Tipo
Dimensiones
Formato
Estandar (vertical)
1080 x 2340 px
WebP / PNG
HD (vertical)
1440 x 3120 px
WebP / PNG
Panoramico (horizontal scroll)
4128 x 1024 px
WebP / PNG

### Video Wallpapers (HOT)
Parametro
Valor
Resolucion
720x720 o 720x1280 px
Duracion: 5-8 segundos (ideal 6s)
Formato: MP4 (H.264 / AVC)
FPS: 24-30 fps
Audio: Sin audio (muted en el engine)
Tamano maximo: 2 MB recomendado
Keyframes: ffmpeg -g 30 para loop suave
Explore mode: Extrae ~36 frames como WebP a 540px de ancho

### Previews
Preview de wallpaper: 540 x 1170 px, WebP, < 50KB
Preview de video: 720 x 720 px, WebP, < 50KB
Cover de story: 1080 x 2340 px, WebP

### Tonos / Ringtones
Formato: MP3
Duracion ringtone: 15-30 segundos
Duracion notification: 3-8 segundos
Duracion alarm: 15-45 segundos
Tamano maximo: 500 KB por tono

### Day Cycle
Imagenes por tema: 4 (morning, afternoon, evening, night)
Dimensiones: 1080 x 2340 px cada una
Formato: WebP / PNG

### Stories
Frames por story: 4-8 imagenes
Dimensiones por frame: 1080 x 2340 px
Formato: WebP
Captions: 3 idiomas: es, en, ja

### Comando FFmpeg para videos optimizados
ffmpeg -i input.mp4 -vf "scale=720:-1" -g 30 -keyint_min 30 -c:v libx264 -preset slow -crf 18 -an output.mp4

### Nota critica: Compatibilidad de videos para Explore mode
IMPORTANTE: Los videos para Explore mode DEBEN ser encodeados con keyframe en cada frame.
El chip MediaTek (Samsung A15 y similares) tiene un MediaMetadataRetriever limitado que no puede decodificar frames intermedios entre keyframes. Si el video tiene keyframes cada 30 frames, solo se extraeran 6 de 36 frames, causando una imagen corrupta o doble.

### Comando FFmpeg para videos Explore-compatible
ffmpeg -i input.mp4 -vf "scale=540:960" -c:v libx264 -profile:v baseline -level 3.1 -x264-params "keyint=1:min-keyint=1" -crf 23 -an output.mp4

### Parametros clave
profile:v baseline: Perfil mas compatible con todos los dispositivos
keyint=1:min-keyint=1: Cada frame es keyframe — extraccion perfecta
scale=540:960: Resolucion reducida para menor uso de memoria
crf 23: Calidad buena con tamano razonable
-an: Sin audio (no se usa en wallpapers)

### Comando FFmpeg para videos Auto Play (loop normal)
ffmpeg -i input.mp4 -vf "scale=720:-1" -g 30 -keyint_min 30 -c:v libx264 -preset slow -crf 18 -an output.mp4
Para Auto Play no se necesita keyframe en cada frame — ExoPlayer maneja bien cualquier perfil.

### Especificaciones definitivas de video (Samsung A15 / MediaTek compatible)
IMPORTANTE: Estos limites son obligatorios para compatibilidad con chips MediaTek.

#### Video Auto Play (MediaPlayer nativo)
Resolucion maxima: 486 x 720 px (vertical) o 720 x 486 (horizontal)
FPS: 24 fps (NO 30fps)
Codec: H.264 High profile
Tamano maximo: 2.5 MB
Duracion: 5-6 segundos
Audio: Sin audio (-an)
Keyframes: -g 30 (cada segundo)
Player: MediaPlayer nativo (no ExoPlayer — evita conflictos de codec)

#### Comando FFmpeg para Auto Play
ffmpeg -i input.mp4 -vf "scale=406:720" -r 24 -c:v libx264 -profile:v high -g 30 -preset slow -crf 20 -an output.mp4

#### Video Explore Mode (frames pre-extraidos)
Frames: 30-36 por video (6fps x 5-6 segundos)
Resolucion frames: 540 x 960 px
Formato: JPG quality 3
Almacenamiento: Supabase: frames/[nombre_video]/frame_XXXX.jpg
Player: FrameScrubRenderer (Canvas, sin codec)

#### Comando FFmpeg para extraer frames
ffmpeg -i input.mp4 -vf "scale=540:-1,fps=6" -q:v 3 output/frame_%04d.jpg

#### Regla de oro
Videos que superan 486x720 o 2.5MB fallan en MediaTek (Samsung A15, Huawei, Xiaomi budget). Siempre encodear al tamano minimo que se vea bien.

## 15. Conocimiento Generado
Conocimiento tecnico adquirido durante el desarrollo. Cada leccion fue aprendida resolviendo problemas reales.

### Chip MediaTek — Limitaciones
Dispositivos MediaTek (Samsung A15, Huawei budget) tienen restricciones severas en codecs.
- Solo 2-3 instancias simultaneas de MediaCodec
- release() no libera inmediatamente — puede tardar segundos
- System.gc() NO libera codecs — son recursos nativos
- MediaMetadataRetriever deja codecs zombie
- Unica forma de liberar: matar el proceso o dejar que Android recree el Engine
- ExoPlayer compite por las mismas instancias que MediaMetadataRetriever
- MediaPlayer nativo usa codec path diferente — no compite

### ExoPlayer vs MediaPlayer
ExoPlayer: MediaCodec API asincrona. Moderno pero compite por codecs. Causa problemas en MediaTek.
MediaPlayer: Player nativo. Codec path independiente. No compite por instancias.
Conclusion: Para WallpaperService usar MediaPlayer. ExoPlayer es mejor para apps de streaming.

### Surface Lifecycle en WallpaperService
- El Surface se crea en onSurfaceCreated, se destruye en onSurfaceDestroyed
- onVisibilityChanged puede llamarse ANTES de que el Surface este listo
- Si Surface no esta listo, usar handler.postDelayed para reintentar
- NUNCA bloquear main thread esperando al Surface (deadlock)
- setSurface(null) ANTES de stop/release

### Android Wallpaper Picker — La solucion clave
SIEMPRE mostrar el picker al instalar wallpaper, incluso si ya hay uno activo.
El picker (ACTION_CHANGE_LIVE_WALLPAPER) internamente:
- 1. Crea un NUEVO Engine desde cero
- 2. Destruye el anterior (libera codecs, surfaces, memoria)
- 3. Asigna Surface nuevo y limpio
- 4. Muestra preview al usuario
- 5. Si acepta: promueve. Si cancela: restaura.
Cuando saltabamos el picker, Android no recreaba el Engine y los codecs se acumulaban.

### MediaPlayer — Orden correcto
- 1. new MediaPlayer()
- 2. setDataSource(path)
- 3. setSurface(surface)
- 4. setVolume(0f, 0f)
- 5. isLooping = true
- 6. setOnPreparedListener / setOnErrorListener
- 7. prepareAsync()
- 8. En onPrepared: asignar referencia + start()
NO usar setDisplay() en WallpaperService — causa error de keep screen on
NO asignar mediaPlayer antes de READY

### Specs de video compatibles
Resolucion maxima: 486x720 (vertical) o 720x486 (horizontal)
Ancho maximo: 720px en cualquier dimension
FPS: 24 fps (NO 30 ni 60)
Codec: H.264 High profile
Tamano maximo: 2.5 MB
Audio: Sin audio (-an)
ffmpeg -i input.mp4 -vf "scale=406:720" -r 24 -c:v libx264 -profile:v high -g 30 -preset slow -crf 20 -an output.mp4

### Explore Mode — Frames
Frames: 30-36 por video (6fps)
Resolucion: 540px ancho
Formato: JPG quality 3
RAM: 3 frames (~3MB en RGB_565)
CPU idle: 0% — redibuja cada 1s para reloj
Storage: ~60KB por frame, ~2MB por video
ffmpeg -i input.mp4 -vf "scale=540:-1,fps=6" -q:v 3 output/frame_%04d.jpg

### Fade Loop optimizado
- Cachear duracion (no llamar getDuration cada frame)
- Medio del video: checa cada 500ms
- Cerca del inicio/final: sube a 30ms para fade suave

### Errores comunes y causas
IllegalStateException: null: setSurface/start en estado invalido
Error -38: start() sin Surface o antes de prepare
Error 1/-22: Video demasiado grande para el codec
setVideoSurfaceTexture -22: Surface destruido o no creado
Decoder init failed c2.mtk: Codec MediaTek agotado
Finalized without released: Leak — siempre llamar release()

### Lecciones aprendidas
- Dejar que Android maneje el ciclo de vida — no forzar releases
- Codigo simple = menos fallas. GC spam y retry loops no resuelven, empeoran
- Probar en dispositivos budget desde el inicio
- Videos pequenos = mas compatibles
- Pre-procesar en servidor, no en dispositivo
- Android Picker hace mas de lo que parece
- MediaPlayer > ExoPlayer para WallpaperService
- Cachear valores constantes (duracion, typefaces, gradients)
- 1fps idle + activacion por touch = 0% CPU

### Surface Producer Conflict (Canvas vs MediaPlayer)
Un Surface en WallpaperService solo acepta UN productor a la vez: Canvas (CPU via lockCanvas) O MediaPlayer (hardware via setSurface). Una vez que Canvas tomo el Surface, MediaPlayer.setSurface() falla con setVideoSurfaceTexture -22 (EINVAL). unlockCanvasAndPost() NO libera la asociacion del productor.
Sintoma: tras instalar un wallpaper de imagen, Explore mode, o cualquier modo con overlays canvas, el siguiente video falla con -22 y IllegalStateException. Era intermitente porque dependia de si el fadeRunnable o drawRunnable habian tocado el Surface.
Fix definitivo (v1.5.3):
1. AndroidManifest: android:process=":wallpaper" en PixoraWallpaperService (servicio en proceso aislado del main app).
2. MainActivity.setLiveWallpaper(): killWallpaperProcess() antes de lanzar el picker. Android respawnea el servicio con Engine fresco y Surface limpio.
3. Usar prefs.commit() (no apply()) para flush sincronico cross-process antes de matar.
4. Eliminado fadeRunnable que dibujaba un overlay Canvas sobre el video — era el peor poisoner del Surface. Para fade en loops, bakearlo con ffmpeg: ffmpeg -i in.mp4 -vf "fade=in:0:12,fade=out:st=4.5:d=12" out.mp4
5. releaseMediaPlayerSafely() helper que limpia los 7 listeners antes de release (evita warning mediaplayer went away with unhandled events).
Lo que NO funciona:
• holder.setFormat() — no fuerza recreacion del Surface
• System.gc() — cero efecto en codecs nativos
• setSurface(null) — no libera la asociacion del productor
• ACTION_CHANGE_LIVE_WALLPAPER picker solo — Android REUSA el mismo Engine si es el mismo servicio
• Botones manuales de Reset Engine / Clear Cache — eliminados de Settings

### v1.5.3 (codigo 19) — 2026-04-05
• Fix definitivo del Surface producer conflict (Canvas vs MediaPlayer)
• PixoraWallpaperService aislado en proceso :wallpaper
• Eliminado fadeRunnable (causaba corrupcion del Surface)
• Helper releaseMediaPlayerSafely para limpiar listeners
• Eliminados botones Reset Engine y Clear Cache de Settings (no servian)
• Compatibilidad mejorada con MediaTek (Samsung A15)

### v1.5.3 (codigo 19) — 2026-04-07 (actualizacion)
Cambios de UI:
• Renombrado tab HOT -> LIVE (icono play en lugar de fuego)
• Titulo de la seccion ahora muestra LIVE
Contenido nuevo agregado:
Live wallpapers (videos) — catalogo v3, 49 totales:
• Quantum Atom (SCIFI, glow #00E5FF) — atomo cuantico con orbitales 3D y nucleo pulsante
• Mai Shiranui Win Pose (GAMING, glow #FF4500) — KOF victory pose con fuego
• Mai Shiranui Neon Halo (GAMING, glow #00BFFF) — halo neon cyber arena
• Bumblebee Last Stand (HEROES, glow #FFD600) — Autobot defendiendo ciudad destruida
• Decepticon Storm (HEROES, glow #9D00FF) — nave Decepticon con vortice morado
Wallpapers estaticos — catalogo v17, 168 totales:
• Mai Shiranui Win Pose (GAMING, featured)
• Mai Shiranui Neon Halo (GAMING, featured)
• Bumblebee Last Stand (GAMING, featured)
• Decepticon Storm (GAMING, featured)
Pipeline de procesamiento:
• Videos Auto Play: 486x720 max, 24fps, H.264 high, CRF 20-24, sin audio, <2.5MB
• Videos Explore: 540 wide, baseline profile, keyframe cada frame para extraccion
• Frames pre-extraidos: 36 JPG q3 a 540 wide, 6fps, almacenados en frames/{slug}/
• Previews WebP: 540x540 cuadrado center crop, quality 50-60, <50KB
• Imagenes estaticas: 1080 wide WebP quality 85, preview 540 wide quality 60
• Upload via scripts Python (upload_batch_5.py, upload_static_4.py) con service role key

## 14. Seccion AURA - Wellness & Sonidos
Modulo nuevo planeado el 2026-04-07 que abre una vertical de wellness/sonido dentro de Pixora. Encaja con la mision ("personalizacion accesible, divertida y unica") y es un diferenciador fuerte: ningun competidor (incluyendo Zedge) ofrece la combinacion frecuencias sanadoras + sonidos de naturaleza + reproductor profesional con sleep timer dentro de una app de wallpapers.

### 14.1 Concepto
AURA es un tab nuevo en la barra inferior (icono de loto) con dos categorias separadas (Opcion B):
- Frecuencias: las 9 frecuencias Solfeggio (174, 285, 396, 417, 528, 639, 741, 852, 963 Hz). Generadas localmente con ffmpeg como ondas sinusoidales puras de 15 minutos, fade in/out, normalizadas a -18 LUFS.
- Naturaleza: 15 sonidos ambientales (lluvia, mar, fuego, bosque, viento, etc.) descargados de Freesound.org bajo licencia CC0, mas ruido blanco y marron generados localmente. Procesados a loops limpios de 10 minutos.

### 14.2 Decisiones tomadas
- Nombre del modulo: AURA
- Estructura: Opcion B - frecuencias y naturaleza son listas separadas, no experiencias combinadas
- Idioma: bilingue ES/EN (titulos y descripciones)
- Reproductor: in-app, full-screen, con play/pause/stop/loop/seek/sleep timer
- Sleep timer: incluido en el MVP - opciones de 5/10/15/20/30/45/60/90 minutos con fade-out
- Background: la app sigue sonando con la app cerrada (foreground service + notificacion con controles)
- Streaming desde Supabase Storage (igual que los videos)
- Bucket nuevo: aura-audio (publico)
- Tabla nueva: public.aura_tracks (con descripciones bilingues, chakra, color, duracion, URL)
- Monetizacion: mismo modelo que wallpapers - ads alternados (instala uno - ad, instala otro - sin ad), cada accion otorga puntos diamantes via CreditService.earnFromAd()
- Descargar para offline: tambien aplica las reglas de ads + diamantes
- Tab posicionado despues de LIVE en el bottom nav
- Icono del tab: loto (Icons.spa)

### 14.3 Frecuencias Solfeggio - tabla resumen
Hz
Nombre
Tradicion
Chakra
174 Hz
Foundation / Fundacion
Sensacion de seguridad, alivio del dolor
-
285 Hz
Quantum / Cuantica
Regeneracion celular, recuperacion
-
396 Hz
Liberation / Liberacion
Liberar miedo y culpa
Raiz (Muladhara)
417 Hz
Transmutation / Transmutacion
Facilitar el cambio
Sacro (Svadhisthana)
528 Hz
Miracle / Milagro
Frecuencia del amor, paz interior
Plexo solar (Manipura)
639 Hz
Connection / Conexion
Armonia en relaciones
Corazon (Anahata)
741 Hz
Expression / Expresion
Auto-expresion, intuicion
Garganta (Vishuddha)
852 Hz
Intuition / Intuicion
Despertar de la intuicion
Tercer ojo (Ajna)
963 Hz
Divine / Divina
Despertar espiritual, unidad
Corona (Sahasrara)

### 14.4 Catalogo de Naturaleza (15 tracks)
- Lluvia Suave / Soft Rain
- Lluvia y Truenos / Rain & Thunder
- Olas del Mar / Ocean Waves
- Rio / River Stream
- Cascada / Waterfall
- Chimenea / Fireplace
- Bosque y Pajaros / Forest Birds
- Viento en Arboles / Wind in Trees
- Tormenta Lejana / Distant Storm
- Grillos Nocturnos / Night Crickets
- Cafeteria / Coffee Shop
- Ruido Blanco / White Noise (generado)
- Ruido Marron / Brown Noise (generado)
- Cuenco Tibetano / Tibetan Bowl
- Campanas de Viento / Wind Chimes

### 14.5 Postura editorial sobre las frecuencias
Decision: las descripciones se presentan como herencia tradicional/espiritual, sin afirmaciones medicas. Lenguaje del tipo "tradicionalmente asociada con", "popular en practicas de meditacion". Esto respeta la tradicion, es honesto con el usuario, y evita problemas con politicas de Google Play sobre afirmaciones medicas no respaldadas.

### 14.6 Stack tecnico
- Generacion de frecuencias: ffmpeg (sine + afade + loudnorm)
- Descarga de naturaleza: API de Freesound v2 (filtro CC0, rating_desc)
- Procesamiento: ffmpeg con silenceremove + aloop + atrim + loudnorm
- Storage: Supabase bucket 'aura-audio' publico
- Catalogo: tabla public.aura_tracks accedida via supabase_flutter
- Reproductor: just_audio + just_audio_background (NUEVO en deps)
- Background: foreground service mediaPlayback en AndroidManifest
- Ads: AdService.instance.showInterstitialAd (ya existente)
- Diamantes: CreditService.instance.earnFromAd (ya existente, automatico via AdService)

### 14.7 Plan de implementacion
El trabajo esta dividido en 2 planes formales en docs/superpowers/plans/:
- 2026-04-07-aura-content-pipeline.md - 8 tareas. Genera, descarga y sube todo el contenido. Termina con 24 tracks en Supabase.
- 2026-04-07-aura-app-integration.md - 15 tareas. Crea el feature module en lib/features/aura/, el reproductor, integra el tab, ads y diamantes. Termina con AURA funcional en el dispositivo.
Los planes son independientes (Plan 2 consume el output de Plan 1). Se pueden ejecutar en paralelo si dos personas trabajan, o secuencialmente.

### 14.8 Credenciales relacionadas
Freesound API: client ID y key guardadas en KEYS_LOCAL.md (gitignored). Marcadas para regenerar despues del MVP por haberse expuesto en una conversacion.
Supabase service role key: requerida para subir audios via tools/aura/upload_supabase.py. Se pasa como variable de entorno SUPABASE_SERVICE_ROLE_KEY, nunca commitear.

### 14.9 Notas pendientes para versiones futuras
- Fase 2: binaural beats (con audifonos) e isochronic tones
- Fase 2: experiencias combinadas (frecuencia + sonido de naturaleza + wallpaper de chakra sincronizados)
- Fase 2: meditaciones guiadas con voz
- Fase 2: integracion con el sistema de creditos para 'descargas premium' (ahora estan gratis con ads)
- Verificar el modulo HOT en este documento -> ya fue renombrado a LIVE en commit 204da6a, actualizar referencias en secciones 7 y 9

#### 14.8.1 Freesound API - credenciales
Cuenta: eduardo javier contreras roman. Client ID y API Key: <REDACTED — ver KEYS_LOCAL.md>. Estado: expuesta en chat el 2026-04-07 — regenerar despues del MVP de AURA.

### 14.10 Estado de implementacion (2026-04-08)
Plan 1 - Content Pipeline: COMPLETADO
- 9 frecuencias Solfeggio generadas con ffmpeg (15 min c/u, loudness -18 LUFS)
- 13 sonidos de naturaleza descargados de Freesound CC0 via API
- 2 ruidos sinteticos (white + brown) generados localmente
- Bucket Supabase aura-audio creado (publico)
- Tabla public.aura_tracks creada con 24 filas (9 frecuencias + 15 nature)
- Scripts en tools/aura/: gen_frequencies.sh, gen_noise.sh, freesound_fetch.py, process_nature.py, upload_supabase.py, supabase_schema.sql
- Tag git: aura-content-v1
Plan 2 - App Integration: COMPLETADO
- Dependencias agregadas: just_audio_background ^0.0.1-beta.13, audio_session ^0.1.21
- AndroidManifest: permisos (WAKE_LOCK, FOREGROUND_SERVICE_MEDIA_PLAYBACK, POST_NOTIFICATIONS) + AudioService + MediaButtonReceiver
- Drawable ic_aura_notification.xml (icono de loto para la notificacion)
- main.dart: JustAudioBackground.init + AuraPlayerService.init
- Feature module lib/features/aura/ con: model, repository (Supabase), AuraPlayerService (singleton con sleep timer), AuraDownloadService, providers Riverpod, AuraTrackCard, SleepTimerSheet, AuraPage (segmentado Frecuencias/Naturaleza), AuraPlayerPage (full-screen)
- Tab AURA insertado en home_page.dart despues de LIVE con icono Icons.spa (loto)
- Helper bilingue lib/core/utils/locale_helper.dart (lee Platform.localeName)
- Sleep timer: 5/10/15/20/30/45/60/90 min con fade-out gradual
- Background playback: foreground service + notificacion con controles (sigue sonando con app cerrada)
- Monetizacion: AdService.showInterstitialAd (ads alternados) en open de track + en download offline. Diamantes via CreditService.earnFromAd (ya automatico)
- Descripciones bilingues ES/EN cargadas desde aura_tracks
- flutter analyze: 0 issues
- flutter build apk --debug: OK (build/app/outputs/flutter-apk/app-debug.apk)
- APK debug instalado en Samsung RF8X903KZ3K para pruebas reales
- 13 commits feat(aura) en branch play-store-estable, pusheados a origin

### 14.11 Pendientes para manana
- Probar AURA en el Samsung de Eduardo: verificar background playback al cerrar app, sleep timer real, descarga offline, ads alternados
- Recolectar feedback del usuario despues de la prueba real (audio loops sin click, volumen entre frecuencias y naturaleza, calidad subjetiva de los CC0)
- Ajustar descripciones de frecuencias si suenan poco naturales en espanol
- Validar que la notificacion media controls aparece bien en Samsung One UI
- Considerar si AURA debe llevar badge NEW en el tab durante la primera semana
- Escribir copy de release notes para Play Store mencionando AURA
- Generar 2-3 screenshots de AURA para Play Store
- Verificar que el ad de open de track no se dispara dos veces (alternancia correcta)
- Despues del MVP: regenerar la API key de Freesound (esta expuesta en chat)
- Considerar agregar mas sonidos CC0 si la lista actual se siente corta
- Fase 2: experiencias combinadas (frecuencia + naturaleza + wallpaper de chakra sincronizados)
- Fase 2: binaural beats e isochronic tones con audifonos
- Fase 2: meditaciones guiadas con voz

### 14.12 Como retomar manana
Branch: play-store-estable. Comando rapido para volver al estado de hoy: git checkout play-store-estable && git pull && flutter pub get
Lee este documento (seccion 14 completa), los planes en docs/superpowers/plans/ y los ultimos 13 commits con git log --oneline aura-content-v1..HEAD para ver todo el trabajo de hoy. Las credenciales de Freesound y Supabase service role estan en KEYS_LOCAL.md (gitignored) y tambien aqui en la seccion 14.8.