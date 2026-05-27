import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

/// Surface 1 del sistema offline — "Cosmic Pulse".
///
/// Pequeño punto ámbar con halo radial pulsante que aparece en el header
/// solo cuando NO hay conexión. Bounce-in al perder conexión, sparkle-out
/// al volver. Diseño del mockup `docs/design/offline_system_concepts.html`.
class OfflineIndicator extends StatefulWidget {
  const OfflineIndicator({super.key});

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _enterCtrl;

  static const Color _amber = Color(0xFFFFB400);
  static const Color _amberBright = Color(0xFFFFD66B);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    if (!ConnectivityService.instance.isOnline) {
      _enterCtrl.forward();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConnectivityService.instance,
      builder: (context, _) {
        final online = ConnectivityService.instance.isOnline;
        if (online) {
          _enterCtrl.reverse();
        } else if (_enterCtrl.status != AnimationStatus.forward &&
            _enterCtrl.value < 1.0) {
          _enterCtrl.forward();
        }
        return _build(online);
      },
    );
  }

  Widget _build(bool online) {
    return IgnorePointer(
      ignoring: online,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseCtrl, _enterCtrl]),
        builder: (context, _) {
          // Elastic bounce-in: scale 0.3 → 1.25 → 1.0
          final t = _enterCtrl.value;
          final scale = t < 0.5
              ? 0.3 + (t * 2) * 0.95 // 0.3 → 1.25
              : 1.25 - ((t - 0.5) * 2) * 0.25; // 1.25 → 1.0
          final opacity = t.clamp(0.0, 1.0);
          final pulseScale = 1.0 + (_pulseCtrl.value * 0.15);
          final pulseOpacity = 1.0 - (_pulseCtrl.value * 0.3);

          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: SizedBox(
                width: 14,
                height: 14,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Halo radial pulsante
                    Transform.scale(
                      scale: pulseScale,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _amberBright.withValues(
                                  alpha: pulseOpacity * 0.6),
                              _amberBright.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Punto sólido central
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _amberBright,
                        boxShadow: [
                          BoxShadow(
                            color: _amber.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
