import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_config.dart';
import 'core/services/ad_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/presentation/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  await Supabase.initialize(
    url: SupabaseConfig.projectUrl,
    anonKey: SupabaseConfig.anonKey,
  );

  AdService.instance.initialize();
  runApp(const ProviderScope(child: PixoraApp()));
}

class PixoraApp extends StatelessWidget {
  const PixoraApp({super.key});

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
