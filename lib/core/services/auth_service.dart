import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'credit_service.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Current user (null if not logged in).
  User? get currentUser => _client.auth.currentUser;

  /// Whether the user is logged in.
  bool get isLoggedIn => currentUser != null;

  /// User display name.
  String? get displayName => currentUser?.userMetadata?['full_name'] as String?;

  /// User email.
  String? get email => currentUser?.email;

  /// User avatar URL.
  String? get avatarUrl => currentUser?.userMetadata?['avatar_url'] as String?;

  /// Listen to auth state changes.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Sign in with Google.
  Future<bool> signInWithGoogle() async {
    try {
      const webClientId =
          '615188090674-057ja5g8m8sennvr4d5qkkgj1r85m9ul.apps.googleusercontent.com';

      final googleSignIn = GoogleSignIn(serverClientId: webClientId);
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        debugPrint('[Auth] Google sign-in cancelled');
        return false;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        debugPrint('[Auth] No ID token from Google');
        return false;
      }

      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      debugPrint('[Auth] Signed in: ${response.user?.email}');
      if (response.user != null) {
        // Record session + sync local diamonds. Both run independently and
        // don't block the sign-in UX — errors are logged but don't reject.
        unawaited(_logSessionAndSyncCredits());
      }
      return response.user != null;
    } catch (e) {
      debugPrint('[Auth] Google sign-in failed: $e');
      return false;
    }
  }

  /// Fire-and-forget: record a session row and merge any local diamond
  /// earnings into the server account.
  Future<void> _logSessionAndSyncCredits() async {
    try {
      final info = await _collectDeviceInfo();
      await _client.rpc('log_session', params: {
        'p_app_version': info['app_version'],
        'p_device_model': info['device_model'],
        'p_android_version': info['android_version'],
        'p_locale': Platform.localeName,
      });
      debugPrint('[Auth] Session logged');
    } catch (e) {
      debugPrint('[Auth] log_session failed: $e');
    }
    // Sync diamonds regardless of whether log_session succeeded.
    try {
      await CreditService.instance.syncAfterLogin();
    } catch (e) {
      debugPrint('[Auth] CreditService.syncAfterLogin failed: $e');
    }
  }

  Future<Map<String, String?>> _collectDeviceInfo() async {
    final out = <String, String?>{
      'app_version': null,
      'device_model': null,
      'android_version': null,
    };
    try {
      final pkg = await PackageInfo.fromPlatform();
      out['app_version'] = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        out['device_model'] = info.model;
        out['android_version'] = info.version.release;
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        out['device_model'] = info.utsname.machine;
        out['android_version'] = info.systemVersion;
      }
    } catch (_) {}
    return out;
  }

  /// Sign out.
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
      await _client.auth.signOut();
      await CreditService.instance.onSignOut();
      debugPrint('[Auth] Signed out');
    } catch (e) {
      debugPrint('[Auth] Sign out failed: $e');
    }
  }

  /// Sync local favorites to Supabase (merge: upload local, download remote).
  Future<Set<String>> syncFavorites(Set<String> localFavorites) async {
    if (!isLoggedIn) return localFavorites;

    try {
      final userId = currentUser?.id ?? '';

      // Get remote favorites
      final response = await _client
          .from('user_favorites')
          .select('wallpaper_id')
          .eq('user_id', userId);

      final remoteFavs = <String>{};
      if (response is List) {
        for (final r in response) {
          if (r is Map) {
            final id = r['wallpaper_id'] as String?;
            if (id != null) remoteFavs.add(id);
          }
        }
      }

      // Merge: union of local + remote
      final merged = {...localFavorites, ...remoteFavs};

      // Upload any that are only local
      final onlyLocal = localFavorites.difference(remoteFavs);
      for (final id in onlyLocal) {
        await _client.from('user_favorites').upsert({
          'user_id': userId,
          'wallpaper_id': id,
        });
      }

      debugPrint(
          '[Auth] Favorites synced: ${merged.length} total (${onlyLocal.length} uploaded)');
      return merged;
    } catch (e) {
      debugPrint('[Auth] Favorites sync failed: $e');
      return localFavorites;
    }
  }

  /// Add a favorite to Supabase.
  Future<void> addFavoriteRemote(String wallpaperId) async {
    if (!isLoggedIn) return;
    try {
      await _client.from('user_favorites').upsert({
        'user_id': currentUser?.id ?? '',
        'wallpaper_id': wallpaperId,
      });
    } catch (e) {
      debugPrint('[Auth] Add favorite remote failed: $e');
    }
  }

  /// Remove a favorite from Supabase.
  Future<void> removeFavoriteRemote(String wallpaperId) async {
    if (!isLoggedIn) return;
    try {
      await _client
          .from('user_favorites')
          .delete()
          .eq('user_id', currentUser?.id ?? '')
          .eq('wallpaper_id', wallpaperId);
    } catch (e) {
      debugPrint('[Auth] Remove favorite remote failed: $e');
    }
  }

  /// Record a download in history.
  Future<void> recordDownload(String wallpaperId) async {
    if (!isLoggedIn) return;
    try {
      await _client.from('user_downloads').insert({
        'user_id': currentUser?.id ?? '',
        'wallpaper_id': wallpaperId,
      });
    } catch (e) {
      debugPrint('[Auth] Record download failed: $e');
    }
  }

  /// Get download history.
  Future<List<String>> getDownloadHistory() async {
    if (!isLoggedIn) return [];
    try {
      final response = await _client
          .from('user_downloads')
          .select('wallpaper_id')
          .eq('user_id', currentUser?.id ?? '')
          .order('downloaded_at', ascending: false)
          .limit(100);

      return (response as List)
          .map((r) => (r['wallpaper_id'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[Auth] Get download history failed: $e');
      return [];
    }
  }
}
