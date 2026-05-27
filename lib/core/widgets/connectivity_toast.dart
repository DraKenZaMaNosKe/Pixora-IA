import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/connectivity_service.dart';

/// Surface 5 del sistema offline — "Edge Gleam".
///
/// Toast verde con borde superior que brilla 2 veces. Aparece SOLO cuando
/// la conexión vuelve después de estar offline >30 segundos (debouncing en
/// [ConnectivityService]). Auto-dismiss después de 3.5s.
///
/// Diseño del mockup `docs/design/offline_system_concepts.html` (5B).
///
/// Plug-and-play: envolver el body de [MaterialApp] con [ConnectivityToastHost]
/// y olvidarte. Escucha a [ConnectivityService.showRestoredToast].
class ConnectivityToastHost extends StatefulWidget {
  const ConnectivityToastHost({required this.child, super.key});
  final Widget child;

  @override
  State<ConnectivityToastHost> createState() => _ConnectivityToastHostState();
}

class _ConnectivityToastHostState extends State<ConnectivityToastHost> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    ConnectivityService.instance.removeListener(_onConnectivityChanged);
    _entry?.remove();
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (!ConnectivityService.instance.showRestoredToast) return;
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (_) => _EdgeGleamToast(
        onDone: () {
          _entry?.remove();
          _entry = null;
        },
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _EdgeGleamToast extends StatefulWidget {
  const _EdgeGleamToast({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_EdgeGleamToast> createState() => _EdgeGleamToastState();
}

class _EdgeGleamToastState extends State<_EdgeGleamToast>
    with TickerProviderStateMixin {
  static const Color _emerald = Color(0xFF3DD68C);
  static const Color _cream = Color(0xFFF0E6D2);

  late final AnimationController _enterCtrl;
  late final AnimationController _gleamCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..forward();
    _enterCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _gleamCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
    // dispara el segundo gleam ~600ms después
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _gleamCtrl
        ..reset()
        ..forward();
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _gleamCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _enterCtrl,
      builder: (context, child) {
        final t = _enterCtrl.value;
        // 0.0..0.1 → slide-in (opacity 0→1, translateY 20→0)
        // 0.1..0.85 → visible
        // 0.85..1.0 → fade-out + slide-up
        double opacity;
        double translateY;
        if (t < 0.1) {
          final p = t / 0.1;
          opacity = p;
          translateY = 20 - p * 20;
        } else if (t < 0.85) {
          opacity = 1;
          translateY = 0;
        } else {
          final p = (t - 0.85) / 0.15;
          opacity = 1 - p;
          translateY = -p * 8;
        }
        return Positioned(
          left: 14,
          right: 14,
          bottom: MediaQuery.of(context).padding.bottom + 30,
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, translateY),
              child: child,
            ),
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: _toastContent(),
      ),
    );
  }

  Widget _toastContent() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF06201A), Color(0xFF091F15)],
              ),
              border: Border.all(
                color: _emerald.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _emerald, width: 1.5),
                  ),
                  child: const Center(
                    child: Icon(Icons.check, size: 11, color: _emerald),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ONLINE',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8,
                          letterSpacing: 2.4,
                          color: _emerald,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Conexión restaurada',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _cream,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Edge gleam — barra de 1px que cruza el borde superior
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 1,
            child: AnimatedBuilder(
              animation: _gleamCtrl,
              builder: (_, __) {
                return CustomPaint(
                  painter: _GleamPainter(progress: _gleamCtrl.value),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GleamPainter extends CustomPainter {
  _GleamPainter({required this.progress});
  final double progress;
  static const Color _emerald = Color(0xFF3DD68C);

  @override
  void paint(Canvas canvas, Size size) {
    final x = -size.width + progress * size.width * 2;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          _emerald.withValues(alpha: 0.9),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(x, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(x, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_GleamPainter old) => old.progress != progress;
}
