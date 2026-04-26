import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'credit_service.dart';

class AdService {
  AdService._();
  static final instance = AdService._();

  static const _interstitialAdUnitId = 'ca-app-pub-6734758230109098/6687118537';

  InterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;
  bool _isAdLoading = false;

  /// Alternating counter: ad shows on odd counts (1st, 3rd, 5th…),
  /// skips on even counts (2nd, 4th, 6th…).
  int _actionCount = 0;

  bool get isAdLoaded => _isAdLoaded;

  /// Whether the NEXT action will show an ad (true) or be free (false).
  bool get isNextActionFree => _actionCount.isOdd;

  /// Current flag value for debugging.
  int get debugFlag => _actionCount;

  /// Initialize Mobile Ads SDK. Call once at app startup.
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    loadInterstitialAd();
  }

  /// Pre-load an interstitial ad so it's ready when needed.
  void loadInterstitialAd() {
    if (_isAdLoading || _isAdLoaded) return;
    _isAdLoading = true;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdLoaded = true;
          _isAdLoading = false;
          debugPrint('[Pixora] Interstitial ad loaded');
        },
        onAdFailedToLoad: (error) {
          _isAdLoaded = false;
          _isAdLoading = false;
          debugPrint('[Pixora] Interstitial ad failed: ${error.message}');
          // Retry after 10 seconds
          Future.delayed(
              const Duration(seconds: 10), () => loadInterstitialAd());
        },
      ),
    );
  }

  /// DEBUG: set to true to disable ads during testing.
  static const _debugDisableAds = true;

  /// Show interstitial ad on alternating actions (1st yes, 2nd no, 3rd yes…).
  /// Awards credits when an ad is actually shown and watched.
  void showInterstitialAd({required VoidCallback onAdDismissed}) {
    if (_debugDisableAds) {
      onAdDismissed();
      return;
    }
    _actionCount++;
    final shouldShow = _actionCount.isOdd;

    if (!shouldShow) {
      onAdDismissed();
      return;
    }

    if (_interstitialAd == null || !_isAdLoaded) {
      onAdDismissed();
      loadInterstitialAd();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _isAdLoaded = false;
        loadInterstitialAd();
        // Award credits for watching the ad
        CreditService.instance.earnFromAd();
        onAdDismissed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _isAdLoaded = false;
        loadInterstitialAd();
        onAdDismissed();
      },
    );

    _interstitialAd!.show();
  }
}
