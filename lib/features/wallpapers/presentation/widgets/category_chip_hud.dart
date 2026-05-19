import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sapphire HUD category chip — Eduardo's gems pick (Concept #03
/// "Sapphire Blue" from category_chips_gems.html, 2026-05-18).
///
/// Visual recipe:
/// - Outer gradient border (sapphire bright → sapphire deep)
/// - Inner background ink premium (very dark navy)
/// - LED dot sapphire bright pulsante (status indicator)
/// - Mono uppercase label + optional count
/// - **Shine sweep**: diagonal white highlight crosses each chip on a
///   stagger (offset derived from the label hash so chips don't
///   sync to a single visible wave)
/// - Hover/press feedback: outer glow expands
/// - Active state: bigger glow + filled gradient border
///
/// Used in WALLPAPERS + LIVE sections as the entry point to the
/// WallpaperViewerHudPage. Colors are hardcoded (not theme-dependent)
/// because the HUD viewer is a "special explorer" that lives apart from
/// the app's regular B&G / iOS White themes — and Sapphire reads premium
/// on both backgrounds.
class CategoryChipHud extends StatefulWidget {
  const CategoryChipHud({
    super.key,
    required this.label,
    required this.onTap,
    this.count,
    this.active = false,
  });

  /// Category display label (e.g. 'TRENDING', 'ARTE', 'DARK').
  /// Will be uppercased automatically by the chip.
  final String label;

  /// Optional count of wallpapers in this category (shows next to label).
  /// Pass null to hide the count.
  final int? count;

  /// Whether this chip is the currently selected category. Active chips
  /// get a stronger glow + filled outer border.
  final bool active;

  /// Tap handler. Caller is responsible for pushing the viewer page.
  final VoidCallback onTap;

  // ─── Sapphire palette (hardcoded, theme-independent) ──────────────────
  static const _ink = Color(0xFF02050A);
  static const _inkLayer = Color(0xFF06101D);
  static const _sapphire = Color(0xFF1FA8FF);
  static const _sapphireDeep = Color(0xFF0B5BB8);
  static const _sapphireBright = Color(0xFF5CC6FF);
  static const _sapphirePale = Color(0xFFBFE6FF);

  @override
  State<CategoryChipHud> createState() => _CategoryChipHudState();
}

class _CategoryChipHudState extends State<CategoryChipHud>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _shineCtrl;
  late final double _phaseOffset;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    // Slow pulse for the LED dot. Always running — independent of active.
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    // Shine sweep across the chip — every ~4s.
    _shineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
    // Stable per-label offset so the row of chips doesn't shine in lockstep.
    _phaseOffset = (widget.label.hashCode.abs() % 100) / 100.0;
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final scale = _pressed ? 0.96 : 1.0;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                CategoryChipHud._sapphireBright,
                CategoryChipHud._sapphireDeep,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: CategoryChipHud._sapphire.withValues(
                  alpha: active ? 0.45 : 0.20,
                ),
                blurRadius: active ? 16 : 10,
                spreadRadius: 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(2)),
            child: Stack(
              children: [
                // Inner ink layer (base background)
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -1.2),
                      radius: 1.4,
                      colors: [
                        CategoryChipHud._sapphire.withValues(alpha: 0.18),
                        CategoryChipHud._inkLayer,
                        CategoryChipHud._ink,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LedDot(controller: _pulseCtrl, active: active),
                      const SizedBox(width: 8),
                      Text(
                        widget.label.toUpperCase(),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.2,
                          color: active
                              ? Colors.white
                              : CategoryChipHud._sapphirePale,
                        ),
                      ),
                      if (widget.count != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          widget.count.toString(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1,
                            color: active
                                ? Colors.white.withValues(alpha: 0.7)
                                : CategoryChipHud._sapphire
                                    .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Shine sweep — diagonal white highlight crossing the chip.
                // IgnorePointer so it never steals taps.
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _shineCtrl,
                      builder: (_, __) {
                        final t = (_shineCtrl.value + _phaseOffset) % 1.0;
                        return CustomPaint(
                          painter: _SapphireShinePainter(progress: t),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// LED dot — sapphire bright with breathing glow.
class _LedDot extends StatelessWidget {
  const _LedDot({required this.controller, required this.active});
  final AnimationController controller;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        final glow = 4.0 + (t * 6.0);
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: CategoryChipHud._sapphireBright,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: CategoryChipHud._sapphireBright.withValues(alpha: 0.6),
                blurRadius: glow,
              ),
              BoxShadow(
                color: CategoryChipHud._sapphire.withValues(alpha: 0.4),
                blurRadius: glow + 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// CustomPainter that draws a diagonal white-to-transparent gradient band
/// sweeping across the chip from left to right. The band has a steep
/// 115° angle so it reads as a "shine" rather than a horizontal line.
class _SapphireShinePainter extends CustomPainter {
  _SapphireShinePainter({required this.progress});

  /// 0..1 — where in the sweep cycle we are.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Move from off-screen left to off-screen right.
    // Band width is ~40% of the chip width.
    final w = size.width;
    final h = size.height;
    final bandWidth = w * 0.4;
    final travel = w + bandWidth * 2;
    final x = -bandWidth + travel * progress;

    // Skip rendering when off-screen on either side (cheap optimization).
    if (x + bandWidth < 0 || x > w) return;

    // Diagonal gradient using transform — rotate the gradient by ~25° via
    // a sheared rect approach. Simpler: paint a parallelogram of width
    // bandWidth, slanted by skewing the points.
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x + bandWidth, 0)
      ..lineTo(x + bandWidth - h * 0.5, h)
      ..lineTo(x - h * 0.5, h)
      ..close();

    final shader = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0x00FFFFFF),
        Color(0x33FFFFFF),
        Color(0x66FFFFFF),
        Color(0x33FFFFFF),
        Color(0x00FFFFFF),
      ],
      stops: [0.0, 0.30, 0.5, 0.70, 1.0],
    ).createShader(Rect.fromLTWH(x, 0, bandWidth, h));

    canvas.drawPath(path, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_SapphireShinePainter old) => old.progress != progress;
}
