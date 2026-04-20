import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_config.dart';
import 'core/services/ad_service.dart';
import 'core/services/credit_service.dart';
import 'core/services/subscription_service.dart';
import 'features/aura/services/aura_player_service.dart';
import 'core/services/wallpaper_stats_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/presentation/splash_page.dart';

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

    await CreditService.instance.init();
    await AuraPlayerService.instance.init();
    AdService.instance.initialize();
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
    return MaterialApp(
      title: 'Pixora IA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashPage(),
    );
  }
}
