import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppEnv {
  AppEnv({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.wallpaperBucket,
    required this.geminiKey,
    required this.grokKey,
  });

  factory AppEnv.fromDotEnv() {
    return AppEnv(
      supabaseUrl: dotenv.maybeGet('SUPABASE_URL') ?? '',
      supabaseAnonKey: dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '',
      wallpaperBucket: dotenv.maybeGet('WALLPAPER_BUCKET') ?? 'wallpapers',
      geminiKey: dotenv.maybeGet('GEMINI_API_KEY') ?? '',
      grokKey: dotenv.maybeGet('GROK_API_KEY') ?? '',
    );
  }

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String wallpaperBucket;
  final String geminiKey;
  final String grokKey;

  bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  void dump() {
    debugPrint('Pixora Env => Supabase: $hasSupabaseConfig, bucket: $wallpaperBucket');
  }
}

final appEnvProvider = Provider<AppEnv>((ref) => throw UnimplementedError());
