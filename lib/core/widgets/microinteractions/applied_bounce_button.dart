import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// M08 — Wallpaper Applied Bounce.
///
/// Botón con 3 estados visuales:
///   • idle    — gradient ámbar normal
///   • loading — bar de progreso interno con % opcional
///   • applied — muta a verde con check + bounce de éxito
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M08).
class AppliedBounceButton extends StatefulWidget {
  const AppliedBounceButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.state = AppliedButtonState.idle,
    this.progress = 0.0,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
  });

  final String label;
  final VoidCallback? onPressed;
  final AppliedButtonState state;
  final double progress;
  final EdgeInsets padding;

  @override
  State<AppliedBounceButton> createState() => _AppliedBounceButtonState();
}

enum AppliedButtonState { idle, loading, applied }

class _AppliedBounceButtonState extends State<AppliedBounceButton>
    with SingleTickerProviderStateMixin {
  static const Color _amber = Color(0xFFFFB400);
  static const Color _amberDeep = Color(0xFFB07A00);
  static const Color _emerald = Color(0xFF3DD68C);
  static const Color _emeraldDeep = Color(0xFF1E8754);
  static const Color _charcoal = Color(0xFF1F1B17);

  late final AnimationController _bounceCtrl;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void didUpdateWidget(AppliedBounceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state &&
        widget.state == AppliedButtonState.applied) {
      _bounceCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceCtrl,
      builder: (context, _) {
        final t = _bounceCtrl.value;
        // Easing: 0..0.3 squish, 0.3..0.6 overshoot, 0.6..1 settle
        double scale;
        if (t < 0.3) {
          scale = 1.0 - (t / 0.3) * 0.08; // 1 → 0.92
        } else if (t < 0.6) {
          scale = 0.92 + ((t - 0.3) / 0.3) * 0.14; // 0.92 → 1.06
        } else {
          scale = 1.06 - ((t - 0.6) / 0.4) * 0.06; // 1.06 → 1.0
        }
        return Transform.scale(
          scale: scale,
          child: _buildButton(),
        );
      },
    );
  }

  Widget _buildButton() {
    final isApplied = widget.state == AppliedButtonState.applied;
    final isLoading = widget.state == AppliedButtonState.loading;

    final gradient = isApplied
        ? const LinearGradient(
            colors: [_emerald, _emeraldDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [_amber, _amberDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    final textColor = isApplied ? Colors.white : _charcoal;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: widget.padding,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: (isApplied ? _emerald : _amber).withValues(alpha: 0.4),
                blurRadius: 14,
              ),
            ],
          ),
          child: Stack(
            children: [
              if (isLoading)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: widget.progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.25),
                                Colors.white.withValues(alpha: 0.05),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isApplied) ...[
                      const Icon(Icons.check, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      widget.label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.96,
                        color: textColor,
                      ),
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
}
