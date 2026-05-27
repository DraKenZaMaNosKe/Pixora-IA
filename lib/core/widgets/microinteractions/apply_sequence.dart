import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// M04 — Apply Wallpaper Sequence.
///
/// 3 chips horizontales mostrando los pasos del apply:
///   1. Cargando
///   2. Enviando (al sistema)
///   3. Listo
///
/// Cada step pasa por: pending (gris) → active (ámbar, dot pulsante) →
/// done (verde, dot sólido). Convierte una espera silenciosa en una
/// narrativa visual.
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M04).
class ApplySequence extends StatelessWidget {
  const ApplySequence({
    super.key,
    required this.activeStep,
    this.steps = const ['Cargando', 'Enviando', 'Listo'],
  });

  /// 0 = primero activo, 1 = segundo activo, 2 = tercero (terminó).
  /// Pasar `-1` para mostrar todos pending.
  final int activeStep;
  final List<String> steps;

  static const Color _amber = Color(0xFFFFB400);
  static const Color _amberBright = Color(0xFFFFD66B);
  static const Color _emerald = Color(0xFF3DD68C);

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final state = i < activeStep
          ? _StepState.done
          : (i == activeStep ? _StepState.active : _StepState.pending);
      children.add(_buildStep(steps[i], state));
      if (i < steps.length - 1) {
        children.add(_buildArrow());
      }
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildStep(String label, _StepState state) {
    Color bg, border, fg, dotColor;
    switch (state) {
      case _StepState.pending:
        bg = Colors.white.withValues(alpha: 0.04);
        border = Colors.white.withValues(alpha: 0.08);
        fg = Colors.white.withValues(alpha: 0.4);
        dotColor = Colors.white.withValues(alpha: 0.2);
        break;
      case _StepState.active:
        bg = _amber.withValues(alpha: 0.12);
        border = _amber;
        fg = _amberBright;
        dotColor = _amber;
        break;
      case _StepState.done:
        bg = _emerald.withValues(alpha: 0.1);
        border = _emerald;
        fg = _emerald;
        dotColor = _emerald;
        break;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: dotColor, pulse: state == _StepState.active),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '›',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.2),
          fontSize: 14,
        ),
      ),
    );
  }
}

enum _StepState { pending, active, done }

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Dot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final scale = 1.0 + (_ctrl.value * 0.3);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: widget.pulse
                  ? [BoxShadow(color: widget.color, blurRadius: 6)]
                  : null,
            ),
          ),
        );
      },
    );
  }
}
