# Progreso Pixora IA - Sesión 27-28 Marzo 2026

## Rama de trabajo
`fix/stories-panoramic-subtitles` (basada en `play-store-estable`)

## Commits realizados (12)

### 1. Fix Stories: live wallpaper + subtítulos
- Activación inteligente del live wallpaper (no muestra picker si ya está activo)
- Subtítulos aparecen 30 segundos cada 3 minutos con fade-in/fade-out

### 2. Netflix UI + descargas robustas + búsqueda
- Hero banner con wallpapers featured, auto-rota cada 7 segundos
- Carruseles horizontales: Trending, New, por categoría
- Shimmer loading placeholders
- AppBar transparente sobre hero banner
- DownloadService: streaming con progress %, retry 3x con backoff, cache 500MB
- Progress bar con porcentaje al descargar wallpaper
- Búsqueda funcional: filtra por nombre, descripción, categoría y tags

### 3. Day Cycle
- Wallpapers cambian automáticamente según hora del día (mañana/tarde/atardecer/noche)
- DayCycleWorker checa cada 15 min via WorkManager
- Usa live wallpaper para soporte panorámico
- Tab nuevo en bottom nav
- Catálogo desde Supabase con cache 6hrs

### 4. Refactor PixoraWallpaperService
- 1615 líneas → 7 archivos modulares:
  - ClockRenderer, EqualizerRenderer, RainEffectRenderer
  - BatteryIndicator, SystemRingsRenderer, CaptionOverlay
  - PixoraWallpaperService (orquestador ~340 líneas)

### 5. Tests + modelo mejorado
- 20 unit tests: Wallpaper, DayCycleTheme, Story, StoryFrame, SupabaseConfig
- Modelo Wallpaper: campos tags, downloadCount, createdAt
- Trending ordena por downloadCount real
- New detecta wallpapers de últimos 14 días

### 6. Catálogo Supabase actualizado
- 146 wallpapers con tags, downloadCount, createdAt
- Featured: Akuma, Scorpion vs Sub-Zero, Vegeta Ultra Ego, Kratos, etc.
- Badge NEW solo en los 6 más recientes
- Versión 15 del catálogo subida a Supabase Storage

### 7. Google Sign-In + avatar
- Login con Google via Supabase Auth (opcional, app funciona sin cuenta)
- Avatar en AppBar (arriba izquierda, estilo Netflix)
- Favoritos sincronizados con Supabase (merge local + cloud)
- Historial de descargas en Supabase
- Perfil en Settings con nombre, email, avatar, badge "Synced"
- Tablas creadas: user_favorites, user_downloads (con RLS)

### 8. Splash screen épico
- CustomPainter con partículas flotantes, anillos de energía, nebulosa
- Logo "P" con gradiente animado morado/cyan
- Precarga catálogo durante splash (mínimo 3 segundos)
- Splash nativo Android cambiado a negro (no más flash blanco)

### 9. App icon + nombre
- Icono: letra P centrada con gradiente cyan sobre fondo oscuro
- Nombre: "Wallpaper PixoraIA" en home screen
- Iconos adaptivos para todas las densidades Android

### 10. Fix seguridad y error handling
- Cleartext traffic deshabilitado (HTTPS only)
- Error handlers en Image.network faltantes
- Favorites sync con error catching
- Logging en silent catches

### 11. Image Quality setting
- Selector en Settings: Auto, HD, Low Quality
- HD descarga imagen full al aplicar wallpaper
- LQ descarga preview ligero (ahorra datos)
- Persistido en Hive

### 12. Version bump + AAB release
- Versión 1.2.0+10
- AAB firmado con pixora-release-key.jks
- Listo para subir a Play Console

## Estado de Play Console
- App: Pixora IA (com.orbix.pixora)
- Track: Prueba cerrada
- Versión anterior: 6 (1.1.0)
- Nueva versión: 10 (1.2.0) — AAB generado, pendiente de subir
- Se cambió la clave de firma (Google administra ahora)

## Configuraciones externas
- **Supabase**: proyecto vzuwvsmlyigjtsearxym (IntraPC Solutions)
  - Auth: Google provider habilitado
  - Tablas: user_favorites, user_downloads (con RLS)
  - Storage: dynamic_catalog.json v15 actualizado
- **Google Cloud Console**: OAuth client creado para com.orbix.pixora
  - Android client: 615188090674-rlbnvmclfqm46b36i5qlrqe50ordvgbl
  - Web client: 615188090674-057ja5g8m8sennvr4d5qkkgj1r85m9ul
- **Keystore**: android/pixora-release-key.jks (alias: pixora, pass: pixora2026)

## Pendientes

### Inmediatos
- [ ] Subir AAB 1.2.0 a Play Console (prueba cerrada)
- [ ] Generar tonos/ringtones con Mureka AI
- [ ] Implementar sistema de ringtones en la app

### Próximos features
- [ ] Ringtones: catálogo, preview, auto-install como ringtone/notificación/alarma
- [ ] Packs temáticos (wallpaper + ringtone combinados)
- [ ] Shimmer en más lugares (Stories, Day Cycle)
- [ ] Escalar Supabase: migrar de JSON estático a tabla DB con paginación
- [ ] Subir imágenes nuevas generadas en Gemini (Halo, Supersónicos, Marte, etc.)

### Prompts de imágenes pendientes (4128x1024)
1. Halo - Master Chief épica
2. Los Supersónicos
3. Marte panorámica
4. Agujero negro panorámica
5. Agujero negro vista normal
6. Ren & Stimpy
7. Halo - Batalla espacial
8. Master Chief solo
9. Los Supersónicos - Orbit City nocturna
10. Marte - Base humana

### Prompts de ringtones (Mureka AI)
- Mario Bros Pack: coin, star power, level complete, power up, game over
- Dragon Ball Pack: power up, kamehameha, super saiyan
- Cyberpunk Pack: notification beep, neon city ringtone, hacking alert
- Horror Pack: creepy music box, jump scare

## Archivos clave
- `lib/main.dart` — entry point con Supabase init
- `lib/core/services/auth_service.dart` — Google Sign-In + sync
- `lib/core/services/quality_service.dart` — HD/LQ setting
- `lib/core/services/download_service.dart` — descargas con retry/progress
- `lib/features/splash/presentation/splash_page.dart` — splash con shaders
- `lib/features/wallpapers/presentation/widgets/hero_banner.dart` — Netflix hero
- `lib/features/wallpapers/presentation/widgets/wallpaper_carousel_row.dart` — carruseles
- `lib/features/day_cycle/` — feature completo Day Cycle
- `android/app/src/main/kotlin/com/orbix/pixora/renderers/` — 6 renderers modulares
- `android/key.properties` — signing config (NO commitear)
- `android/pixora-release-key.jks` — keystore release (NO commitear)
