import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_env.dart';
import 'core/theme/app_theme.dart';
import 'features/gallery/presentation/pages/gallery_page.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', mergeWith: const {});
  final env = AppEnv.fromDotEnv();
  env.dump();
  await SupabaseService.init(env);

  runApp(ProviderScope(overrides: [appEnvProvider.overrideWithValue(env)], child: const PixoraApp()));
}

class PixoraApp extends ConsumerWidget {
  const PixoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'PixoraIA',
      debugShowCheckedModeBanner: false,
      theme: PixoraTheme.light,
      home: const GalleryPage(),
    );
  }
}
