import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/ad_service.dart';

/// Mystery card que reemplaza ocasionalmente cards normales en el grid
/// (1 de cada N posiciones).
///
/// 3 estados posibles:
///   1. **Mystery** (default): Glitch Neon, ??? cyan con RGB split
///   2. **Tesoro Bonus** (1 de cada ~5 reveals): card dorada con CTA
///      "DESCUBRIR" que dispara ad interstitial. Al cerrar el ad,
///      AdService.earnFromAd() suma diamantes automáticamente +
///      revela el wallpaper como recompensa.
///   3. **Revealed** (wallpaper real): el card normal de la grid.
///
/// Auto-hide: 3s en estados (1)+(2) sin acción → vuelve a mystery.
///
/// 2026-06-24 — Engagement feature con monetización opt-in.
class MysteryCardWidget extends StatefulWidget {
  const MysteryCardWidget({
    required this.revealedChild,
    required this.wallpaperId,
    this.onRevealed,
    this.rewardNoun = 'wallpaper',
    this.placement = 'mystery',
    super.key,
  });

  /// El widget real que se mostrará después del tap (la card del contenido).
  final Widget revealedChild;

  /// ID del item — usado para hash (decisión bonus vs normal) y AdService.
  final String wallpaperId;

  /// Callback opcional cuando el user revela. Útil para analytics.
  final VoidCallback? onRevealed;

  /// Sustantivo del premio en el copy del bonus ("wallpaper", "tono",
  /// "fondo"). Permite reusar la carta en LIVE/3D/TONOS con texto correcto.
  final String rewardNoun;

  /// Prefijo de placement para AdService (analytics por sección):
  /// `${placement}_reveal` y `${placement}_bonus`. Ej: 'mystery_tono'.
  final String placement;

  @override
  State<MysteryCardWidget> createState() => _MysteryCardWidgetState();
}

enum _MysteryState { mystery, bonus, revealed }

