import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// First-launch welcome flow — Pixora's "carta de presentación".
///
/// Redesigned 2026-07-14 for the Vitrina navigation: 8 full-bleed slides on a
/// dark cosmic canvas, premium Grok artwork per pillar, and a **Perilla** slide
/// (#2) that teaches the rotary-dial navigation before the user lands on the
/// gesture-only home. The progress indicator is a notched arc that mimics the
/// dial itself — every advance reads as one "click" of the knob.
///
/// Show with `OnboardingPage.shouldShow()`; call `OnboardingPage.markSeen()`
/// (done internally) when the user finishes or skips.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onFinish});

  /// Fired when the user finishes (¡Comenzar!) or skips. Receives the active
  /// OnboardingPage context (the splash context is already unmounted).
  final void Function(BuildContext context) onFinish;

  static const _hiveBox = 'pixora_settings';
  // v2 bump — the redesign changed the whole flow, so returning users who
  // saw the old tutorial get the new one once.
  static const _hiveKey = 'onboarding_seen_v2';

  static Future<bool> shouldShow() async {
    try {
      final box = await Hive.openBox(_hiveBox);
      return !(box.get(_hiveKey, defaultValue: false) as bool);
    } catch (_) {
      return false; // never block launch on a Hive hiccup
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

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  int _index = 0;
  late final AnimationController _floatCtrl;

  // ── Palette (fixed dark-cosmic brand look, independent of app theme) ──
  static const _bg = Color(0xFF0E0E13);
  static const _bg2 = Color(0xFF17131E);
  static const _stage = Color(0xFF05050A);
  static const _gold = Color(0xFFD4AF37);
  static const _goldLt = Color(0xFFF4D774);
  static const _goldDp = Color(0xFFA67C1A);
  static const _dim = Color(0xFF9A9080);

  static const _slides = <_SlideData>[
    _SlideData(
      image: 'assets/onboarding/01_bienvenida.webp',
      accent: Color(0xFF6AA9FF),
      kicker: 'BIENVENIDO A PIXORA',
      titlePre: 'Tu pantalla, ',
      titleHl: 'viva',
      body:
          'Miles de wallpapers, sonidos y experiencias que cobran vida. Prepárate para presumir tu teléfono.',
    ),
    _SlideData(
      isDial: true,
      accent: Color(0xFFF4D774),
      kicker: 'LO PRIMERO',
      titlePre: 'Gira la ',
      titleHl: 'perilla',
      body:
          'Desliza la ruedita dorada del borde y salta entre secciones al instante. Una mano, todo Pixora.',
    ),
    _SlideData(
      image: 'assets/onboarding/02_wallpapers.webp',
      accent: Color(0xFF7FB3FF),
      kicker: 'GALERÍA INFINITA',
      titlePre: 'Fondos de ',
      titleHl: 'otro nivel',
      body:
          'Cientos de wallpapers en alta resolución, curados uno por uno. Aplícalos a inicio, bloqueo o ambos.',
    ),
    _SlideData(
      image: 'assets/onboarding/03_live.webp',
      accent: Color(0xFFFF5A47),
      kicker: 'EN MOVIMIENTO',
      titlePre: 'Que ',
      titleHl: 'cobren vida',
      body:
          'Wallpapers animados que reaccionan a tu toque. Tu pantalla nunca se queda quieta.',
    ),
    _SlideData(
      image: 'assets/onboarding/04_parallax.webp',
      accent: Color(0xFFB15CE0),
      kicker: 'PROFUNDIDAD REAL',
      titlePre: 'Un mundo en ',
      titleHl: '3D',
      body:
          'Inclina el teléfono y las capas se mueven contigo. Un efecto parallax que hipnotiza.',
    ),
    _SlideData(
      image: 'assets/onboarding/05_cultura.webp',
      accent: Color(0xFFE0A24A),
      kicker: 'CON HISTORIA',
      titlePre: 'Arte que ',
      titleHl: 'enseña',
      body:
          'Cada fondo trae su relato: mitología, símbolos y datos. Decora tu pantalla y aprende algo nuevo.',
    ),
    _SlideData(
      image: 'assets/onboarding/06_aura.webp',
      accent: Color(0xFF46C7E0),
      kicker: 'TU MOMENTO ZEN',
      titlePre: 'Relaja y ',
      titleHl: 'duerme mejor',
      body:
          'Frecuencias y sonidos de naturaleza para concentrarte o dormir. Con temporizador integrado.',
    ),
    _SlideData(
      image: 'assets/onboarding/07_arcano.webp',
      accent: Color(0xFF8AA0D8),
      kicker: 'ESCRITO EN LAS ESTRELLAS',
      titlePre: 'La ',
      titleHl: 'luna',
      titlePost: ' en tu pantalla',
      body:
          'Un wallpaper que cambia con la fase real de la luna y tu signo del zodiaco. Empieza tu viaje.',
    ),
  ];

  int get _count => _slides.length;
  bool get _isLast => _index == _count - 1;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finish() async {
    await OnboardingPage.markSeen();
    if (mounted) widget.onFinish(context);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _slides[_index].accent;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // dark bg → light icons
        statusBarBrightness: Brightness.dark, // iOS
      ),
      child: Scaffold(
        backgroundColor: _stage,
        body: Stack(
          children: [
            // Cosmic backdrop tinted subtly by the active slide's accent.
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.75),
                    radius: 1.2,
                    colors: [
                      Color.lerp(_bg2, accent, 0.10)!,
                      _bg,
                      _stage,
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
                child: CustomPaint(painter: _StarfieldPainter()),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // Skip (hidden on last slide)
                  Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedOpacity(
                      opacity: _isLast ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: TextButton(
                        onPressed: _isLast ? null : _finish,
                        child: Text('Saltar',
                            style: GoogleFonts.inter(
                                color: _dim,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemCount: _count,
                      itemBuilder: (_, i) => _SlideView(
                        data: _slides[i],
                        floatCtrl: _floatCtrl,
                      ),
                    ),
                  ),
                  // Signature: dial-arc progress
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: SizedBox(
                      width: 220,
                      height: 52,
                      child: CustomPaint(
                        painter: _DialProgressPainter(
                          count: _count,
                          index: _index,
                          accent: accent,
                          gold: _gold,
                        ),
                      ),
                    ),
                  ),
                  Text('GIRA PARA AVANZAR',
                      style: GoogleFonts.jetBrainsMono(
                          color: _dim.withValues(alpha: 0.5),
                          fontSize: 9,
                          letterSpacing: 3)),
                  // CTA
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 14, 26, 22),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_goldLt, _gold, _goldDp],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _gold.withValues(alpha: 0.35),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _next,
                            child: Center(
                              child: Text(
                                _isLast ? '¡Comenzar!' : 'Siguiente',
                                style: GoogleFonts.fraunces(
                                  color: const Color(0xFF201803),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
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
            ),
          ],
        ),
      ),
    );
  }
}

