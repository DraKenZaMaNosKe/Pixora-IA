import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/connectivity_service.dart';

/// Surface 2 + 4 del sistema offline — "Holographic Edge".
///
/// Modal glassmorphic con borde gradient gold giratorio y gleam diagonal.
/// Usado para dos escenarios:
///   • [OfflineModal.noInternet]    — sin internet + sin cache (download)
///   • [OfflineModal.autoRotate]    — AutoRotate sin contenido inicial
///
/// El botón "Reintentar" verifica conexión real con un ping HEAD a Google
/// (~500 bytes) y, si responde OK, cierra el modal automáticamente.
/// Diseño del mockup `docs/design/offline_system_concepts.html` (2C/4C).
class OfflineModal extends StatefulWidget {
  const OfflineModal._({
    required this.title,
    required this.titleEm,
    required this.body,
    required this.showDownloadMini,
    this.onRetrySuccess,
  });

  factory OfflineModal.noInternet({VoidCallback? onRetrySuccess}) {
    return OfflineModal._(
      title: 'Conexión',
      titleEm: 'interrumpida',
      body:
          'Para traer este wallpaper necesitamos internet. Conéctate y lo descargamos en segundos.',
      showDownloadMini: false,
      onRetrySuccess: onRetrySuccess,
    );
  }

  factory OfflineModal.autoRotate({VoidCallback? onRetrySuccess}) {
    return OfflineModal._(
      title: 'Sincronización',
      titleEm: 'pendiente',
      body:
          'AutoRotate necesita descargar 3-5 wallpapers iniciales. Conéctate y arranca en segundos.',
      showDownloadMini: true,
      onRetrySuccess: onRetrySuccess,
    );
  }

  final String title;
  final String titleEm;
  final String body;
  final bool showDownloadMini;
  final VoidCallback? onRetrySuccess;

  /// Muestra el modal como dialog. Retorna `true` si el usuario logró
  /// reconectarse (ping OK), `false` o `null` si cerró sin reconectar.
  static Future<bool?> show(BuildContext context,
      {required bool isAutoRotate}) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (ctx, anim, secAnim) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: isAutoRotate
                ? OfflineModal.autoRotate(
                    onRetrySuccess: () => Navigator.of(ctx).pop(true),
                  )
                : OfflineModal.noInternet(
                    onRetrySuccess: () => Navigator.of(ctx).pop(true),
                  ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secAnim, child) {
        return Opacity(
          opacity: anim.value,
          child: Transform.scale(
            scale: 0.85 + anim.value * 0.15,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<OfflineModal> createState() => _OfflineModalState();
}

class _OfflineModalState extends State<OfflineModal>
    with TickerProviderStateMixin {
  static const Color _amber = Color(0xFFFFB400);
  static const Color _amberBright = Color(0xFFFFD66B);
  static const Color _emerald = Color(0xFF3DD68C);
  static const Color _charcoal = Color(0xFF1F1B17);

  late final AnimationController _gleamCtrl;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _gleamCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _gleamCtrl.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await ConnectivityService.instance.verifyRealConnection();
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) {
      widget.onRetrySuccess?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A14).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              // Borde gold gradient
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _gleamCtrl,
                  builder: (_, __) {
                    return CustomPaint(
                      painter: _HoloEdgePainter(
                        progress: _gleamCtrl.value,
                        color: _amberBright,
                      ),
                    );
                  },
                ),
              ),
              // Gleam diagonal
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _gleamCtrl,
                  builder: (_, __) {
                    return Transform.rotate(
                      angle: _gleamCtrl.value * 6.283185,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.transparent,
                              _amber.withValues(alpha: 0.05),
                              Colors.transparent,
                            ],
                            stops: const [0.3, 0.5, 0.7],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Contenido
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _holoIcon(),
                    const SizedBox(height: 16),
                    _titleText(),
                    const SizedBox(height: 8),
                    Text(
                      widget.body,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        height: 1.55,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (widget.showDownloadMini && _checking) _downloadMini(),
                    if (widget.showDownloadMini && _checking)
                      const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _ghostButton()),
                        const SizedBox(width: 8),
                        Expanded(child: _primaryButton()),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _holoIcon() {
    return AnimatedBuilder(
      animation: _gleamCtrl,
      builder: (_, __) {
        final pulse = (_gleamCtrl.value * 4) % 1;
        final color = _checking ? _emerald : _amberBright;
        return SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: _checking ? _gleamCtrl.value * 12.566 : 0,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 16,
                      ),
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                ),
              ),
              Opacity(
                opacity: 1.0 - (pulse * 0.3),
                child: Icon(
                  _checking ? Icons.refresh : Icons.wifi_off_outlined,
                  size: 28,
                  color: color,
                  shadows: [
                    Shadow(
                      color: color.withValues(alpha: 0.7),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _titleText() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: GoogleFonts.fraunces(
          fontSize: 19,
          fontWeight: FontWeight.w400,
          color: Colors.white,
          letterSpacing: -0.1,
        ),
        children: [
          TextSpan(text: '${widget.title} '),
          TextSpan(
            text: widget.titleEm,
            style: GoogleFonts.fraunces(
              fontSize: 19,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w400,
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: [_amberBright, _amber],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(const Rect.fromLTWH(0, 0, 200, 25)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _downloadMini() {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.2, end: 1.0),
              duration: Duration(milliseconds: 600 + i * 200),
              curve: Curves.easeOut,
              builder: (_, t, __) {
                return Opacity(
                  opacity: 0.2 + t * 0.8,
                  child: Transform.scale(
                    scale: 0.8 + t * 0.2,
                    child: Container(
                      width: 14,
                      height: 24,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF3A2210), Color(0xFF1A0A14)],
                        ),
                        border: Border.all(
                          color: const Color(0xFFC9A650).withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _ghostButton() {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(false),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Center(
            child: Text(
              'Cerrar',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryButton() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: _checking ? null : _retry,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: const LinearGradient(
              colors: [_amberBright, _amber],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: _amberBright),
            boxShadow: [
              BoxShadow(
                color: _amber.withValues(alpha: 0.5),
                blurRadius: 12,
              ),
            ],
          ),
          child: Center(
            child: _checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(_charcoal),
                    ),
                  )
                : Text(
                    'Reintentar',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: _charcoal,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _HoloEdgePainter extends CustomPainter {
  _HoloEdgePainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 6.283185,
        transform: GradientRotation(progress * 6.283185),
        colors: [
          color,
          Colors.transparent,
          color.withValues(alpha: 0.6),
          Colors.transparent,
          color,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      const Radius.circular(15),
    );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_HoloEdgePainter old) => old.progress != progress;
}

// BackdropFilter wrapper que evita crashes en plataformas sin GPU compose.
