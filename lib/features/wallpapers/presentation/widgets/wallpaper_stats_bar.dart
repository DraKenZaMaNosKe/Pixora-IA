import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/services/wallpaper_stats_service.dart';

/// Compact stats bar with like button, views, downloads — for wallpaper cards.
class WallpaperStatsBar extends StatefulWidget {
  final String wallpaperId;
  final Color glowColor;

  const WallpaperStatsBar({
    super.key,
    required this.wallpaperId,
    required this.glowColor,
  });

  @override
  State<WallpaperStatsBar> createState() => _WallpaperStatsBarState();
}

class _WallpaperStatsBarState extends State<WallpaperStatsBar>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final WallpaperStatsService _service;
  StreamSubscription? _sub;
  Map<String, int> _stats = {'likes': 0, 'downloads': 0, 'views': 0};
  bool _liked = false;

  // Like tap animation
  AnimationController? _likeController;
  // Particle explosion
  AnimationController? _particleController;
  bool _showParticles = false;
  // Counter bump
  AnimationController? _bumpController;
  int _prevLikes = 0;
  // Heartbeat pulse (always running)
  AnimationController? _heartbeatController;

  @override
  void initState() {
    super.initState();
    _service = WallpaperStatsService.instance;
    _stats = _service.getStats(widget.wallpaperId);
    _liked = _service.hasLiked(widget.wallpaperId);
    _prevLikes = _stats['likes'] ?? 0;

    _likeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _bumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Heartbeat: continuous pulse to attract taps
    _heartbeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);

    // Listen for realtime updates
    _sub = _service.statsStream.listen((allStats) {
      final newStats = allStats[widget.wallpaperId];
      if (newStats != null && mounted) {
        final newLikes = newStats['likes'] ?? 0;
        if (newLikes != _prevLikes) {
          _bumpController?.forward(from: 0);
          _prevLikes = newLikes;
        }
        setState(() => _stats = newStats);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _heartbeatController?.stop();
    } else if (state == AppLifecycleState.resumed) {
      _heartbeatController?.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _likeController?.dispose();
    _particleController?.dispose();
    _bumpController?.dispose();
    _heartbeatController?.dispose();
    super.dispose();
  }

  Future<void> _onLikeTap() async {
    _likeController?.forward(from: 0);

    if (!_liked) {
      setState(() => _showParticles = true);
      _particleController?.forward(from: 0).then((_) {
        if (mounted) setState(() => _showParticles = false);
      });
    }

    final nowLiked = await _service.toggleLike(widget.wallpaperId);
    if (mounted) {
      setState(() {
        _liked = nowLiked;
        _stats = _service.getStats(widget.wallpaperId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final likes = _stats['likes'] ?? 0;
    final downloads = _stats['downloads'] ?? 0;
    final views = _stats['views'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Like button (heart) — RED, pulsing
          GestureDetector(
            onTap: _onLikeTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 36,
              height: 20,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  // Particles
                  if (_showParticles)
                    Positioned(
                      left: -4,
                      top: -10,
                      child: _LikeParticles(
                        controller: _particleController!,
                        color: Colors.red,
                      ),
                    ),
                  // Heart icon — red, pulsing heartbeat
                  AnimatedBuilder(
                    animation: Listenable.merge([_likeController!, _heartbeatController!]),
                    builder: (_, __) {
                      // Tap bounce
                      final tapScale = 1.0 +
                          0.4 * Curves.elasticOut.transform(_likeController!.value);
                      // Heartbeat pulse (subtle when not liked, stronger when liked)
                      final beatPhase = Curves.easeInOut.transform(_heartbeatController!.value);
                      final beatScale = _liked
                          ? 1.0 + 0.08 * beatPhase
                          : 1.0 + 0.12 * beatPhase; // stronger pulse when NOT liked to attract
                      return Transform.scale(
                        scale: tapScale * beatScale,
                        child: Icon(
                          _liked ? Icons.favorite : Icons.favorite,
                          size: 14,
                          color: _liked
                              ? Colors.red
                              : Colors.red.withOpacity(0.7),
                        ),
                      );
                    },
                  ),
                  // Like count
                  Positioned(
                    right: 0,
                    child: AnimatedBuilder(
                      animation: _bumpController!,
                      builder: (_, __) {
                        final bump = Curves.elasticOut.transform(_bumpController!.value);
                        return Transform.scale(
                          scale: 1.0 + 0.2 * bump,
                          child: Text(
                            WallpaperStatsService.formatCount(likes),
                            style: TextStyle(
                              fontSize: 9,
                              color: _liked ? Colors.red : Colors.white.withOpacity(0.7),
                              fontWeight: _liked ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Views
          Icon(Icons.visibility, size: 10, color: Colors.white.withOpacity(0.5)),
          const SizedBox(width: 2),
          Text(
            WallpaperStatsService.formatCount(views),
            style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(width: 4),
          // Downloads
          Icon(Icons.download, size: 10, color: Colors.white.withOpacity(0.5)),
          const SizedBox(width: 2),
          Text(
            WallpaperStatsService.formatCount(downloads),
            style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.5)),
          ),
        ],
      ),
    );
  }
}

/// Particle explosion effect when liking.
class _LikeParticles extends StatelessWidget {
  final AnimationController controller;
  final Color color;

  const _LikeParticles({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final progress = controller.value;
        final opacity = (1.0 - progress).clamp(0.0, 1.0);

        return SizedBox(
          width: 40,
          height: 40,
          child: CustomPaint(
            painter: _ParticlePainter(
              progress: progress,
              opacity: opacity,
              color: color,
            ),
          ),
        );
      },
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double progress;
  final double opacity;
  final Color color;

  _ParticlePainter({
    required this.progress,
    required this.opacity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rng = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * math.pi * 2 + rng.nextDouble() * 0.5;
      final distance = 8 + 18 * progress + rng.nextDouble() * 8 * progress;
      final radius = (2.5 - 2.0 * progress).clamp(0.3, 2.5);

      final particleColor = i % 3 == 0
          ? color
          : i % 3 == 1
              ? Colors.pink.shade200
              : Colors.white;

      paint.color = particleColor.withOpacity(opacity * 0.8);

      canvas.drawCircle(
        Offset(
          center.dx + math.cos(angle) * distance,
          center.dy + math.sin(angle) * distance,
        ),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.progress != progress || old.opacity != opacity;
}
