# Pixora v2 — Compose Native Android (Plan inicial)

> **Branch**: `pixora-v2-compose` (off `play-store-estable`)
> **Decisión tomada**: 2026-05-23 noche. Migración Flutter → Compose Native Android-only.
> **Razón**: 0 plan de iOS, ~9000 LOC Kotlin nativo ya escrito (wallpaper service, renderers), Flutter overhead innecesario para Android-only.

## Stack confirmado

| Layer | Tech |
|---|---|
| UI | Jetpack Compose Material 3 |
| DI | Hilt |
| State | ViewModel + StateFlow |
| Image | Coil 3 |
| HTTP | Ktor 3 |
| Database local | Room |
| Backend | Supabase (mismo de v1) vía `supabase-kt` |
| Audio/Video | Media3 (ExoPlayer) |
| AdMob | `play-services-ads` 23.x directo |
| IAP | `billing-ktx` v7 directo |
| Push | Firebase Cloud Messaging |
| Min SDK | 26 (Android 8.0) |
| Target SDK | 35 |
| Kotlin | 2.0 + KSP |

## App identity (sin cambios)

- `applicationId`: `com.orbix.pixora` (mismo)
- Signing: misma `pixora-release-key.jks` (en orbixprivate)
- Same Supabase, same Postgres schema, same buckets
- Strategy de release: Internal Testing → Closed → Open → Production cuando feature parity ≥90%

## Estrategia "Single source of truth"

- Branch `play-store-estable` (Flutter v1) → **FREEZE excepto critical bugfixes**
- Branch `pixora-v2-compose` (Compose v2) → desarrollo activo
- Merge a `play-store-estable` (reemplazo) cuando v2 esté lista para producción

## Que se BORRA (Flutter scaffold v1)

```
lib/                          ← TODO Dart code
ios/                          ← iOS scaffolding nunca usado
linux/                        ← desktop scaffolding
macos/                        ← desktop scaffolding
web/                          ← web scaffolding
windows/                      ← desktop scaffolding
pubspec.yaml                  ← Dart dependencies
pubspec.lock
.dart_tool/
analysis_options.yaml         ← Flutter lints
build/                        ← Flutter build outputs
.flutter-plugins-dependencies
.metadata
```

## Que se PRESERVA (lo que portamos)

```
android/                      ← ⭐ JOYA: 9254 LOC Kotlin nativo ya hecho
  app/src/main/kotlin/com/orbix/pixora/
    MainActivity.kt           (reescribir como Compose entry — pero referencias intact)
    PixoraWallpaperService.kt  (intact — core wallpaper engine)
    AutoRotateWorker.kt        (intact)
    DayCycleWorker.kt          (intact)
    StoryWorker.kt             (intact)
    LunarPhaseWorker.kt        (intact)
    gl/GLShaderRenderer.kt     (intact)
    gl/ShaderWallpaperService.kt (intact)
    renderers/*.kt             (12 renderers OpenGL — INTACT)
    scene/*.kt                 (scene system — INTACT)
    touch/*.kt                 (touch trails — INTACT)
android/app/src/main/AndroidManifest.xml  (preservar permissions + services declaration)
android/app/src/main/res/                 (recursos + ic_launcher + splash)
android/app/key.properties                (firmas)
android/app/google-services.json          (Firebase config)
android/app/build.gradle (kts)            (reescribir para Compose)

supabase/migrations/          ← Schema Postgres (no cambia)
tools/                        ← Scripts Python (admin server, FCM push, etc.)
docs/                         ← Documentación
KEYS_LOCAL.md                 ← Secrets (gitignored)
CLAUDE.md                     ← Instrucciones AI assistant
.claude/                      ← Config Claude Code
.gitignore                    ← Adaptar
```

## Estructura nueva del repo (post-borrado)

