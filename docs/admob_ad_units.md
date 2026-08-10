# Pixora IA — AdMob IDs

AdMob account/app: **"Fondos de pantalla - Pixora IA"** · publisher `pub-6734758230109098`.

> These are ad UNIT ids — not secrets (they ship inside the APK). Kept here for
> reference. The master switch `AdService.useProductionAds` flips test↔prod.

## App ID (AndroidManifest.xml → `com.google.android.gms.ads.APPLICATION_ID`)
```
ca-app-pub-6734758230109098~6032512419
```

## Ad units

| Format | Name | Ad unit id | Wired in |
|---|---|---|---|
| App Open | Pixora_AppOpen | `ca-app-pub-6734758230109098/4300023419` | `lib/core/services/app_open_ad_service.dart` (`_prodAppOpenId`) |
| Interstitial | Pixora_Interstitial_ApplyWallpaper | `ca-app-pub-6734758230109098/6687118537` | `lib/core/services/ad_service.dart` (`_prodInterstitialId`) |
| Native | Pixora_Native_Carrusel | `ca-app-pub-6734758230109098/9644077378` | `lib/core/services/native_ad_service.dart` (`_prodAdUnitIdAndroid`) |
| Banner | Pixora_Banner_WallpaperViewer | `ca-app-pub-6734758230109098/2960762292` | `lib/features/wallpapers/presentation/pages/wallpaper_viewer_hud_page.dart` (`_prodBannerAdUnitId`) |

## Google TEST unit ids (used in debug / before a prod unit exists)
- App Open: `ca-app-pub-3940256099942544/9257395921`
- Interstitial: `ca-app-pub-3940256099942544/1033173712`

## Notes
- **eCPM real (jul 2026):** interstitial ~$3 no — real blended eCPM ≈ MXN 27.41 (see master doc / `ad_network_rates`). AdMob is the source of truth for revenue.
- Test devices (Samsung `RF8X903KZ3K`, Huawei `VNS-L53`) are registered in
  `AdService._testDeviceIds` so they always get TEST impressions — never
  self-click a production unit (account was suspended once for this).
- App Open ad created 2026-08-10; ships in v1.7.77.
