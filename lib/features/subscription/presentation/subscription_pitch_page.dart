import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/subscription_service.dart';

/// Premium pitch shown right after the onboarding tutorial completes.
///
/// Design: "La Vitrina Dorada" (user pick, 2026-07-18) — a single premium
/// artwork in a gilded frame, treated like a gallery piece. Sells desire, not
/// a feature list. Fraunces italic display, honest localized pricing, the
/// 7-day trial up front. Includes an "Ahora no" skip that proceeds without
/// buying.
///
/// Layout is fully scroll-based with proportional spacing (no Expanded/Spacer,
/// which throw inside a scroll view) so it can never overflow — it adapts from
/// the short Huawei (1080x1920) up to tall devices.
///
/// Triggers Google Play subscription sheet via SubscriptionService.buyMonthly().
/// Skipped state is remembered in Hive so we don't re-prompt on every launch.
class SubscriptionPitchPage extends StatefulWidget {
  const SubscriptionPitchPage({super.key, required this.onFinish});

  /// Called when the user either skips or completes a purchase. Receives the
  /// active page context so the navigator call works regardless of whether
  /// the original caller (splash, settings, etc.) has been disposed.
  final void Function(BuildContext context) onFinish;

  static const _hiveBox = 'pixora_settings';
  static const _hiveKey = 'subscription_pitch_seen_v1';

  /// Returns true if the pitch should be shown (user hasn't skipped/seen,
  /// AND isn't already a subscriber).
  static Future<bool> shouldShow() async {
    if (SubscriptionService.instance.hasAccess) return false;
    try {
      final box = await Hive.openBox(_hiveBox);
      final seen = box.get(_hiveKey, defaultValue: false) as bool;
      return !seen;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final box = await Hive.openBox(_hiveBox);
      await box.put(_hiveKey, true);
    } catch (_) {}
  }

  @override
  State<SubscriptionPitchPage> createState() => _SubscriptionPitchPageState();
}

class _SubscriptionPitchPageState extends State<SubscriptionPitchPage> {
  bool _purchasing = false;

