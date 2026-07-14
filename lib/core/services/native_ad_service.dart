import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';

/// Native ad manager — separate from [AdService] because native ads have a
/// fundamentally different lifecycle:
///   - Multiple ads alive simultaneously (one per carousel slot)
///   - Each ad owned by the widget that displays it (disposed on widget unmount)
///   - No full-screen takeover, no watchdog, no interstitial state machine
///
/// We don't preload a pool — each [NativeAdCard] requests a fresh ad on mount
/// and disposes it on unmount. AdMob is fast enough that the small loading
/// shimmer is barely visible, and managing a pool with concurrent slots would
/// double the complexity for marginal latency gain.
///
/// Sub bypass + debug disable both honored by checking [AdService] flags at
/// request time.
class NativeAdService {
  NativeAdService._();
  static final instance = NativeAdService._();

  /// Google's reserved test native ad unit ID for Android. Returns predictable
  /// test creatives + never charges advertisers + never risks suspension on
  /// accidental taps. Production replaces this with the real unit ID.
  static const _testAdUnitIdAndroid = 'ca-app-pub-3940256099942544/2247696110';

  /// Production native ad unit ID (Pixora_Native_Carrusel, created 2026-07-14
  /// for the Play Store launch). Release builds use this; debug builds still
  /// fall back to the test unit via [_adUnitId] (kDebugMode guard).
  static const _prodAdUnitIdAndroid = 'ca-app-pub-6734758230109098/9644077378';

  String get _adUnitId {
    if (kDebugMode || _prodAdUnitIdAndroid.isEmpty) return _testAdUnitIdAndroid;
    return _prodAdUnitIdAndroid;
  }

  /// True when native ads are globally disabled (debug flag or premium sub).
  /// Mirror of AdService's gating — keep them in sync.
  bool get isDisabled => AdService.adsDisabledForUser;

  /// Build a NativeAd ready to load. Caller is responsible for `.load()` then
  /// `.dispose()`. The [onLoaded] / [onFailed] callbacks fire from the SDK.
  NativeAd buildAd({
    required VoidCallback onLoaded,
    required void Function(LoadAdError) onFailed,
  }) {
    return NativeAd(
      adUnitId: _adUnitId,
      listener: NativeAdListener(
        onAdLoaded: (_) => onLoaded(),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          onFailed(error);
        },
      ),
      request: const AdRequest(),
      // Google template — Pixora-themed (gold + dark) so it blends with the
      // app's design language without needing a native Android factory.
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF0E0E13),
        cornerRadius: 14.0,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF0E0E13),
          backgroundColor: const Color(0xFFE6B655),
          style: NativeTemplateFontStyle.bold,
          size: 13.0,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFE6B655),
          backgroundColor: const Color(0x00000000),
          style: NativeTemplateFontStyle.bold,
          size: 14.0,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFD0D0D0),
          backgroundColor: const Color(0x00000000),
          style: NativeTemplateFontStyle.normal,
          size: 12.0,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFA0A0A0),
          backgroundColor: const Color(0x00000000),
          style: NativeTemplateFontStyle.italic,
          size: 11.0,
        ),
      ),
    );
  }
}