class _MysteryCardWidgetState extends State<MysteryCardWidget>
    with TickerProviderStateMixin {
  late final AnimationController _flipCtrl;
  _MysteryState _state = _MysteryState.mystery;
  Timer? _autoHideTimer;

  // RGB jitter para el glitch.
  double _glitchOffsetX = 0;
  double _glitchOffsetY = 0;
  final _rng = math.Random();
  bool _glitchScheduled = false;

  /// Tiempo antes de volver a mystery si user no abre el preview.
  static const Duration _autoHideAfter = Duration(seconds: 3);

  /// 1 de cada N reveals es Tesoro Bonus (con ad).
  /// 5 = 20% — frecuente pero no spam.
  static const int _kBonusEvery = 5;

  /// Decide si este reveal será bonus (1/5 probabilidad determinística).
  bool get _isBonusReveal =>
      widget.wallpaperId.hashCode.abs() % _kBonusEvery == 0;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scheduleGlitch();
  }

  void _scheduleGlitch() {
    if (_glitchScheduled) return;
    _glitchScheduled = true;
    Future.delayed(Duration(milliseconds: 2500 + _rng.nextInt(2000)), () {
      _glitchScheduled = false;
      if (!mounted || _state != _MysteryState.mystery) return;
      setState(() {
        _glitchOffsetX = (_rng.nextDouble() - 0.5) * 6;
        _glitchOffsetY = (_rng.nextDouble() - 0.5) * 3;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        setState(() {
          _glitchOffsetX = 0;
          _glitchOffsetY = 0;
        });
        _scheduleGlitch();
      });
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _flipCtrl.dispose();
    super.dispose();
  }

  /// Tap en la mystery card (front). Dirige a bonus o a revealed
  /// dependiendo del hash.
  Future<void> _tapMystery() async {
    if (_state != _MysteryState.mystery) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
    if (_isBonusReveal) {
      // Phase 3: muestra Tesoro Bonus en vez del wallpaper.
      setState(() => _state = _MysteryState.bonus);
      await _flipCtrl.forward();
      _autoHideTimer = Timer(_autoHideAfter, _hideBackToMystery);
    } else {
      // Phase 1: reveal directo al wallpaper.
      setState(() => _state = _MysteryState.revealed);
      await _flipCtrl.forward();
      widget.onRevealed?.call();
      _autoHideTimer = Timer(_autoHideAfter, _hideBackToMystery);
      // 2026-07-04 — Eduardo: monetizar cada reveal, no solo los bonus.
      // AdService alterna 1-yes/2-no internamente (ver ad_service.dart)
      // así que en promedio ~50% de reveals disparan ad real. El
      // interstitial de AdMob YA trae X para cerrar. Silent fail si
      // no cargó — nunca penalizar al user por ad no disponible.
      _showRevealAd();
    }
  }

  Future<void> _showRevealAd() async {
    if (!mounted) return;
    try {
      await AdService.instance.showInterstitialAd(
        placement: '${widget.placement}_reveal',
        wallpaperId: widget.wallpaperId,
        onAdDismissed: () {},
      );
    } catch (_) {
      // Silent fail — el wallpaper ya se reveló, el ad es upside.
    }
  }

  /// Tap en "DESCUBRIR" del bonus → ad → reveal wallpaper como recompensa.
  Future<void> _tapBonusDescubrir() async {
    _autoHideTimer?.cancel();
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
    // Defensive: si AdService truena o el user no completa el ad, igual
    // revelamos el wallpaper para no penalizar.
    try {
      await AdService.instance.showInterstitialAd(
        placement: '${widget.placement}_bonus',
        wallpaperId: widget.wallpaperId,
        onAdDismissed: () {
          if (!mounted) return;
          // AdService.earnFromAd() YA fue llamado internamente — el user
          // ya tiene sus diamantes. Solo revelamos el wallpaper.
          _proceedToReveal();
        },
      );
    } catch (e) {
      // Ad failed → reveal directo igual.
      _proceedToReveal();
    }
  }

  Future<void> _proceedToReveal() async {
    if (!mounted) return;
    setState(() => _state = _MysteryState.revealed);
    // Re-do flip animation for the wallpaper reveal.
    await _flipCtrl.reverse();
    await _flipCtrl.forward();
    if (!mounted) return;
    widget.onRevealed?.call();
    _autoHideTimer = Timer(_autoHideAfter, _hideBackToMystery);
  }

  Future<void> _hideBackToMystery() async {
    if (!mounted || _state == _MysteryState.mystery) return;
    await _flipCtrl.reverse();
    if (!mounted) return;
    setState(() => _state = _MysteryState.mystery);
    _scheduleGlitch();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flipCtrl,
      builder: (context, _) {
        final t = _flipCtrl.value;
        final angle = t * math.pi;
        final showFront = t < 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: showFront
              ? _buildMysteryFace()
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: _state == _MysteryState.bonus
                      ? _buildBonusFace()
                      : widget.revealedChild,
                ),
        );
      },
    );
  }

  // ════════════════ FRONT: MYSTERY (Glitch Neon) ════════════════
  Widget _buildMysteryFace() {
    return GestureDetector(
      onTap: _tapMystery,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A0033), Color(0xFFFF2BD6)],
            ),
            border: Border.all(color: const Color(0xFFFF2BD6), width: 2),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2BD6).withValues(alpha: 0.4),
                blurRadius: 20,
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                  child: CustomPaint(painter: _SynthwaveGridPainter())),
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.2,
                        colors: [
                          Colors.transparent,
                          const Color(0xFFFF2BD6).withValues(alpha: 0.15),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // FittedBox scaleDown + padding-bottom reservado para el hint
              // → nunca overflow, incluso en cards chicas de 3 columnas
              // (TONOS). En cards grandes se ve idéntico. 2026-07-05.
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 34),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: const Color(0xFFE6B655), width: 1),
                          ),
                          child: Text(
                            'MYSTERY',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFE6B655),
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _GlitchText(
                          text: '???',
                          offsetX: _glitchOffsetX,
                          offsetY: _glitchOffsetY,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Text(
                  '▶ TAP TO REVEAL',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF00F0FF),
                    letterSpacing: 2,
                    shadows: [
                      Shadow(
                        color: const Color(0xFF00F0FF).withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════ BACK (opcional): TESORO BONUS (golden) ════════════════
  Widget _buildBonusFace() {
    return GestureDetector(
      onTap: _tapBonusDescubrir,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFD95E), Color(0xFFE6B655), Color(0xFF8B5A0F)],
            ),
            border: Border.all(color: const Color(0xFFFFD95E), width: 2),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE6B655).withValues(alpha: 0.6),
                blurRadius: 24,
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Foil sweep overlay
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _flipCtrl,
                    builder: (_, __) =>
                        CustomPaint(painter: _FoilSweepPainter()),
                  ),
                ),
              ),
              // Sparkles
              ..._buildSparkles(),
              // Content — FittedBox scaleDown + padding-bottom reservado para
              // el CTA "DESCUBRIR" → sin overflow en cards de 3 columnas
              // (TONOS). 2026-07-05.
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 48),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '✨ TESORO ✨',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.black.withValues(alpha: 0.85),
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'BONUS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('🎁', style: TextStyle(fontSize: 64)),
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Apoya a Pixora\n+ desbloquea\n'
                            '${widget.rewardNoun} sorpresa',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withValues(alpha: 0.75),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // CTA
              Positioned(
                left: 12,
                right: 12,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '▶ DESCUBRIR',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFFFD95E),
                      letterSpacing: 3,
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

  List<Widget> _buildSparkles() {
    // 5 small sparkles at random positions for the bonus face.
    return List.generate(5, (i) {
      final left = 20.0 + (i * 35) % 180;
      final top = 30.0 + (i * 47) % 280;
      return Positioned(
        left: left.toDouble(),
        top: top.toDouble(),
        child: Text(
          '✦',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10 + (i % 3) * 4,
          ),
        ),
      );
    });
  }
}