// ── Slide data ──────────────────────────────────────────────────────────────
class _SlideData {
  const _SlideData({
    this.image,
    this.isDial = false,
    required this.accent,
    required this.kicker,
    required this.titlePre,
    required this.titleHl,
    this.titlePost = '',
    required this.body,
  });

  final String? image;
  final bool isDial;
  final Color accent;
  final String kicker;
  final String titlePre;
  final String titleHl;
  final String titlePost;
  final String body;
}

// ── One slide ───────────────────────────────────────────────────────────────
class _SlideView extends StatelessWidget {
  const _SlideView({required this.data, required this.floatCtrl});
  final _SlideData data;
  final AnimationController floatCtrl;

  static const _ink = Color(0xFFF5F1E6);
  static const _dim = Color(0xFF9A9080);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // Hero art with accent glow + gentle float
          AspectRatio(
            aspectRatio: 1,
            child: FractionallySizedBox(
              widthFactor: 0.82,
              child: AnimatedBuilder(
                animation: floatCtrl,
                builder: (context, child) {
                  final dy = reduce
                      ? 0.0
                      : math.sin(floatCtrl.value * 2 * math.pi) * 7;
                  return Transform.translate(
                      offset: Offset(0, -dy), child: child);
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        data.accent.withValues(alpha: 0.30),
                        Colors.transparent,
                      ],
                      stops: const [0.35, 0.72],
                    ),
                  ),
                  child: data.isDial
                      ? CustomPaint(
                          painter: _DialKnobPainter(accent: data.accent))
                      : _MaskedArt(image: data.image!),
                ),
              ),
            ),
          ),
          const Spacer(flex: 1),
          // Kicker
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('◈ ', style: TextStyle(color: data.accent, fontSize: 10)),
              Text(
                data.kicker,
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFFD4AF37),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Title with highlighted keyword
          Text.rich(
            TextSpan(
              style: GoogleFonts.fraunces(
                fontSize: 31,
                height: 1.07,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                color: _ink,
                letterSpacing: -0.3,
              ),
              children: [
                TextSpan(text: data.titlePre),
                TextSpan(
                  text: data.titleHl,
                  style: TextStyle(
                      color: data.accent, fontWeight: FontWeight.w700),
                ),
                if (data.titlePost.isNotEmpty) TextSpan(text: data.titlePost),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          // Body
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: _dim, fontSize: 14, height: 1.6),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

/// Grok artwork with soft radial edge-fade so the square blends into the canvas.
class _MaskedArt extends StatelessWidget {
  const _MaskedArt({required this.image});
  final String image;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const RadialGradient(
        center: Alignment(0, -0.04),
        radius: 0.62,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.78, 1],
      ).createShader(rect),
      child: Image.asset(image,
          fit: BoxFit.contain, filterQuality: FilterQuality.medium),
    );
  }
}

// ── Painters ────────────────────────────────────────────────────────────────

