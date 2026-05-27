import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/connectivity_service.dart';

/// Surface 3 del sistema offline — "Glow Pill".
///
/// Badge pequeño que aparece sobre el botón APLICAR cuando el wallpaper
/// YA está en cache local (disponible sin red). Pill redondeada con dot
/// pulsante y glow ámbar suave. Solo visible cuando offline + cache valido.
///
/// Diseño del mockup `docs/design/offline_system_concepts.html` (3B).
class OfflineBadge extends StatefulWidget {
  const OfflineBadge({
    super.key,
    this.text = 'Disponible offline',
  });

  final String text;

  @override
  State<OfflineBadge> createState() => _OfflineBadgeState();
}

class _OfflineBadgeState extends State<OfflineBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  static const Color _amber = Color(0xFFFFB400);
  static const Color _amberBright = Color(0xFFFFD66B);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConnectivityService.instance,
      builder: (context, _) {
        if (ConnectivityService.instance.isOnline) {
          return const SizedBox.shrink();
        }
        return AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, _) {
            final pulse = _pulseCtrl.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: _amber.withValues(alpha: 0.12),
                border: Border.all(
                  color: _amber.withValues(alpha: 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _amber.withValues(alpha: 0.2),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 1.0 + pulse * 0.15,
                    child: Container(
                      width: 5,
                      height: 5,
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
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.text,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _amberBright,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
