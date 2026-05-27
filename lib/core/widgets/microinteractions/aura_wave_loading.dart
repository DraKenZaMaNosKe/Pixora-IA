import 'dart:math' as math;
import 'package:flutter/material.dart';

/// M02 — AURA Wave Pulse Loading.
///
/// Ecualizador de barras violetas/rosas pulsantes. Reemplaza el spinner
/// genérico cuando AURA está buffering un track — comunica "audio cargando"
/// con personalidad y prepara visualmente al usuario para lo que viene.
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M02).
class AuraWaveLoading extends StatefulWidget {
  const AuraWaveLoading({
    super.key,
    this.barCount = 8,
    this.height = 80,
    this.barWidth = 4,
    this.gap = 4,
  });

  final int barCount;
  final double height;
  final double barWidth;
  final double gap;

  @override
  State<AuraWaveLoading> createState() => _AuraWaveLoadingState();
}

class _AuraWaveLoadingState extends State<AuraWaveLoading>
    with SingleTickerProviderStateMixin {
  static const Color _violet = Color(0xFF9D4EDD);
  static const Color _rose = Color(0xFFFF5A8E);

  late final AnimationController _ctrl;
  late final List<double> _baseHeights;
  late final List<double> _phaseOffsets;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    final rng = math.Random(42); // determinístico para vis consistente
    _baseHeights = List.generate(
      widget.barCount,
      (_) => 0.35 + rng.nextDouble() * 0.6,
    );
    _phaseOffsets = List.generate(
      widget.barCount,
      (i) => i * 0.1,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.barCount, (i) {
              final phase = (_ctrl.value + _phaseOffsets[i]) % 1;
              // Pulse: sin curve, scaleY entre 0.4 y 1.0
              final scaleY =
                  0.4 + (math.sin(phase * math.pi * 2) + 1) / 2 * 0.6;
              final barHeight = widget.height * _baseHeights[i] * scaleY;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.gap / 2),
                child: Container(
                  width: widget.barWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_violet, _rose],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _violet.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