```
Pixora-IA/                    ← root del repo
├── app/                      ← ⭐ Standalone Android module (era `android/app/`)
│   ├── build.gradle.kts
│   ├── src/main/
│   │   ├── AndroidManifest.xml
│   │   ├── kotlin/com/orbix/pixora/
│   │   │   ├── MainActivity.kt
│   │   │   ├── PixoraApp.kt            ← @HiltAndroidApp entry
│   │   │   ├── navigation/
│   │   │   │   ├── PixoraNavHost.kt
│   │   │   │   ├── NavDestinations.kt
│   │   │   │   └── BottomNav.kt
│   │   │   ├── ui/theme/
│   │   │   │   ├── PixoraColors.kt
│   │   │   │   ├── PixoraTheme.kt
│   │   │   │   └── PixoraTypography.kt
│   │   │   ├── features/                ← 13 features
│   │   │   │   ├── wallpapers/
│   │   │   │   ├── live/
│   │   │   │   ├── threed/
│   │   │   │   ├── cultura/
│   │   │   │   ├── eventos/
│   │   │   │   ├── aura/
│   │   │   │   ├── arcano/
│   │   │   │   ├── stories/
│   │   │   │   ├── daycycle/
│   │   │   │   ├── ringtones/
│   │   │   │   ├── aigenerate/
│   │   │   │   ├── favorites/
│   │   │   │   └── settings/
│   │   │   ├── wallpaper/               ← Native wallpaper engine (portado)
│   │   │   │   ├── PixoraWallpaperService.kt
│   │   │   │   ├── workers/
│   │   │   │   ├── gl/
│   │   │   │   ├── renderers/
│   │   │   │   ├── scene/
│   │   │   │   └── touch/
│   │   │   └── data/                    ← Supabase repos, Room db, etc.
│   │   └── res/                          ← Recursos + ic_launcher
│   └── proguard-rules.pro
├── build.gradle.kts                     ← Root project Gradle
├── settings.gradle.kts
├── gradle/wrapper/
├── gradle.properties
├── gradlew, gradlew.bat
├── supabase/                             ← preservado
├── tools/                                ← preservado
├── docs/                                 ← preservado
├── KEYS_LOCAL.md
├── CLAUDE.md
└── PIXORA_V2_PLAN.md (este archivo)
```

## Day 1 (3-4 hrs) — Goal: APK Compose esqueleto navegable

1. ✅ Crear branch `pixora-v2-compose`
2. ✅ Crear este PIXORA_V2_PLAN.md (estás leyendo esto)
3. ⏳ **OK del usuario para borrar Flutter** ← punto de pausa aquí
4. ⏳ Borrar lib/, ios/, linux/, macos/, web/, windows/, pubspec.*
5. ⏳ Reorganizar android/app/ → root como módulo `app/`
6. ⏳ Setup Gradle nuevo (Compose BOM + stack completo)
7. ⏳ Theme HUD (PixoraColors, PixoraTheme, PixoraTypography)
8. ⏳ MainActivity + PixoraApp (@HiltAndroidApp)
9. ⏳ NavHost + BottomNav + 13 destinos
10. ⏳ 13 shells de features con Material 3 Scaffold + "Coming soon"
11. ⏳ Build APK debug + install Samsung + validar las 13 secciones navegan

## Day 2-5 (próximas sesiones)

- Setup Supabase client + repository pattern por feature
- Migrar WallpapersFeature (catalog + viewer + apply) — primer feature real
- Setup AdService nativo (sin plugin)
- Setup CreditService nativo (Room + Supabase realtime)
- Migrar otros features incrementalmente

## Roadmap a producción (estimado conservador)

| Hito | Estimado |
|---|---|
| Day 1: Esqueleto navegable | 1 día |
| Wallpaper feature funcional (catalog + apply) | 1 semana |
| AURA + Live wallpapers | 2 semanas |
| Stories + Day Cycle + Ringtones | 2 semanas |
| Arcano + Cultura + Eventos + AI Generate | 3 semanas |
| Favorites + Settings + Admin sync | 1 semana |
| Subscriptions + Credits + Ads | 1 semana |
| Testing + parity check vs v1 | 1 semana |
| **TOTAL** | **~11 semanas (3 meses)** |

Más conservador que mis primeras estimaciones (6-9 meses) gracias a portar el wallpaper engine entero.

---

**Estado actual**: este plan documentado. Esperando GO del usuario para borrar Flutter (paso 3-4).