/// The Perilla — a gold rotary knob with radial notches + a turn arrow.
class _DialKnobPainter extends CustomPainter {
  _DialKnobPainter({required this.accent});
  final Color accent;

  static const _gold = Color(0xFFD4AF37);
  static const _goldLt = Color(0xFFF4D774);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.33;

    // notches
    final notch = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 24; i++) {
      final a = i / 24 * 2 * math.pi;
      final r1 = r * 1.18, r2 = r * 1.33;
      notch.color = accent.withValues(alpha: i % 6 == 0 ? 1 : 0.4);
      canvas.drawLine(
        c + Offset(math.cos(a) * r1, math.sin(a) * r1),
        c + Offset(math.cos(a) * r2, math.sin(a) * r2),
        notch,
      );
    }

    // body with radial gradient
    final body = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.2, -0.3),
        radius: 0.9,
        colors: [_goldLt, _gold, Color(0xFF2A2415)],
        stops: [0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, body);

    // inner groove
    canvas.drawCircle(
        c,
        r * 0.7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = const Color(0x55000000));
    canvas.drawCircle(c, r * 0.15, Paint()..color = const Color(0xFF1A1712));

    // index pointer (top)
    final ptr = Path()
      ..moveTo(c.dx, c.dy - r * 0.72)
      ..lineTo(c.dx - 7, c.dy - r * 0.42)
      ..lineTo(c.dx + 7, c.dy - r * 0.42)
      ..close();
    canvas.drawPath(ptr, Paint()..color = accent);

    // turn arrow (bottom-right)
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = _goldLt;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.82), 0,
        math.pi * 0.5, false, arc);
    final ah = c +
        Offset(math.cos(math.pi * 0.5) * r * 0.82,
            math.sin(math.pi * 0.5) * r * 0.82);
    final head = Path()
      ..moveTo(ah.dx, ah.dy)
      ..lineTo(ah.dx - 9, ah.dy + 3)
      ..lineTo(ah.dx - 2, ah.dy + 12)
      ..close();
    canvas.drawPath(head, Paint()..color = _goldLt);
  }

  @override
  bool shouldRepaint(covariant _DialKnobPainter old) => old.accent != accent;
}

/// Signature progress: a notched arc (like the dial) that fills as you advance;
/// the active tick sits on a pointer swung from the hub — one "click" per step.
class _DialProgressPainter extends CustomPainter {
  _DialProgressPainter({
    required this.count,
    required this.index,
    required this.accent,
    required this.gold,
  });
  final int count;
  final int index;
  final Color accent;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final hub = Offset(size.width / 2, size.height * 0.92);
    final r = size.width * 0.42;
    const start = math.pi * 1.18, end = math.pi * 1.82;

    // guide arc
    canvas.drawArc(
      Rect.fromCircle(center: hub, radius: r),
      start,
      end - start,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF3A3527),
    );
    canvas.drawCircle(hub, 4, Paint()..color = const Color(0xFF5A5240));

    for (var i = 0; i < count; i++) {
      final t = count == 1 ? 0.0 : i / (count - 1);
      final a = start + (end - start) * t;
      final p = hub + Offset(math.cos(a) * r, math.sin(a) * r);
      final done = i <= index;
      if (i == index) {
        // pointer from hub + halo ring
        final k = hub + Offset(math.cos(a) * (r - 15), math.sin(a) * (r - 15));
        canvas.drawLine(
            hub,
            k,
            Paint()
              ..strokeWidth = 2.5
              ..strokeCap = StrokeCap.round
              ..color = accent.withValues(alpha: 0.8));
        canvas.drawCircle(
            p,
            11,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = accent.withValues(alpha: 0.5));
        canvas.drawCircle(p, 6.5, Paint()..color = accent);
      } else {
        canvas.drawCircle(
            p, 3.4, Paint()..color = done ? gold : const Color(0xFF4A4433));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DialProgressPainter old) =>
      old.index != index || old.accent != accent;
}

/// Faint fixed starfield — deterministic so it doesn't shimmer on rebuild.
class _StarfieldPainter extends CustomPainter {
  static final _stars = <Offset>[
    const Offset(0.20, 0.12),
    const Offset(0.68, 0.09),
    const Offset(0.84, 0.22),
    const Offset(0.32, 0.30),
    const Offset(0.12, 0.44),
    const Offset(0.90, 0.40),
    const Offset(0.50, 0.18),
    const Offset(0.74, 0.52),
    const Offset(0.08, 0.62),
    const Offset(0.42, 0.58),
    const Offset(0.60, 0.68),
    const Offset(0.26, 0.72),
    const Offset(0.88, 0.66),
    const Offset(0.16, 0.28),
    const Offset(0.56, 0.36),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white;
    for (var i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      p.color = Colors.white.withValues(alpha: 0.10 + (i % 4) * 0.05);
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height),
          1.0 + (i % 3) * 0.4, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) => false;
}