  // Vitrina palette.
  static const _gold = Color(0xFFE4B95A);
  static const _goldDeep = Color(0xFFB8862F);
  static const _foil = Color(0xFFF4D6B8);
  static const _cream = Color(0xFFF6F2E9);

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.trackPitchShown('post_onboarding');
  }

  /// The real, region-localized price Google will charge (e.g. "$199.00",
  /// "€11.99"), read from the Play Store product. Falls back to the MX price
  /// only if the product hasn't loaded yet. Never hardcode a currency here —
  /// showing "$9.99 USD" to a user Google charges €11.99 is a trust-killer.
  String get _priceLabel {
    final p = SubscriptionService.instance.monthlyProduct?.price;
    return (p == null || p.isEmpty) ? '\$199 MXN' : p;
  }

  Future<void> _onSubscribe() async {
    if (_purchasing) return;
    AnalyticsService.instance.trackPitchCtaTap();
    setState(() => _purchasing = true);
    try {
      // Debug builds (sideloaded APK) cannot reach Google Play Billing —
      // the upload key signature doesn't match what Play Store has on file,
      // and apps must be installed via Play to even initialise BillingClient.
      // Simulate a successful purchase so the rest of the flow can be tested.
      if (kDebugMode) {
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🧪 Modo desarrollo: compra simulada. En Play Store funciona normal.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        AnalyticsService.instance
            .trackPitchPaid(productId: 'pixora_monthly_debug');
        // Actually flip into the subscribed state so the ad-free / mystery-
        // free experience is testable on a sideloaded build (no-op in release).
        SubscriptionService.instance.debugGrantAccess();
        await SubscriptionPitchPage.markSeen();
        if (!mounted) return;
        widget.onFinish(context);
        return;
      }

      // Release flow — real Google Play purchase sheet
      final ok = await SubscriptionService.instance.buyMonthly();
      if (!mounted) return;
      if (ok) {
        AnalyticsService.instance.trackPitchPaid(productId: 'pixora_monthly');
        await SubscriptionPitchPage.markSeen();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Bienvenido a Pixora Plus!')),
        );
        widget.onFinish(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La compra fue cancelada o falló. Intenta de nuevo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _onSkip() async {
    await SubscriptionPitchPage.markSeen();
    if (mounted) widget.onFinish(context);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Frame scales with the screen but is capped, so the piece stays a focal
    // object rather than filling the view. Also capped by height so it never
    // pushes the CTA off a short screen.
    final frameW = math.min(size.width * 0.54, size.height * 0.28);
    // Breathing room above the frame, proportional to the screen so tall
    // devices feel airy and short ones stay tight. Clamped both ways.
    final topGap = (size.height * 0.045).clamp(12.0, 48.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.55),
            radius: 1.1,
            colors: [Color(0xFF1C1730), Color(0xFF0A0812)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top row: badge + skip
                  Row(
                    children: [
                      _plusBadge(),
                      const Spacer(),
                      IconButton(
                        onPressed: _purchasing ? null : _onSkip,
                        icon: Icon(
                          Icons.close_rounded,
                          color: _cream.withValues(alpha: 0.45),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: topGap),

                  // The gilded frame — the hero.
                  _GildedFrame(width: frameW),

                  SizedBox(height: topGap * 0.7 + 16),
                  Text(
                    'Desbloquea la\ncolección completa.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fraunces(
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w400,
                      fontSize: 29,
                      height: 1.08,
                      letterSpacing: -0.3,
                      color: _cream,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Wallpapers, escenas 3D y tonos que no están\nen la versión gratis.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                      color: _cream.withValues(alpha: 0.6),
                    ),
                  ),

                  SizedBox(height: topGap + 20),

                  // CTA
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: _gold.withValues(alpha: 0.34),
                            blurRadius: 26,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _purchasing ? null : _onSubscribe,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          foregroundColor: const Color(0xFF1A1207),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ).copyWith(
                          backgroundColor:
                              WidgetStateProperty.resolveWith((states) {
                            return states.contains(WidgetState.disabled)
                                ? _goldDeep
                                : _gold;
                          }),
                        ),
                        child: _purchasing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF1A1207),
                                  strokeWidth: 2.4,
                                ),
                              )
                            : Text(
                                'Probar 7 días gratis',
                                style: GoogleFonts.inter(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Localized price — updates when the product loads.
                  AnimatedBuilder(
                    animation: SubscriptionService.instance,
                    builder: (context, _) => Text(
                      'Luego $_priceLabel/mes · cancela cuando quieras',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _foil.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _purchasing ? null : _onSkip,
                    child: Text(
                      'Ahora no',
                      style: GoogleFonts.inter(
                        color: _cream.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Renovación automática mensual. Cancela cuando quieras '
                    'desde Google Play. La compra se procesa con tu cuenta '
                    'de Google.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: _cream.withValues(alpha: 0.3),
                      fontSize: 10.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _plusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_foil, _gold]),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '✦ PIXORA PLUS',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: const Color(0xFF1A1408),
        ),
      ),
    );
  }
}

/// A premium artwork mounted in a gold-foil frame with a warm glow behind it —
/// the single object the whole screen is built around. Height is derived from
/// [width] (fixed 3:4), so it never depends on unbounded constraints.
class _GildedFrame extends StatelessWidget {
  const _GildedFrame({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    // Inner art area after the 9px frame border, kept at 3:4.
    final innerW = width - 18;
    final innerH = innerW * 4 / 3;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Warm halo bleeding out from behind the frame.
        Container(
          width: width * 1.7,
          height: (innerH + 18) * 1.4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFE4B95A).withValues(alpha: 0.20),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Container(
          width: width,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF4D6B8),
                Color(0xFFB8862F),
                Color(0xFF6B4E1E),
                Color(0xFFE4B95A),
              ],
              stops: [0.0, 0.4, 0.7, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 40,
                offset: const Offset(0, 22),
              ),
            ],
          ),
          child: SizedBox(
            width: innerW,
            height: innerH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Image.asset(
                'assets/onboarding/01_bienvenida.webp',
                fit: BoxFit.cover,
                // If the asset ever fails, show a cosmic gradient rather than a
                // broken-image glyph — the frame must always look intentional.
                errorBuilder: (_, __, ___) => const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.3, -0.6),
                      colors: [Color(0xFF7D5AC9), Color(0xFF120F26)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
