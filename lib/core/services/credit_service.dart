import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Diamonds / credits balance for a user.
///
/// Local Hive box (`pixora_credits`) is the UI-visible cache. Server is the
/// source of truth once the user is logged in. Flow:
///
/// - **Earning**: works offline. When not logged in, we accumulate locally. On
///   first login, `syncAfterLogin` merges local balance with the server's
///   (MAX rule) and clears the local-only flag. After that, every earn is
///   written through to the server via `earn_credits` RPC.
/// - **Spending**: requires login (throws `CreditError('not_authenticated')`
///   otherwise). Goes through the server-atomic `spend_credits` RPC — no way
///   to spend if the server says insufficient balance.
///
/// Server RPCs enforce rate limit (3s between earns) and daily cap (500).
/// Those errors surface as `CreditError('rate_limited' / 'daily_cap_reached')`.
class CreditService extends ChangeNotifier {
  CreditService._();
  static final instance = CreditService._();

  static const _boxName = 'pixora_credits';
  static const _keyBalance = 'balance';
  static const _keyTotalEarned = 'total_earned';
  static const _keyAdsWatched = 'ads_watched';
  static const _keyLocalOnly = 'has_local_only_earnings';
  static const _keyProtectPromptShown = 'protect_prompt_shown';
  static const creditsPerAd = 15;
  static const protectPromptThreshold = 100;

  Box? _box;
  int _balance = 0;
  RealtimeChannel? _realtimeChannel;

  SupabaseClient get _client => Supabase.instance.client;
  bool get _isLoggedIn => _client.auth.currentUser != null;
  String? get _userId => _client.auth.currentUser?.id;

  int get balance => _balance;
  int get totalEarned => _box?.get(_keyTotalEarned, defaultValue: 0) ?? 0;
  int get adsWatched => _box?.get(_keyAdsWatched, defaultValue: 0) ?? 0;

  /// True when the local balance contains earnings that haven't been synced
  /// to a server account yet (i.e. earned while signed out).
  bool get hasUnsyncedLocalEarnings =>
      _box?.get(_keyLocalOnly, defaultValue: false) as bool? ?? false;

  /// Whether the "protect your diamonds" soft prompt should be shown now:
  /// user is signed out, has at least [protectPromptThreshold] local diamonds,
  /// and we haven't prompted them yet in this install.
  bool get shouldShowProtectPrompt =>
      !_isLoggedIn &&
      _balance >= protectPromptThreshold &&
      !(_box?.get(_keyProtectPromptShown, defaultValue: false) as bool? ??
          false);

  /// Mark the protect prompt as shown so we don't nag the user again.
  Future<void> markProtectPromptShown() async {
    await _box?.put(_keyProtectPromptShown, true);
  }

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _balance = _box?.get(_keyBalance, defaultValue: 0) ?? 0;

