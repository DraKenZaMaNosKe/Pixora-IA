import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  AdService._();
  static final instance = AdService._();

  static const _interstitialAdUnitId = 'ca-app-pub-6734758230109098/6687118537';

  InterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;

  bool get isAdLoaded => _isAdLoaded;

  /// Initialize Mobile Ads SDK. Call once at app startup.
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    loadInterstitialAd();
  }

  /// Pre-load an interstitial ad so it's ready when needed.
  void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdLoaded = true;
          debugPrint('[Pixora] Interstitial ad loaded');
        },
        onAdFailedToLoad: (error) {
          _isAdLoaded = false;
          debugPrint('[Pixora] Interstitial ad failed to load: ${error.message}');
        },
      ),
    );
  }

  /// Show the interstitial ad, then call [onAdDismissed] when done.
  /// If no ad is loaded, calls [onAdDismissed] immediately.
  void showInterstitialAd({required VoidCallback onAdDismissed}) {
    if (_interstitialAd == null || !_isAdLoaded) {
      onAdDismissed();
      loadInterstitialAd(); // Try loading for next time
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _isAdLoaded = false;
        loadInterstitialAd(); // Pre-load next ad
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
