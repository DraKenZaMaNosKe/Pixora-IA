import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/services/wallpaper_stats_service.dart';

/// Single shared heartbeat that all stats bars listen to.
///
/// Uses a standalone [Ticker] (not tied to any widget's vsync) so stats-bar
/// widgets can be disposed in any order without leaving the controller bound
/// to a dead TickerProvider. The ticker starts when the first listener is
/// added and stops when the last one is removed — auto-pauses CPU when no
/// stats bars are on screen.
class _GlobalHeartbeat {
  static _GlobalHeartbeat? _instance;
  static _GlobalHeartbeat get instance => _instance ??= _GlobalHeartbeat._();

  _GlobalHeartbeat._();

  Ticker? _ticker;
  final _listeners = <VoidCallback>{};

  /// 0→1→0 triangle wave on a 2400 ms period (matches the old
  /// AnimationController(1200ms, reverse: true) shape).
  double _value = 0.0;
  double get value => _value;

  void _onTick(Duration elapsed) {
    final t = (elapsed.inMilliseconds % 2400) / 1200.0;
    _value = t <= 1.0 ? t : 2.0 - t;
    for (final cb in _listeners) {
      cb();
    }
  }

  void addListener(VoidCallback cb) {
    _listeners.add(cb);
    if (_ticker == null) {
      _ticker = Ticker(_onTick, debugLabel: 'GlobalHeartbeat')..start();
    }
  }

  void removeListener(VoidCallback cb) {
    _listeners.remove(cb);
    if (_listeners.isEmpty) {
      _ticker?.dispose();
      _ticker = null;
      _value = 0.0;
    }
  }
}

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
    with TickerProviderStateMixin {
  late final WallpaperStatsService _service;
  StreamSubscription? _sub;
  Map<String, int> _stats = {'likes': 0, 'downloads': 0, 'views': 0};
  bool _liked = false;

  AnimationController? _likeController;
  AnimationController? _particleController;
  AnimationController? _bumpController;
  bool _showParticles = false;
  int _prevLikes = 0;

  late final VoidCallback _heartbeatCb;

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

    _heartbeatCb = () {
      if (mounted) setState(() {});
    };
    _GlobalHeartbeat.instance.addListener(_heartbeatCb);

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
  void dispose() {
    _GlobalHeartbeat.instance.removeListener(_heartbeatCb);
    _sub?.cancel();
    _likeController?.dispose();
    _particleController?.dispose();
    _bumpController?.dispose();
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
    final h = context.hud;
    final likes = _stats['likes'] ?? 0;
    final downloads = _stats['downloads'] ?? 0;
    final views = _stats['views'] ?? 0;
    final beatPhase =
        Curves.easeInOut.transform(_GlobalHeartbeat.instance.value);
    // iOS: light blurred pill on white bg. Black & Gold: dark pill.
    final pillBg = h.isIosStyle
        ? Colors.white.withValues(alpha: 0.85)
        : Colors.black.withValues(alpha: 0.55);
    final iconColor =
        h.isIosStyle ? h.textDim : Colors.white.withValues(alpha: 0.5);
    final likeColor = h.isIosStyle
        ? const Color(0xFFFF3B30) // iOS system red for liked heart
        : HudTokens.goldDeep;
    final likeIdleColor =
        h.isIosStyle ? h.textDim : HudTokens.goldDeep.withValues(alpha: 0.7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                  if (_showParticles)
                    Positioned(
                      left: -4,
                      top: -10,
                      child: _LikeParticles(
                        controller: _particleController!,
                        color: likeColor,
                      ),
                    ),
                  AnimatedBuilder(
                    animation: _likeController!,
                    builder: (_, __) {
                      final tapScale = 1.0 +
                          0.4 *
                              Curves.elasticOut
                                  .transform(_likeController!.value);
                      final beatScale = _liked
                          ? 1.0 + 0.08 * beatPhase
                          : 1.0 + 0.12 * beatPhase;
                      return Transform.scale(
                        scale: tapScale * beatScale,
                        child: Icon(
                          Icons.favorite,
                          size: 14,
                          color: _liked ? likeColor : likeIdleColor,
                        ),
                      );
                    },
                  ),
                  Positioned(
                    right: 0,
                    child: AnimatedBuilder(
                      animation: _bumpController!,
                      builder: (_, __) {
                        final bump =
                            Curves.elasticOut.transform(_bumpController!.value);
                        return Transform.scale(
                          scale: 1.0 + 0.2 * bump,
                          child: Text(
                            WallpaperStatsService.formatCount(likes),
                            style: TextStyle(
                              fontSize: 9,
                              color: _liked ? likeColor : iconColor,
                              fontWeight:
                                  _liked ? FontWeight.bold : FontWeight.normal,
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
          Icon(Icons.visibility, size: 10, color: iconColor),
          const SizedBox(width: 2),
          Text(
            WallpaperStatsService.formatCount(views),
            style: TextStyle(fontSize: 9, color: iconColor),
          ),
          const SizedBox(width: 4),
          Icon(Icons.download, size: 10, color: iconColor),
          const SizedBox(width: 2),
          Text(
            WallpaperStatsService.formatCount(downloads),
            style: TextStyle(fontSize: 9, color: iconColor),
          ),
        ],
      ),
    );
  }
}

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
              ? HudTokens.gold
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