    // If already logged in when app starts, refresh from server in background.
    if (_isLoggedIn) {
      unawaited(_refreshFromServer());
      _subscribeToRealtimeBalance();
    }
  }

  // ── Earning ────────────────────────────────────────────────────────────

  /// Award credits after watching an ad. Returns the new balance, or throws
  /// `CreditError` on rate_limited / daily_cap_reached when logged in.
  /// Errors are swallowed and logged for non-critical UX (earning is a
  /// nice-to-have, not a blocker).
  Future<void> earnFromAd() async {
    if (_isLoggedIn) {
      try {
        final row = await _client.rpc(
          'earn_credits',
          params: {
            'p_amount': creditsPerAd,
            'p_metadata': <String, dynamic>{'source': 'interstitial'},
          },
        );
        if (row is Map) {
          _balance = (row['balance'] as int?) ?? _balance;
          await _box?.put(_keyBalance, _balance);
          await _box?.put(_keyTotalEarned, row['total_earned'] ?? totalEarned);
          await _box?.put(_keyAdsWatched, row['ads_watched'] ?? adsWatched);
        }
        debugPrint('[Credits] +$creditsPerAd (server, balance: $_balance)');
      } on PostgrestException catch (e) {
        final code = _parseErrorCode(e.message);
        debugPrint('[Credits] earn_credits failed: $code (${e.message})');
        // Don't throw to caller — earning is best-effort. UI just won't
        // update. Next ad will try again.
      } catch (e) {
        debugPrint('[Credits] earn_credits unexpected: $e');
      }
    } else {
      // Local accumulation — will merge on first login.
      _balance += creditsPerAd;
      await _box?.put(_keyBalance, _balance);
      await _box?.put(_keyTotalEarned, totalEarned + creditsPerAd);
      await _box?.put(_keyAdsWatched, adsWatched + 1);
      await _box?.put(_keyLocalOnly, true);
      debugPrint('[Credits] +$creditsPerAd (local, balance: $_balance)');
    }
    notifyListeners();
  }

  /// 2026-06-24 — generic add credits para flujos no-ad (premium daily
  /// refill, promo grants, etc). Logged via 'earn_credits' RPC con el
  /// reason custom. Defensive: errores no rompen UX.
  Future<void> addCredits({required int amount, required String reason}) async {
    if (amount <= 0) return;
    if (_isLoggedIn) {
      try {
        final row = await _client.rpc(
          'earn_credits',
          params: {
            'p_amount': amount,
            'p_metadata': <String, dynamic>{'source': reason},
          },
        );
        if (row is Map) {
          _balance = (row['balance'] as int?) ?? _balance;
          await _box?.put(_keyBalance, _balance);
          await _box?.put(_keyTotalEarned, row['total_earned'] ?? totalEarned);
        }
        debugPrint('[Credits] +$amount ($reason, balance: $_balance)');
      } catch (e) {
        debugPrint('[Credits] addCredits ($reason) failed: $e');
        // Fallback: local-only
        _balance += amount;
        await _box?.put(_keyBalance, _balance);
        await _box?.put(_keyTotalEarned, totalEarned + amount);
      }
    } else {
      _balance += amount;
      await _box?.put(_keyBalance, _balance);
      await _box?.put(_keyTotalEarned, totalEarned + amount);
      await _box?.put(_keyLocalOnly, true);
      debugPrint('[Credits] +$amount ($reason, local, balance: $_balance)');
    }
    notifyListeners();
  }

  // ── Spending ───────────────────────────────────────────────────────────

  /// Spend credits. REQUIRES login — throws `CreditError('not_authenticated')`
  /// if not signed in. Throws `CreditError('insufficient_credits')` if balance
  /// is below [amount].
  ///
  /// [reason] is logged in `credits_audit` for analytics. Examples:
  /// 'ia_generation', 'premium_wallpaper_unlock'.
  /// [metadata] gets saved as JSONB in the audit row for extra context.
  Future<void> spend(
    int amount, {
    required String reason,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isLoggedIn) {
      throw CreditError('not_authenticated');
    }
    if (amount <= 0) {
      throw CreditError('invalid_amount');
    }

    try {
      final row = await _client.rpc(
        'spend_credits',
        params: {
          'p_amount': amount,
          'p_reason': reason,
          'p_metadata': metadata,
        },
      );
      if (row is Map) {
        _balance = (row['balance'] as int?) ?? _balance;
        await _box?.put(_keyBalance, _balance);
      }
      notifyListeners();
      debugPrint('[Credits] -$amount ($reason), balance: $_balance');
    } on PostgrestException catch (e) {
      final code = _parseErrorCode(e.message);
      debugPrint('[Credits] spend_credits failed: $code');
      throw CreditError(code, e.message);
    } catch (e) {
      throw CreditError('network_error', e.toString());
    }
  }

  // ── Login sync ─────────────────────────────────────────────────────────

  /// Called by AuthService after successful sign-in. Merges any local-only
  /// earnings into the server balance using MAX rule and subscribes to
  /// realtime balance updates for cross-device sync.
  Future<void> syncAfterLogin() async {
    if (!_isLoggedIn) return;

    try {
      if (hasUnsyncedLocalEarnings) {
        // Merge local into server via MAX rule.
        final row = await _client.rpc('sync_local_credits', params: {
          'p_balance': _balance,
          'p_earned': totalEarned,
          'p_ads': adsWatched,
        });
        if (row is Map) {
          _balance = (row['balance'] as int?) ?? _balance;
          await _box?.put(_keyBalance, _balance);
          await _box?.put(_keyTotalEarned, row['total_earned'] ?? totalEarned);
          await _box?.put(_keyAdsWatched, row['ads_watched'] ?? adsWatched);
        }
        await _box?.put(_keyLocalOnly, false);
        debugPrint(
            '[Credits] Synced local earnings on login, balance: $_balance');
      } else {
        await _refreshFromServer();
      }
      _subscribeToRealtimeBalance();
      notifyListeners();
    } on PostgrestException catch (e) {
      debugPrint('[Credits] syncAfterLogin failed: ${e.message}');
    } catch (e) {
      debugPrint('[Credits] syncAfterLogin unexpected: $e');
    }
  }

  /// Called on sign-out. Keeps the last known balance in local cache so the UI
  /// doesn't blank, but stops the realtime subscription and marks it as not
  /// our local-only (to avoid re-sync with a different account).
  Future<void> onSignOut() async {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    // Reset local balance to 0 — signed-out state shouldn't show previous
    // user's balance. Earning while signed out will start fresh.
    _balance = 0;
    await _box?.put(_keyBalance, 0);
    await _box?.put(_keyLocalOnly, false);
    notifyListeners();
  }

  // ── Internal helpers ──────────────────────────────────────────────────

  Future<void> _refreshFromServer() async {
    // Cache uid BEFORE await — if the user signs out between the guard
    // and the use, `_userId` becomes null and `_userId!` would crash.
    final uid = _userId;
    if (uid == null) return;
    try {
      final row = await _client
          .from('user_credits')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (row != null) {
        _balance = (row['balance'] as int?) ?? 0;
        await _box?.put(_keyBalance, _balance);
        await _box?.put(_keyTotalEarned, row['total_earned'] ?? 0);
        await _box?.put(_keyAdsWatched, row['ads_watched'] ?? 0);
        notifyListeners();
        debugPrint('[Credits] Refreshed from server: $_balance');
      }
    } catch (e) {
      debugPrint('[Credits] _refreshFromServer failed: $e');
    }
  }

  void _subscribeToRealtimeBalance() {
    if (_realtimeChannel != null) return;
    final uid = _userId;
    if (uid == null) return;
    _realtimeChannel = _client
        .channel('user_credits_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_credits',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final newBalance = row['balance'] as int?;
            if (newBalance != null && newBalance != _balance) {
              _balance = newBalance;
              _box?.put(_keyBalance, _balance);
              notifyListeners();
              debugPrint('[Credits] Realtime update: balance=$_balance');
            }
          },
        )
        .subscribe();
  }

  /// Parse the error code from a Postgres RAISE EXCEPTION message.
  /// RPC throws with messages like "rate_limited" or "insufficient_credits".
  String _parseErrorCode(String? msg) {
    if (msg == null) return 'unknown';
    // Known codes from our RPCs.
    for (final code in const [
      'not_authenticated',
      'rate_limited',
      'daily_cap_reached',
      'insufficient_credits',
      'invalid_amount',
      'missing_reason',
    ]) {
      if (msg.contains(code)) return code;
    }
    return 'unknown';
  }
}

/// Typed error for credit operations. Check `.code` to decide the user-facing
/// message.
class CreditError implements Exception {
  final String code;
  final String? message;
  CreditError(this.code, [this.message]);

  @override
  String toString() =>
      'CreditError($code${message != null ? ": $message" : ""})';

  bool get isNotAuthenticated => code == 'not_authenticated';
  bool get isRateLimited => code == 'rate_limited';
  bool get isDailyCapReached => code == 'daily_cap_reached';
  bool get isInsufficient => code == 'insufficient_credits';
}
