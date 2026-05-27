import 'package:flutter/material.dart';

/// M22 — Error Shake.
///
/// Wrapper que sacude horizontalmente cualquier widget hijo cuando se llama
/// [ErrorShakeController.trigger]. Útil para botones que fallan (login,
/// download, apply), inputs invalidos, snackbars de error.
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M22).
///
/// ```dart
/// final shake = ErrorShakeController();
/// ...
/// ErrorShake(controller: shake, child: MyButton(...));
/// ...
/// // disparar el shake desde donde sea:
/// shake.trigger();
/// ```
class ErrorShakeController extends ChangeNotifier {
  int _ticks = 0;
  int get ticks => _ticks;
  void trigger() {
    _ticks++;
    notifyListeners();
  }
}

class ErrorShake extends StatefulWidget {
  const ErrorShake({
    super.key,
    required this.controller,
    required this.child,
    this.intensity = 8.0,
    this.duration = const Duration(milliseconds: 400),
  });

  final ErrorShakeController controller;
  final Widget child;
  final double intensity;
  final Duration duration;

  @override
  State<ErrorShake> createState() => _ErrorShakeState();
}

class _ErrorShakeState extends State<ErrorShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    widget.controller.addListener(_onTrigger);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTrigger);
    _ctrl.dispose();
    super.dispose();
  }

  void _onTrigger() {
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        // Offset: 0% → 0, 20% → -8, 40% → 8, 60% → -5, 80% → 5, 100% → 0
        final t = _ctrl.value;
        double dx;
        if (t < 0.2) {
          dx = -(t / 0.2) * widget.intensity;
        } else if (t < 0.4) {
          dx = -widget.intensity + ((t - 0.2) / 0.2) * (widget.intensity * 2);
        } else if (t < 0.6) {
          dx =
              widget.intensity - ((t - 0.4) / 0.2) * (widget.intensity * 1.625);
        } else if (t < 0.8) {
          dx = -widget.intensity * 0.625 +
              ((t - 0.6) / 0.2) * (widget.intensity * 1.25);
        } else {
          dx = widget.intensity * 0.625 -
              ((t - 0.8) / 0.2) * (widget.intensity * 0.625);
        }
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
