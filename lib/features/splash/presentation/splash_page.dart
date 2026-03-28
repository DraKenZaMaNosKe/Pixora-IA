import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/services/catalog_service.dart';
import '../../home/presentation/home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _exitController;
  bool _loadingDone = false;
  bool _minTimeDone = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _preload();

    Future.delayed(const Duration(milliseconds: 3000), () {
      _minTimeDone = true;
      _navigateIfReady();
    });
  }

  Future<void> _preload() async {
    try {
      await CatalogService.instance.fetchCatalog();
    } catch (_) {}
    _loadingDone = true;
    _navigateIfReady();
  }

  void _navigateIfReady() {
    if (_loadingDone && _minTimeDone && !_exiting && mounted) {
      _exiting = true;
      _exitController.forward().then((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const HomePage(),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
              transitionDuration: const Duration(milliseconds: 500),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      body: AnimatedBuilder(
        animation: Listenable.merge([_controller, _exitController]),
        builder: (context, _) {
          final exitOpacity = 1.0 - _exitController.value;
          return Opacity(
            opacity: exitOpacity,
            child: CustomPaint(
              painter: _SplashShaderPainter(
                time: _controller.value * 10,
                entryProgress: min(1.0, _controller.value * 10 / 2.0),
              ),
              size: Size.infinite,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // "P" letter with shader-like glow
                    _buildLogo(),
                    const SizedBox(height: 16),
                    // "Pixora IA" text
                    _buildTitle(),
                    const SizedBox(height: 50),
                    // Loading dots
                    _buildLoadingDots(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogo() {
    final t = _controller.value * 10;
    final glow = (sin(t * 1.5) * 0.3 + 0.7);
    final entry = min(1.0, t / 1.5);
    final scale = 0.5 + entry * 0.5;

    return Opacity(
      opacity: entry,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C4DFF).withOpacity(0.5 * glow),
                blurRadius: 40 * glow,
                spreadRadius: 5 * glow,
              ),
              BoxShadow(
                color: const Color(0xFF00B4D8).withOpacity(0.3 * glow),
                blurRadius: 60 * glow,
                spreadRadius: 10 * glow,
              ),
            ],
          ),
          child: Center(
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(const Color(0xFF7C4DFF), const Color(0xFF00B4D8), (sin(t * 0.8) * 0.5 + 0.5))!,
                  Color.lerp(const Color(0xFF00B4D8), const Color(0xFF7C4DFF), (sin(t * 0.8) * 0.5 + 0.5))!,
                ],
              ).createShader(bounds),
              child: const Text(
                'P',
                style: TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    final t = _controller.value * 10;
    final entry = max(0.0, min(1.0, (t - 0.8) / 1.0));

    return Opacity(
      opacity: entry,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - entry)),
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF7C4DFF), Color(0xFF00B4D8), Color(0xFF7C4DFF)],
          ).createShader(bounds),
          child: const Text(
            'Pixora IA',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingDots() {
    final t = _controller.value * 10;
    final entry = max(0.0, min(1.0, (t - 1.5) / 0.5));

    return Opacity(
      opacity: entry * 0.6,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final dotPhase = sin(t * 3 - i * 0.8) * 0.5 + 0.5;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(
                const Color(0xFF7C4DFF),
                const Color(0xFF00B4D8),
                dotPhase,
              )!.withOpacity(0.4 + dotPhase * 0.6),
            ),
          );
        }),
      ),
    );
  }
}

/// Custom painter that creates shader-like background effects
class _SplashShaderPainter extends CustomPainter {
  final double time;
  final double entryProgress;
  final Random _rng = Random(42);
  final List<_Particle> _particles = [];

  _SplashShaderPainter({required this.time, required this.entryProgress}) {
    if (_particles.isEmpty) {
      for (var i = 0; i < 60; i++) {
        _particles.add(_Particle(
          x: _rng.nextDouble(),
          y: _rng.nextDouble(),
          speed: 0.2 + _rng.nextDouble() * 0.8,
          size: 1 + _rng.nextDouble() * 3,
          phase: _rng.nextDouble() * pi * 2,
          color: _rng.nextBool() ? 0 : 1, // 0=purple, 1=cyan
        ));
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2 - 30;

    // Dark background with subtle radial gradient
    final bgPaint = Paint();
    bgPaint.shader = ui.Gradient.radial(
      Offset(cx, cy),
      w * 0.8,
      [
        const Color(0xFF0D0D15),
        const Color(0xFF050508),
      ],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // Energy rings expanding from center
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (var i = 0; i < 3; i++) {
      final ringProgress = ((time * 0.3 + i * 0.33) % 1.0);
      final radius = ringProgress * w * 0.6;
      final alpha = ((1 - ringProgress) * 0.15 * entryProgress * 255).toInt().clamp(0, 255);
      if (alpha <= 0) continue;

      ringPaint.color = i % 2 == 0
          ? Color.fromARGB(alpha, 124, 77, 255)
          : Color.fromARGB(alpha, 0, 180, 216);
      canvas.drawCircle(Offset(cx, cy), radius, ringPaint);
    }

    // Floating particles
    final particlePaint = Paint();
    for (final p in _particles) {
      final px = p.x * w;
      final py = p.y * h;

      // Drift upward and wobble
      final drift = (time * p.speed * 0.1) % 1.0;
      final wobble = sin(time * 2 + p.phase) * 15;
      final finalY = (py - drift * h) % h;
      final finalX = px + wobble;

      // Distance from center affects brightness
      final dx = finalX - cx;
      final dy = finalY - cy;
      final dist = sqrt(dx * dx + dy * dy);
      final distFade = max(0.0, 1 - dist / (w * 0.5));

      final alpha = (distFade * 0.8 * entryProgress * 255).toInt().clamp(0, 255);
      if (alpha <= 0) continue;

      final baseColor = p.color == 0
          ? Color.fromARGB(alpha, 124, 77, 255)
          : Color.fromARGB(alpha, 0, 180, 216);

      // Glow
      particlePaint.color = baseColor.withOpacity(baseColor.opacity * 0.3);
      canvas.drawCircle(Offset(finalX, finalY), p.size * 4, particlePaint);

      // Core
      particlePaint.color = baseColor;
      canvas.drawCircle(Offset(finalX, finalY), p.size, particlePaint);
    }

    // Central nebula glow
    final nebulaPaint = Paint();
    final nebulaBreath = sin(time * 1.2) * 0.15 + 0.85;
    nebulaPaint.shader = ui.Gradient.radial(
      Offset(cx, cy),
      w * 0.25 * nebulaBreath,
      [
        Color.fromARGB((30 * entryProgress).toInt(), 124, 77, 255),
        Color.fromARGB((15 * entryProgress).toInt(), 0, 180, 216),
        const Color(0x00000000),
      ],
      [0.0, 0.5, 1.0],
    );
    canvas.drawCircle(Offset(cx, cy), w * 0.25 * nebulaBreath, nebulaPaint);

    // Subtle scan line effect
    final scanPaint = Paint()
      ..color = Color.fromARGB((8 * entryProgress).toInt(), 255, 255, 255);
    final scanY = ((time * 0.15) % 1.0) * h;
    canvas.drawRect(
      Rect.fromLTWH(0, scanY, w, 2),
      scanPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SplashShaderPainter oldDelegate) => true;
}

class _Particle {
  final double x, y, speed, size, phase;
  final int color;
  const _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.phase,
    required this.color,
  });
}
