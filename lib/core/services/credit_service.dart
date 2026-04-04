import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Simple local credit system stored in Hive.
/// Credits accumulate from watching ads — spendable when IA features launch.
class CreditService extends ChangeNotifier {
  CreditService._();
  static final instance = CreditService._();

  static const _boxName = 'pixora_credits';
  static const _keyBalance = 'balance';
  static const _keyTotalEarned = 'total_earned';
  static const _keyAdsWatched = 'ads_watched';
  static const creditsPerAd = 15;

  Box? _box;
  int _balance = 0;

  int get balance => _balance;
  int get totalEarned => _box?.get(_keyTotalEarned, defaultValue: 0) ?? 0;
  int get adsWatched => _box?.get(_keyAdsWatched, defaultValue: 0) ?? 0;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _balance = _box?.get(_keyBalance, defaultValue: 0) ?? 0;
  }

  /// Award credits after watching an ad.
  Future<void> earnFromAd() async {
    _balance += creditsPerAd;
    await _box?.put(_keyBalance, _balance);
    await _box?.put(_keyTotalEarned, totalEarned + creditsPerAd);
    await _box?.put(_keyAdsWatched, adsWatched + 1);
    notifyListeners();
    debugPrint('[Credits] +$creditsPerAd from ad (balance: $_balance)');
  }

  /// Spend credits (for future IA generation).
  /// Returns true if enough credits, false if not.
  Future<bool> spend(int amount) async {
    if (_balance < amount) return false;
    _balance -= amount;
    await _box?.put(_keyBalance, _balance);
    notifyListeners();
    return true;
  }
}
