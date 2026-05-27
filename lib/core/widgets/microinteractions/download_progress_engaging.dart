import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// M01 — Download Progress Engaging.
///
/// Preview de wallpaper que mientras descarga:
///   • Empieza como skeleton (sin imagen)
///   • A medida que avanza el progreso, la imagen real aparece desenfocada
///     y se va aclarando (blur 20px → 0px lerp con progress)
///   • Una barra dorada con bytes/total debajo
///
/// El usuario "ve" el wallpaper llegando en vez de un spinner vacío. La
/// espera se siente más corta y satisfactoria.
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M01).
class DownloadProgressEngaging extends StatelessWidget {
  const DownloadProgressEngaging({
    super.key,
    required this.imageUrl,
    required this.progress,
    this.bytesDownloaded,
    this.bytesTotal,
    this.aspectRatio = 9 / 16,
  });

  final String imageUrl;
  final double progress; // 0.0 .. 1.0
  final int? bytesDownloaded;
  final int? bytesTotal;
  final double aspectRatio;

  static const Color _amber = Color(0xFFFFB400);
  static const Color _amberBright = Color(0xFFFFD66B);

  String _fmtBytes(int? b) {
    if (b == null) return '—';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final blurSigma = (1.0 - p) * 20;
    final imageOpacity = (p * 1.5).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Preview con imagen blurreada según progreso
        AspectRatio(
          aspectRatio: aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Skeleton base
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2A1818), Color(0xFF0A0612)],
                    ),
                  ),
                ),
                // Imagen real, aparece progresivamente
                if (p > 0.1)
                  Opacity(
                    opacity: imageOpacity,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: blurSigma,
                        sigmaY: blurSigma,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 540,
                      ),
                    ),
                  ),
                // Shimmer overlay diagonal (sutil)
                Positioned.fill(
                  child: _ShimmerOverlay(active: p < 0.95),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Bar de progreso
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 4,
            color: _amber.withValues(alpha: 0.1),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: p,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: const LinearGradient(
                      colors: [_amber, _amberBright],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _amber.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Stat line
        DefaultTextStyle(
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: _amber.withValues(alpha: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(p < 1.0 ? 'DESCARGANDO...' : 'LISTO'),
              if (bytesTotal != null)
                Text(
                  '${_fmtBytes(bytesDownloaded)} / ${_fmtBytes(bytesTotal)}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _amberBright,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShimmerOverlay extends StatefulWidget {
  const _ShimmerOverlay({required this.active});
  final bool active;
  @override
  State<_ShimmerOverlay> createState() => _ShimmerOverlayState();
}

class _ShimmerOverlayState extends State<_ShimmerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_ShimmerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final shift = _ctrl.value * 2 - 0.5;
        return IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1 + shift, -0.5),
                end: Alignment(1 + shift, 0.5),
                colors: const [
                  Colors.transparent,
                  Color(0x1AFFB400),
                  Colors.transparent,
                ],
                stops: const [0.3, 0.5, 0.7],
              ),
            ),
          ),
        );
      },
    );
  }
}
