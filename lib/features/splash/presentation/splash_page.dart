import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/catalog_index_service.dart';
import '../../../core/services/catalog_service.dart';
import '../../../core/services/legal_service.dart';
import '../../../core/services/shader_download_service.dart';
import '../../../core/services/wallpaper_stats_service.dart';
import '../../home/presentation/home_page.dart';
import '../../legal/presentation/terms_acceptance_page.dart';
import '../../onboarding/presentation/onboarding_page.dart';
import '../../subscription/presentation/subscription_pitch_page.dart';

/// Art Deco Gatsby splash — black tinta + gold diamonds.
///
/// Design direction: Black & Gold (master doc §21) · Variant: Art Deco Gatsby.
/// Luxury 1920s feel with geometric chevrons, rotating diamond, serif italic
/// typography.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  // Black & Gold palette (hardcoded in splash so it works before theme loads).
  static const _ink = Color(0xFF000000);
  static const _cream = Color(0xFFF0E8D6);
  static const _gold = Color(0xFFC9A650);
  static const _goldBright = Color(0xFFF0DD9E);
  static const _goldDim = Color(0xFF8A7A56);
  static const _goldDeep = Color(0xFF5A4E36);

  late final AnimationController _diamondController;
  late final AnimationController _contentController;
  late final AnimationController _exitController;
  bool _loadingDone = false;
  bool _minTimeDone = false;
  bool _exiting = false;
  String _loadingStatus = 'LA COLECCIÓN';
  double _loadingProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _diamondController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _preload();
    Future.delayed(const Duration(milliseconds: 3000), () {
      _minTimeDone = true;
      _navigateIfReady();
    });
  }

  Future<void> _preload() async {
    try {
      if (mounted) {
        setState(() {
          _loadingStatus = 'CHARGEMENT DU CATALOGUE';
          _loadingProgress = 0.25;
        });
      }
      await CatalogService.instance.fetchCatalog();

      if (mounted) {
        setState(() {
          _loadingStatus = 'SYNCHRONISATION';
          _loadingProgress = 0.55;
        });
      }
      await WallpaperStatsService.instance.init();

      if (mounted) {
        setState(() {
          _loadingStatus = 'PRÉPARATION';
          _loadingProgress = 0.85;
        });
      }
      // Bootstrap shaders (~7 KB total) so they're ready when applied.
      // Fire-and-forget: failure here doesn't block navigation.
      unawaited(ShaderDownloadService.instance.ensureBootstrapShaders());
      // v1.7 catalog index validation — fire-and-forget, logs result.
      unawaited(CatalogIndexService.instance.getItems().then((items) {
        debugPrint(
            '[Pixora] CatalogIndex v${CatalogIndexService.instance.version} '
            '→ ${items.length} items: '
            '${items.map((e) => "${e.id}(${e.type})").join(", ")}');
      }));
      await Future.delayed(const Duration(milliseconds: 220));

      if (mounted) {
        setState(() {
          _loadingStatus = 'BIENVENUE';
          _loadingProgress = 1.0;
        });
      }
    } catch (e) {
      debugPrint('[Pixora] Preload error (continuing): $e');
      if (mounted) setState(() => _loadingStatus = 'BIENVENUE');
    }
    _loadingDone = true;
    _navigateIfReady();
  }

  void _navigateIfReady() {
    if (_loadingDone && _minTimeDone && !_exiting && mounted) {
      _exiting = true;
      _exitController.forward().then((_) async {
        if (!mounted) return;
        // Decide first destination: onboarding > subscription pitch > home.
        // Each step decides its own next via onFinish, so the splash only
        // picks the entry point.
        final next = await _firstScreenAfterSplash();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => next,
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      });
    }
  }

  /// Cold-start funnel:
  ///   first launch    → TermsGate → Onboarding → SubscriptionPitch → Home
  ///   second launch   → SubscriptionPitch (if not yet shown) → Home
  ///   pro subscriber  → Home (pitch is auto-skipped by shouldShow)
  ///
  /// TermsGate is hard-blocking: it shows whenever the user has not accepted
  /// the current Terms version (`LegalService.kCurrentTermsVersion`). On
  /// version bumps, every existing user re-sees it on the next launch.
  ///
  /// All onFinish callbacks use the active page context (NOT the splash state)
  /// because by the time the user finishes onboarding/pitch, the splash is
  /// already disposed. Using splash's context would be a use-after-free.
  Future<Widget> _firstScreenAfterSplash() async {
    if (!LegalService.instance.hasAcceptedCurrent()) {
      return TermsAcceptancePage(onFinish: _navigateAfterTerms);
    }
    if (await OnboardingPage.shouldShow()) {
      return OnboardingPage(onFinish: _navigateToPitchOrHome);
    }
    if (await SubscriptionPitchPage.shouldShow()) {
      return SubscriptionPitchPage(onFinish: _navigateToHome);
    }
    return const HomePage();
  }

  /// Called by TermsAcceptancePage when the user taps "Acepto y continuar".
  /// Forwards to onboarding (or pitch / home if onboarding already done).
  Future<void> _navigateAfterTerms(BuildContext context) async {
    if (await OnboardingPage.shouldShow()) {
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              OnboardingPage(onFinish: _navigateToPitchOrHome),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else {
      _navigateToPitchOrHome(context);
    }
  }

  /// Called by OnboardingPage when the user taps "¡Comenzar!".
  /// `context` is the OnboardingPage's own context, guaranteed mounted.
  Future<void> _navigateToPitchOrHome(BuildContext context) async {
    if (await SubscriptionPitchPage.shouldShow()) {
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              SubscriptionPitchPage(onFinish: _navigateToHome),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else {
      _navigateToHome(context);
    }
  }

  /// Called by SubscriptionPitchPage when the user buys or skips.
  /// `context` is the SubscriptionPitchPage's own context.
  void _navigateToHome(BuildContext context) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomePage(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _diamondController.dispose();
    _contentController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  TextStyle _display(double size, Color color,
          {FontWeight w = FontWeight.w300,
          FontStyle style = FontStyle.normal,
          double ls = 0.02}) =>
      GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontWeight: w,
        fontStyle: style,
        color: color,
        letterSpacing: ls,
        height: 1.0,
      );

  TextStyle _poiret(double size, Color color, {double ls = 0.4}) =>
      GoogleFonts.poiretOne(
        fontSize: size,
        color: color,
        letterSpacing: ls,
        height: 1.2,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ink,
      body: AnimatedBuilder(
        animation: Listenable.merge([_contentController, _exitController]),
        builder: (context, _) {
          final exitOpacity = 1.0 - _exitController.value;
          final contentOpacity =
              Curves.easeOut.transform(_contentController.value);
          return Opacity(
            opacity: exitOpacity,
            child: Stack(
              children: [
                // Double gold frame — thin, sits inside scaffold.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: _gold, width: 1),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _gold.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  // LayoutBuilder + IntrinsicHeight + ClipRect protect the
                  // splash from RenderFlex overflow on phones where the
                  // Spacers + fixed-height children sum > available height
                  // (notch + 3-button-nav steal vertical space briefly during
                  // the contentController fade-in). The ClipRect silently
                  // hides any overflow instead of painting yellow stripes.
                  child: LayoutBuilder(
                    builder: (context, constraints) => ClipRect(
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 36),
                            child: IntrinsicHeight(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Opacity(
                                    opacity: contentOpacity,
                                    child: _buildTopDeco(),
                                  ),
                                  const Spacer(),
                                  Opacity(
                                    opacity: contentOpacity,
                                    child: _buildDiamondLogo(),
                                  ),
                                  const SizedBox(height: 32),
                                  Opacity(
                                    opacity: contentOpacity,
                                    child: _buildTitle(),
                                  ),
                                  const SizedBox(height: 14),
                                  Opacity(
                                    opacity: contentOpacity,
                                    child: _buildDivider(),
                                  ),
                                  const SizedBox(height: 12),
                                  Opacity(
                                    opacity: contentOpacity,
                                    child: _buildTagline(),
                                  ),
                                  const Spacer(),
                                  Opacity(
                                    opacity: contentOpacity,
                                    child: _buildBottomDeco(),
                                  ),
                                  const SizedBox(height: 20),
                                  Opacity(
                                    opacity: contentOpacity,
                                    child: _buildProgress(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Chevron row: "— ◆ ◇ ◆ ◇ ◆ —"
  Widget _buildTopDeco() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 5; i++) ...[
          Text(
            i.isEven ? '◆' : '◇',
            style: TextStyle(color: _gold, fontSize: 14, height: 1),
          ),
          if (i < 4) const SizedBox(width: 14),
        ],
      ],
    );
  }

  /// Rotating diamond (square rotated 45°) + inner diamond + gold serif "P".
  Widget _buildDiamondLogo() {
    return SizedBox(
      height: 200,
      child: Center(
        child: SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer rotating diamond.
              AnimatedBuilder(
                animation: _diamondController,
                builder: (context, _) => Transform.rotate(
                  angle: _diamondController.value * 2 * pi,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: _gold, width: 1.5),
                    ),
                  ),
                ),
              ),
              // Inner static diamond outline.
              Transform.rotate(
                angle: pi / 4,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _gold.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                ),
              ),
              // The "P".
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_goldBright, _gold, _goldDeep],
                  stops: [0.0, 0.5, 1.0],
                ).createShader(rect),
                child: Text(
                  'P',
                  style: _display(
                    120,
                    Colors.white,
                    w: FontWeight.w300,
                    style: FontStyle.italic,
                    ls: -0.04,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Text.rich(
      TextSpan(
        style: _display(38, _cream, ls: 0.15, w: FontWeight.w500),
        children: [
          const TextSpan(text: 'PIX'),
          TextSpan(
            text: 'ora',
            style: _display(
              38,
              _gold,
              w: FontWeight.w400,
              style: FontStyle.italic,
              ls: 0.05,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildDivider() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 40, height: 1, color: _gold),
        const SizedBox(width: 10),
        Transform.rotate(
          angle: pi / 4,
          child: Container(width: 5, height: 5, color: _gold),
        ),
        const SizedBox(width: 10),
        Container(width: 40, height: 1, color: _gold),
      ],
    );
  }

  Widget _buildTagline() {
    return Text(
      'la colección',
      textAlign: TextAlign.center,
      style: _display(16, _goldDim,
          w: FontWeight.w400, style: FontStyle.italic, ls: 0.2),
    );
  }

  Widget _buildBottomDeco() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++) ...[
              Text(
                i == 1 ? '◇' : '◆',
                style: TextStyle(color: _gold, fontSize: 12, height: 1),
              ),
              if (i < 2) const SizedBox(width: 18),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'MMXXVI',
          textAlign: TextAlign.center,
          style: _poiret(11, _goldDeep, ls: 0.5),
        ),
      ],
    );
  }

  Widget _buildProgress() {
    return Column(
      children: [
        SizedBox(
          height: 1,
          child: Stack(
            children: [
              Container(color: _gold.withValues(alpha: 0.2)),
              FractionallySizedBox(
                widthFactor: _loadingProgress,
                child: Container(color: _gold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '· $_loadingStatus ·',
          textAlign: TextAlign.center,
          style: _poiret(10, _goldDim, ls: 0.5),
        ),
      ],
    );
  }
}
