# Pixora IA

Wallpapers, Ringtones & Icon Packs for Android and iOS.

## Setup

```bash
flutter pub get
flutter run
```

## Architecture

- **Flutter** with Riverpod for state management
- **Supabase Storage** for dynamic catalog (JSON + images)
- **Platform channels** (Kotlin) for Android wallpaper/ringtone APIs
- **Hive** for local favorites storage

## Backend

Catalog is fetched from Supabase Storage as a JSON file — no database tables needed. Images are served directly from public buckets.

## Build

```bash
flutter build apk --release    # Android APK
flutter build appbundle         # Android AAB (Play Store)
flutter build ios               # iOS (requires Mac)
```

## Package

- Android: `com.orbix.pixora`
- iOS: `com.orbix.pixora`
