import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/services/ad_service.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  await Supabase.initialize(
    url: 'https://vzuwvsmlyigjtsearxym.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6dXd2c21seWlnanRzZWFyeHltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg2NDg3MDksImV4cCI6MjA3NDIyNDcwOX0.Fqum-r8H3erP3fLUvzQlLtWivlrp3smAebvI0uDA5uE',
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
      home: const HomePage(),
    );
  }
}
