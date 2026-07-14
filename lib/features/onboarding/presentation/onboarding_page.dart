import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/design/hud_tokens.dart';

/// First-launch tutorial. PageView con 7 slides explicando las secciones
/// principales de Pixora. Skippable. El estado "ya lo vio" se guarda en Hive.
///
/// Mostrar con: `OnboardingPage.shouldShow()` → true la primera vez.
/// Después de completar (o skip), llamar `OnboardingPage.markSeen()`.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onFinish});

  /// Callback cuando el usuario termina el tutorial (Comenzar) o salta (Skip).
  /// Recibe el context activo de la OnboardingPage para que el siguiente
  /// destino pueda navegar correctamente (no usar el context del splash, que
  /// ya fue desmontado por pushReplacement).
  final void Function(BuildContext context) onFinish;

  static const _hiveBox = 'pixora_settings';
  static const _hiveKey = 'onboarding_seen_v1';

  /// Returns true if the user hasn't completed onboarding yet.
  /// Reset by bumping the version in `_hiveKey` (e.g. 'onboarding_seen_v2').
  static Future<bool> shouldShow() async {
    try {
      final box = await Hive.openBox(_hiveBox);
      final seen = box.get(_hiveKey, defaultValue: false) as bool;
      return !seen;
    } catch (_) {
      return false; // safer default — don't block app on Hive errors
    }
  }

  static Future<void> markSeen() async {
    try {
      final box = await Hive.openBox(_hiveBox);
      await box.put(_hiveKey, true);
    } catch (_) {}
  }

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  int _currentIndex = 0;

  static const _slides = <_SlideData>[
    _SlideData(
      icon: Icons.image_outlined,
      iconColor: Color(0xFF3B82F6),
      title: 'Bienvenido a Pixora',
      subtitle: 'Descubre wallpapers, sonidos y experiencias visuales',
      body:
          'Tu pantalla nunca volverá a ser igual. Pixora reúne arte, mitología y tecnología en una sola app.',
    ),
    _SlideData(
      icon: Icons.image_outlined,
      iconColor: Color(0xFF3B82F6),
      title: 'Wallpapers · WALL',
      subtitle: 'Cientos de fondos estáticos curados',
      body:
          'Imágenes de alta resolución organizadas por categoría. Aplica a Inicio, Bloqueo o ambos.',
    ),
    _SlideData(
      icon: Icons.play_arrow_rounded,
      iconColor: Color(0xFFEF4444),
      title: 'LIVE',
      subtitle: 'Wallpapers que cobran vida',
      body:
          'Animaciones interactivas — toca o inclina el teléfono para que el escenario reaccione.',
    ),
    _SlideData(
      icon: Icons.threed_rotation_rounded,
      iconColor: Color(0xFF8B5CF6),
      title: '3D · Parallax',
      subtitle: 'Profundidad real al inclinar',
      body:
          'Escenas con capas que se mueven por separado: Goku Genkidama, Volcán Dragón, Castillo al ocaso, y más.',
    ),
    _SlideData(
      icon: Icons.menu_book_outlined,
      iconColor: Color(0xFFD9B14A),
      title: 'CULTURA · Códice',
      subtitle: '¡NUEVO! Wallpapers con historia',
      body:
          'Cada uno trae un capítulo: mitología real, datos curiosos, símbolos. Aprende mientras decoras tu pantalla.',
      isNew: true,
    ),
    _SlideData(
      icon: Icons.spa_outlined,
      iconColor: Color(0xFF06B6D4),
      title: 'AURA',
      subtitle: 'Sonidos para concentrarte y descansar',
      body:
          'Frecuencias Solfeggio + paisajes sonoros de naturaleza. Reproducción en background con timer de sueño.',
    ),
    _SlideData(
      icon: Icons.nights_stay_outlined,
      iconColor: Color(0xFFD4AF37),
      title: 'ARCANO',
      subtitle: 'Calendario lunar personalizado',
      body:
          'Wallpaper que cambia cada noche con la fase real de la luna. Tu signo zodiacal aparece como guardián.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentIndex < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _skip() async => _finish();

  Future<void> _finish() async {
    await OnboardingPage.markSeen();
    if (mounted) widget.onFinish(context);
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    // QA #2 — status bar icons must contrast with the onboarding background.
    final bgIsDark =
        ThemeData.estimateBrightnessForColor(h.bg) == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            bgIsDark ? Brightness.light : Brightness.dark, // Android
        statusBarBrightness:
            bgIsDark ? Brightness.dark : Brightness.light, // iOS
      ),
      child: Scaffold(
        backgroundColor: h.bg,
        body: SafeArea(
          child: Column(
            children: [
              // Skip button (top right)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                  child: AnimatedOpacity(
                    opacity: _currentIndex == _slides.length - 1 ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: _skip,
                      child: Text(
                        'Saltar',
                        style: TextStyle(
                          color: h.textDim,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Slides
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _currentIndex = i),
                  itemCount: _slides.length,
                  itemBuilder: (_, i) => _Slide(data: _slides[i], h: h),
                ),
              ),

              // Dots indicator
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slides.length, (i) {
                    final active = i == _currentIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active ? h.accent : h.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),

              // CTA button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: h.accent,
                      foregroundColor: h.bg,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _currentIndex == _slides.length - 1
                          ? '¡Comenzar!'
                          : 'Siguiente',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: h.isDark ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideData {
  const _SlideData({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.body,
    this.isNew = false,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String body;
  final bool isNew;
}

class _Slide extends StatelessWidget {
  const _Slide({required this.data, required this.h});
  final _SlideData data;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon hero with soft halo
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  data.iconColor.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: data.iconColor.withValues(alpha: 0.12),
                border: Border.all(
                    color: data.iconColor.withValues(alpha: 0.4), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Icon(data.icon, size: 56, color: data.iconColor),
            ),
          ),
          const SizedBox(height: 36),

          // NEW badge (just for the Cultura slide)
          if (data.isNew)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: data.iconColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '✨ NUEVO',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: h.isDark ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

          // Title (Fraunces italic for editorial feel)
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 32,
              fontWeight: FontWeight.w600,
              color: h.text,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),

          // Subtitle (accent color)
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: data.iconColor,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 24),

          // Body explanation
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: h.textDim,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
