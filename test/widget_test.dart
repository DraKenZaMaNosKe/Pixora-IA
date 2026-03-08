import 'package:flutter_test/flutter_test.dart';

import 'package:pixoraia/core/config/app_env.dart';

void main() {
  test('AppEnv stores keys correctly', () {
    final env = AppEnv(
      supabaseUrl: 'https://demo.supabase.co',
      supabaseAnonKey: 'anon',
      wallpaperBucket: 'wallpapers',
      geminiKey: 'gemini',
      grokKey: 'grok',
    );

    expect(env.supabaseUrl, contains('supabase'));
    expect(env.hasSupabaseConfig, isTrue);
  });
}
