import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_config.dart';
import 'core/services/ad_service.dart';
import 'core/services/analytics_service.dart';
import 'core/services/app_strings_service.dart';
import 'core/services/catalog_service.dart';
import 'core/services/credit_service.dart';
import 'core/services/grace_pass_service.dart';
import 'core/services/legal_service.dart';
import 'core/services/live_wallpaper_catalog_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/subscription_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/wallpaper_engine_coordinator.dart';
import 'features/aura/services/aura_player_service.dart';
import 'core/services/wallpaper_stats_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/presentation/splash_page.dart';

/// Global navigator key kept around in case a future flow needs it.
/// The ad-overlay path no longer uses it — see [adShowingNotifier] below.
final GlobalKey<NavigatorState> pixoraNavigatorKey =
    GlobalKey<NavigatorState>();

/// Toggled by AdService.showInterstitialAd around the AdMob show. While
/// `true`, PixoraApp swaps its entire content for a black ColoredBox —
/// every widget below MaterialApp is unmounted, releasing GPU memory and
/// stopping Flutter's frame loop on the catalog UI. AdMob's translucent
/// AdActivity sits on top so users only ever see the ad. This is the
/// thing that actually fixes ads stuttering on memory-pressed Samsung
/// devices (Navigator.push didn't work — push doesn't unmount, it stacks
/// the new route on top of the heavy catalog tree which keeps rendering
/// at 13 fps because the previous route is still mounted in the
/// Navigator's element tree).
final ValueNotifier<bool> adShowingNotifier = ValueNotifier<bool>(false);

Future<void> main() async {
  // Catch all uncaught Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[Pixora] FlutterError: ${details.exception}');
  };

  // Catch all uncaught async errors
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Memory: cap Flutter's in-memory image cache so 4K wallpapers don't
    // balloon RAM on mid-range devices (Samsung A15 / MediaTek chips crash
    // around 100 MB of bitmap cache). 100 images × ~0.5 MB each ≈ 50 MB max.
    PaintingBinding.instance.imageCache.maximumSize = 50;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;

    // Skia GPU resource cache cap. This is the BIG one — Skia keeps an
    // internal cache of GPU textures, framebuffers and compiled shaders
    // that grows unbounded as the user navigates through the app. By
    // 2026-05-08, dumpsys meminfo on Pixora was showing 442 MB in
    // GL mtrack alone, dwarfing Java/Native heaps and bottlenecking the
    // playable AdMob ads (they need GPU memory to render their interactive
    // mini-game). Capping at 64 MB keeps the cache useful for animation
    // smoothness without hogging memory needed by other windows (ads,
    // wallpaper service, etc).
    //
    // IMPORTANT: must call this AFTER the first frame because the engine's
    // shell isn't ready before runApp(). Calling here in main() pre-engine
    // silently drops the message. Wired up in the addPostFrameCallback
    // below in PixoraApp.initState.

    await Hive.initFlutter();

    await Supabase.initialize(
      url: SupabaseConfig.projectUrl,
      anonKey: SupabaseConfig.anonKey,
    );

    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.orbix.pixora.aura.channel.audio',
      androidNotificationChannelName: 'AURA Audio',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    );

    // Configure audio session as ambient — don't steal focus from Spotify/YouTube.
    // AURA sounds play alongside other apps (duck softly, never pause them).
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.ambient,
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
    ));

    await ThemeService.instance.init();
    await LegalService.instance.init();
    await AnalyticsService.instance.init();
    await CreditService.instance.init();
    await GracePassService.instance.init();
    await AuraPlayerService.instance.init();
    // FCM push notifications — fire-and-forget so we don't block app
    // startup if Firebase/network is slow. Topic subscription happens
    // in the background; failures only log debug, never crash UI.
    unawaited(PushNotificationService.instance.init());
    // Text CMS — fetch admin-editable strings from Supabase, cache in Hive.
    // Non-blocking: if it fails, LocaleHelper.fromCms() falls back to
    // hardcoded strings in each widget.
    unawaited(AppStringsService.instance.initialize());
    AdService.instance.initialize();
    // Cold-start optimization — precarga los catálogos desde disco antes
    // de runApp() para que las pantallas Wallpapers/LIVE arranquen con
    // data al instante en vez del skeleton 1-3s. Hacemos ambos en
    // paralelo (~20-40ms total). Si falta la cache (primera instalación)
    // o falla la lectura, los providers de Riverpod muestran el skeleton
    // como siempre — comportamiento normal.
    await Future.wait([
      CatalogService.instance.preloadFromDiskCache(),
      LiveWallpaperCatalogService.instance.preloadFromDiskCache(),
    ]);
    // Sync the wallpaper engine coordinator from native state so we know
    // which rotation engine (AutoRotate / DayCycle / Story) was active
    // before app restart. Fire-and-forget — UI doesn't block on this.
    unawaited(WallpaperEngineCoordinator.instance.syncFromNative());
    // Subscription init doesn't block app start — it queries Play Store and
    // Supabase in parallel. If a user is already signed in, onSignIn will
    // fire again once session hydrates.
    unawaited(SubscriptionService.instance.init());
    runApp(const ProviderScope(child: PixoraApp()));
  }, (error, stackTrace) {
    debugPrint('[Pixora] Uncaught error: $error');
    debugPrint('[Pixora] Stack: $stackTrace');
  });
}

class PixoraApp extends StatefulWidget {
  const PixoraApp({super.key});

  @override
  State<PixoraApp> createState() => _PixoraAppState();
}

class _PixoraAppState extends State<PixoraApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Apply Skia GPU resource cache cap AFTER the first frame so the engine
    // shell is fully initialized. Calling this in main() pre-runApp drops
    // the message silently because the platform channel isn't wired yet.
    // 64 MB is the chosen cap — see comment in main() above for why.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChannels.skia
          .invokeMethod<void>(
        'Skia.setResourceCacheMaxBytes',
        64 * 1024 * 1024,
      )
          .then((_) {
        debugPrint('[Pixora] Skia GPU cache capped at 64 MB');
      }).catchError((Object e) {
        debugPrint('[Pixora] Skia cap error: $e');
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WallpaperStatsService.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      WallpaperStatsService.instance.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Pixora IA',
          navigatorKey: pixoraNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.forHud(ThemeService.instance.currentTheme),
          home: ValueListenableBuilder<bool>(
            valueListenable: adShowingNotifier,
            builder: (context, isAdShowing, child) {
              if (isAdShowing) {
                // Heavy catalog UI is unmounted while the ad runs.
                // GPU memory drops, Flutter idles, AdMob runs smoothly.
                return const ColoredBox(color: Colors.black);
              }
              return child!;
            },
            child: const SplashPage(),
          ),
        );
      },
    );
  }
}