/// Texto "???" con efecto glitch RGB (3 capas magenta + cyan + main).
class _GlitchText extends StatelessWidget {
  const _GlitchText({
    required this.text,
    required this.offsetX,
    required this.offsetY,
  });

  final String text;
  final double offsetX;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontSize: 64,
      fontWeight: FontWeight.w900,
      fontFamily: 'sans-serif',
      letterSpacing: 4,
      height: 1.0,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: Offset(-2 + offsetX, offsetY),
          child: Text(text,
              style: baseStyle.copyWith(
                color: const Color(0xFFFF2BD6).withValues(alpha: 0.85),
              )),
        ),
        Transform.translate(
          offset: Offset(2 - offsetX, -offsetY),
          child: Text(text,
              style: baseStyle.copyWith(
                color: const Color(0xFF00F0FF).withValues(alpha: 0.85),
              )),
        ),
        Text(
          text,
          style: baseStyle.copyWith(
            color: const Color(0xFF00F0FF),
            shadows: [
              Shadow(
                color: const Color(0xFF00F0FF).withValues(alpha: 0.7),
                blurRadius: 20,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Rejilla synthwave 3D (perspectiva al piso) para la mystery card.
class _SynthwaveGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F0FF).withValues(alpha: 0.15)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final gridTop = size.height * 0.55;
    final horizon = gridTop;
    final bottom = size.height;
    final centerX = size.width / 2;
    const nHorizontal = 8;
    for (var i = 0; i <= nHorizontal; i++) {
      final t = i / nHorizontal;
      final easedT = t * t;
      final y = bottom - (bottom - horizon) * (1 - easedT);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    const nVertical = 12;
    for (var i = 0; i <= nVertical; i++) {
      final t = i / nVertical;
      final bottomX = size.width * t;
      canvas.drawLine(
        Offset(bottomX, bottom),
        Offset(centerX, horizon),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Foil holographic sweep para la bonus card.
class _FoilSweepPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: 0.35),
        Colors.white.withValues(alpha: 0),
      ],
      stops: const [0.35, 0.5, 0.65],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_) => false;
}
