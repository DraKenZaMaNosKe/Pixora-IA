import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dual-Layer HUD category chip — Eduardo's pick (Concept #5 from
/// category_buttons_concepts.html, 2026-05-17).
///
/// Visual recipe:
/// - Outer gradient border (cyan electric → amber)
/// - Inner background ink premium (deep black)
/// - LED dot amber pulsante (status indicator)
/// - Mono uppercase label + optional count
/// - Hover/press feedback: outer glow expands
/// - Active state: bigger glow + filled gradient border
///
/// Used in WALLPAPERS + LIVE sections as the entry point to the
/// WallpaperViewerHudPage. Colors are hardcoded (not theme-dependent)
/// because the HUD viewer is a "special explorer" that lives apart from
/// the app's regular B&G / iOS White themes.
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

  // ─── HUD palette (hardcoded, theme-independent) ────────────────────────
  static const _ink = Color(0xFF02050A);
  static const _inkLayer = Color(0xFF0A1018);
  static const _cyan = Color(0xFF00E5FF);
  static const _cyanDeep = Color(0xFF0099B0);
  static const _amber = Color(0xFFFFB400);
  static const _amberDeep = Color(0xFFB07A00);

  @override
  State<CategoryChipHud> createState() => _CategoryChipHudState();
}

class _CategoryChipHudState extends State<CategoryChipHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    // Slow pulse for the LED dot. Always running — independent of active state.
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
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
            gradient: LinearGradient(
              colors: active
                  ? const [CategoryChipHud._cyan, CategoryChipHud._amber]
                  : const [
                      CategoryChipHud._cyanDeep,
                      CategoryChipHud._amberDeep,
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(3),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: CategoryChipHud._cyan.withValues(alpha: 0.35),
                      blurRadius: 14,
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [CategoryChipHud._inkLayer, CategoryChipHud._ink],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // LED dot — amber pulsante
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) {
                    final t = _pulseCtrl.value;
                    final glow = 4.0 + (t * 6.0);
                    return Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: CategoryChipHud._amber,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                CategoryChipHud._amber.withValues(alpha: 0.5),
                            blurRadius: glow,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // Label
                Text(
                  widget.label.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                    color: active ? Colors.white : CategoryChipHud._cyan,
                  ),
                ),
                // Counter (optional)
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
                          : CategoryChipHud._cyan.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
