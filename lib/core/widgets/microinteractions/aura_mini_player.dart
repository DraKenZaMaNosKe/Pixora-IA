import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// M11 — AURA Mini Player Floating.
///
/// Mini widget que muestra qué AURA está sonando en background. Cover
/// pulsante (respiración), título, barra de progreso, botón play/pause.
/// Inspirado en Spotify mini player. Drop al bottom de cualquier scaffold.
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M11).
class AuraMiniPlayer extends StatefulWidget {
  const AuraMiniPlayer({
    super.key,
    required this.title,
    required this.progress,
    required this.isPlaying,
    required this.onPlayPause,
    this.onTap,
  });

  final String title;
  final double progress; // 0.0 .. 1.0
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback? onTap;

  @override
  State<AuraMiniPlayer> createState() => _AuraMiniPlayerState();
}

class _AuraMiniPlayerState extends State<AuraMiniPlayer>
    with SingleTickerProviderStateMixin {
  static const Color _violet = Color(0xFF9D4EDD);
  static const Color _rose = Color(0xFFFF5A8E);

  late final AnimationController _breathCtrl;

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    if (widget.isPlaying) _breathCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AuraMiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_breathCtrl.isAnimating) {
      _breathCtrl.repeat(reverse: true);
    } else if (!widget.isPlaying && _breathCtrl.isAnimating) {
      _breathCtrl.stop();
    }
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A0E2A), Color(0xFF0A0612)],
            ),
            border: Border.all(color: _violet.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _breathCtrl,
                builder: (_, __) {
                  final scale = 1.0 + (_breathCtrl.value * 0.08);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: const RadialGradient(
                          colors: [_violet, _rose],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _violet.withValues(alpha: 0.5),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fraunces(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        height: 2,
                        color: Colors.white.withValues(alpha: 0.1),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: widget.progress.clamp(0.0, 1.0),
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [_violet, _rose],
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
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onPlayPause,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                icon: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _rose,
                  ),
                  child: Icon(
                    widget.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 14,
                    color: Colors.white,
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
