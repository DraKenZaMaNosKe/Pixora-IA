import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/credit_service.dart';

/// M07 — Credit Count-Up + Glow.
///
/// Pill que muestra el balance de créditos 💎 y, cuando el balance SUBE
/// (típicamente después de ver un anuncio), hace un count-up animado de
/// número viejo a nuevo + glow ámbar pulse.
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M07).
///
/// Para usar en lugar del badge actual: drop-in replacement, escucha a
/// `CreditService.instance` automáticamente.
class CreditCountUpBadge extends StatefulWidget {
  const CreditCountUpBadge({
    super.key,
    this.onTap,
  });

  final VoidCallback? onTap;

  @override
  State<CreditCountUpBadge> createState() => _CreditCountUpBadgeState();
}

class _CreditCountUpBadgeState extends State<CreditCountUpBadge>
    with SingleTickerProviderStateMixin {
  static const Color _gold = Color(0xFFC9A650);
  static const Color _amber = Color(0xFFFFB400);
  static const Color _amberBright = Color(0xFFFFD66B);

  late final AnimationController _glowCtrl;
  int _displayBalance = 0;
  int _lastSeenBalance = 0;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _displayBalance = CreditService.instance.balance;
    _lastSeenBalance = _displayBalance;
    CreditService.instance.addListener(_onCreditsChanged);
  }

  @override
  void dispose() {
    CreditService.instance.removeListener(_onCreditsChanged);
    _glowCtrl.dispose();
    super.dispose();
  }

  void _onCreditsChanged() {
    final newBalance = CreditService.instance.balance;
    if (newBalance == _lastSeenBalance) return;
    if (newBalance > _lastSeenBalance) {
      _animateCountUp(_lastSeenBalance, newBalance);
      _glowCtrl.forward(from: 0);
    } else {
      // Bajada (spend) → cambio directo sin micro
      if (mounted) setState(() => _displayBalance = newBalance);
    }
    _lastSeenBalance = newBalance;
  }

  void _animateCountUp(int from, int to) async {
    final delta = to - from;
    final steps = delta.clamp(1, 30); // máx 30 frames
    final stepDelay = 50 ~/ steps.clamp(1, 50);
    for (var i = 1; i <= steps; i++) {
      if (!mounted) return;
      await Future.delayed(Duration(milliseconds: stepDelay.clamp(20, 50)));
      if (!mounted) return;
      setState(() {
        _displayBalance = from + ((delta * i) ~/ steps);
      });
    }
    if (mounted) setState(() => _displayBalance = to);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _glowCtrl,
        builder: (context, _) {
          final t = _glowCtrl.value;
          // 0..0.5 → up, 0.5..1 → down
          final pulse = t < 0.5 ? t * 2 : (1 - t) * 2;
          final scale = 1.0 + pulse * 0.08;
          return Transform.scale(
            scale: scale,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: Color.lerp(
                  _gold.withValues(alpha: 0.12),
                  _amberBright.withValues(alpha: 0.25),
                  pulse,
                ),
                border: Border.all(
                  color: Color.lerp(
                        _gold.withValues(alpha: 0.4),
                        _amberBright,
                        pulse,
                      ) ??
                      _gold,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _amber.withValues(alpha: pulse * 0.4),
                    blurRadius: 24 * pulse,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.diamond_outlined,
                    size: 12,
                    color: Color.lerp(_amberBright, Colors.white, pulse * 0.4),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_displayBalance',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color.lerp(_gold, _amberBright, pulse),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
