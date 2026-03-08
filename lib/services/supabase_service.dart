import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_env.dart';

class SupabaseService {
  static Future<void> init(AppEnv env) async {
    if (!env.hasSupabaseConfig) {
      debugPrint('[Pixora] Supabase env vars not found, skipping init');
      return;
    }

    await Supabase.initialize(
      url: env.supabaseUrl,
      anonKey: env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );

    debugPrint('[Pixora] Supabase initialized');
  }
}

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
});
