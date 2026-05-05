import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/subscription_service.dart';

/// Premium pitch shown right after the onboarding tutorial completes
/// (concept #02 "Apple Premium" — confirmed by user 2026-05-05).
///
/// Design: minimal, gradient hero with shimmering gold tint, single feature
/// column, big price card, prominent CTA. Includes a "Ahora no" skip that
/// proceeds to HomePage without buying.
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
  /// AND isn't already a Pro subscriber).
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

  static const _accent = Color(0xFFD9B14A);

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.trackPitchShown('post_onboarding');
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
          const SnackBar(content: Text('¡Bienvenido a Pixora Pro!')),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _Hero(),
              const SizedBox(height: 24),
              _Features(),
              const SizedBox(height: 24),
              _PriceCard(),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _purchasing ? null : _onSubscribe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _purchasing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2.4,
                            ),
                          )
                        : const Text(
                            'Comenzar Pixora Pro',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
              ),
              TextButton(
                onPressed: _purchasing ? null : _onSkip,
                child: Text(
                  'Ahora no',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  'Renovación automática mensual. Cancela en cualquier momento desde Google Play. La compra se procesa con tu cuenta de Google.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Soft golden halo behind the badge
        Positioned(
          top: 30,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFD9B14A).withValues(alpha: 0.22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 50, 28, 0),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD9B14A), Color(0xFFF5D676)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'PIXORA PRO',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Color(0xFFD9B14A), Color(0xFFF5D676)],
                ).createShader(rect),
                child: const Text(
                  'Eleva tu',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const Text(
                'experiencia',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Sin anuncios. Acceso completo. Soporte prioritario.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w300,
                  color: Colors.white.withValues(alpha: 0.62),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Features extends StatelessWidget {
  static const _features = <(IconData, String, String)>[
    (
      Icons.block,
      'Cero anuncios',
      'Experiencia ininterrumpida — el ojo descansa',
    ),
    (
      Icons.menu_book_outlined,
      'Códices culturales',
      'Toda la mitología — Mictlán, Iah, Quetzalcóatl y los que vendrán',
    ),
    (
      Icons.celebration_outlined,
      'Eventos exclusivos',
      'Wallpapers únicos en cada temporada: Día de Muertos, Navidad, San Valentín',
    ),
    (
      Icons.spa_outlined,
      'AURA ilimitado',
      'Todas las frecuencias y paisajes sonoros sin restricciones',
    ),
    (
      Icons.auto_awesome,
      'Acceso anticipado',
      'Cada nuevo dios y escena 3D antes que nadie',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: _features.map((f) {
          final isLast = f == _features.last;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: isLast
                    ? BorderSide.none
                    : BorderSide(
                        color: Colors.white.withValues(alpha: 0.07),
                        width: 0.5,
                      ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFD9B14A).withValues(alpha: 0.22),
                        const Color(0xFFD9B14A).withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(f.$1, color: const Color(0xFFD9B14A), size: 19),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.$2,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        f.$3,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w300,
                          color: Colors.white.withValues(alpha: 0.55),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFD9B14A).withValues(alpha: 0.16),
              const Color(0xFFD9B14A).withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFD9B14A).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          children: [
            Text(
              'MENSUAL',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 2.2,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  '\$49',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1,
                    letterSpacing: -1.5,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'MXN',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cancela cuando quieras',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w300,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
