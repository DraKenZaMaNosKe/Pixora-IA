# PixoraIA

App de wallpapers animados (live wallpapers) para Android e iOS impulsada por Supabase y modelos generativos (Gemini / Grok).

## Estado actual

- Proyecto Flutter base inicializado (`flutter create --project-name pixoraia .`).
- Arquitectura con Riverpod, Supabase y servicios para futuros módulos.
- Pantalla de galería que consume un repositorio (mock o Supabase) y muestra tarjetas animadas con `video_player`/`lottie`.
- Configuración flexible mediante `.env` y `AppEnv`.

## Configuración rápida

```bash
flutter pub get
cp .env.example .env # edita las llaves reales
```

Completa `.env` con:

```
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
WALLPAPER_BUCKET=wallpapers
GEMINI_API_KEY=...
GROK_API_KEY=...
```

### Supabase

1. Crea un proyecto y un bucket público `wallpapers` (o el nombre que definas en `WALLPAPER_BUCKET`).
2. Tablas recomendadas (simplificadas):
   - `wallpapers`: id, title, preview_url, source_url, asset_type, tags (array), duration_seconds, is_premium, created_at.
   - `downloads`: user_id, wallpaper_id, platform, created_at.
3. Configura políticas RLS para permitir lectura pública de wallpapers y acceso autenticado al bucket.

### Lanza la app

- Android Studio / VS Code: `flutter run` (elige emulador o dispositivo real).
- iOS: requiere Xcode en macOS. Puedes usar MacStadium/MacInCloud o un runner CI (Codemagic, Bitrise) si trabajas desde Windows.

## Arquitectura

```
lib/
├─ core/
│  ├─ config/ (AppEnv)
│  └─ theme/
├─ services/ (SupabaseService, futuros AI clients)
├─ features/
│  └─ gallery/
│     ├─ data/ (models, repositories, mock data)
│     ├─ providers/
│     └─ presentation/
```

- `wallpaper_repository.dart` ya incluye una implementación mock y un stub para Supabase.
- `wallpaper_card.dart` demuestra cómo reproducir videos/lotties en loop.

## Próximos pasos sugeridos

1. **Conectar Supabase real**: poblar tabla `wallpapers` y ajustar `SupabaseWallpaperRepository` para mapear los campos reales.
2. **Módulo de generación**: endpoint (Supabase Edge Function o Cloud Run) que use Gemini/Grok para crear clips y subirlos al bucket.
3. **Descargas y aplicado**: integrar `WallpaperManager` (Android) y guías para iOS (export video + instructions / shortcuts).
4. **Cuenta/planes premium**: autenticar usuarios, favoritos, compras in-app.
5. **Pipeline CI**: configurar Codemagic/Bitrise para builds automáticos Android/iOS.

¡Happy building! 💎
