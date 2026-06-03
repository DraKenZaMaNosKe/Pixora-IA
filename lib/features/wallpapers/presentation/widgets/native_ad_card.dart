import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../../core/services/native_ad_service.dart';

/// A native ad styled to live alongside [WallpaperCard]s in a horizontal
/// carousel. Slightly wider than a wallpaper card (280 vs 140) so Google's
/// medium template has room to breathe — the visual break reads as a
/// "premium placement" rather than blending into product cards (which would
/// risk accidental taps + ad policy violations).
///
/// Lifecycle: loads its own [NativeAd] on init, disposes on unmount. While
/// loading, shows a subtle gold shimmer in the card frame so the slot doesn't
/// jump in size when the ad resolves.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({
    super.key,
    this.height = 260.0,
    this.width = 280.0,
  });

  final double height;
  final double width;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    if (NativeAdService.instance.isDisabled) {
      // Premium subscriber or debug-disabled — render nothing, never call SDK.
      setState(() => _failed = true);
      return;
    }
    final ad = NativeAdService.instance.buildAd(
      onLoaded: () {
        if (mounted) setState(() => _loaded = true);
      },
      onFailed: (error) {
        debugPrint('[NativeAdCard] load failed: ${error.message}');
        if (mounted) setState(() => _failed = true);
      },
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    _ad = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Failed → render nothing (the carousel slot will just be empty). Better
    // UX than an obvious "ad failed" placeholder which looks broken.
    if (_failed) return const SizedBox.shrink();

    return Container(
      width: widget.width,
      height: widget.height,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6B655), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE6B655).withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            if (_loaded && _ad != null)
              Positioned.fill(child: AdWidget(ad: _ad!))
            else
              const _LoadingShimmer(),
            // "AD" pill — tiny, top-right, gold on dark. Required by AdMob
            // policy + helps distinguish ad cards from wallpaper cards.
            const Positioned(
              top: 6,
              right: 6,
              child: _AdBadge(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdBadge extends StatelessWidget {
  const _AdBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE6B655),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'AD',
        style: TextStyle(
          color: Color(0xFF0E0E13),
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _LoadingShimmer extends StatefulWidget {
  const _LoadingShimmer();

  @override
  State<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<_LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2 * t, -0.5),
              end: Alignment(-0.5 + 2 * t, 0.5),
              colors: const [
                Color(0xFF0E0E13),
                Color(0xFF1A1A22),
                Color(0xFFE6B655),
                Color(0xFF1A1A22),
                Color(0xFF0E0E13),
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ),
          ),
        );
      },
    );
  }
}
