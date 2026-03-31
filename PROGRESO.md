# Progreso Pixora IA - Sesiones 27-30 Marzo 2026

## Rama de trabajo
`fix/stories-panoramic-subtitles` (basada en `play-store-estable`)

## Versión actual
**1.4.0+13** — AAB listo para subir a Play Console

## Signing Key (Release)
- **Keystore**: `android/pixora-release-key.jks`
- **Alias**: `pixora`
- **Config**: `android/key.properties`
- Ver `KEYS_LOCAL.md` para passwords y SHA-1 (NO commitear)

## Build commands
```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# Release AAB (Play Store)
flutter build appbundle --release

# Install on Samsung A155M
adb -s RF8X903KZ3K install -r build/app/outputs/flutter-apk/app-release.apk

# Install on Samsung A20
adb -s R58MA30MN5T install -r build/app/outputs/flutter-apk/app-release.apk
```

## Notas importantes
- **Flutter**: 3.19.3 (NO actualizar sin verificar compatibilidad)
- **win32 override**: debe ser 5.5.0 (5.7.1 no compatible con Dart 3.3)
- **CardTheme**: usar `CardTheme()` no `CardThemeData()` (Flutter 3.19)
- **NDK warning**: ignorar, no afecta el build
- **AAB pendiente de subir**: `build/app/outputs/bundle/release/app-release.aab`

## Dispositivos de prueba
- **Samsung SM-A155M** (Android 16, API 36) — ID: `RF8X903KZ3K`
- **Samsung SM-A205U** (Android 10) — ID: `R58MA30MN5T`
- **Huawei VNS-L53** (Android 7.0, API 24) — ID: `G2R4C17516000149`

## Features implementadas
1. Netflix UI (hero banner, carruseles, shimmer)
2. Búsqueda funcional (nombre, categoría, tags)
3. Day Cycle (wallpapers por hora del día)
4. Google Sign-In + favoritos sincronizados
5. Splash screen con efectos de partículas
6. Descargas robustas (progress %, retry 3x, cache 500MB)
7. Image Quality setting (HD/Auto/LQ)
8. Ringtones: 6 packs, 72 tonos, preview con just_audio, auto-install
9. Refactor WallpaperService → 7 módulos
10. 20 unit tests
11. App icon P centrada + nombre "Wallpaper PixoraIA"

## Pendiente
- [ ] Subir AAB 1.4.0 a Play Console (prueba cerrada)
- [ ] Promover de prueba cerrada a producción
- [ ] Generar más wallpapers (Halo, Supersónicos, Marte, etc.)
- [ ] Más packs de ringtones
- [ ] Escalar Supabase: migrar de JSON a tabla DB con paginación
