import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// One selectable entry in the Perilla dial.
class DialItemData {
  const DialItemData(
      this.label, this.kicker, this.icon, this.color, this.onApply);

  final String label;
  final String kicker;
  final IconData icon;
  final Color color;

  /// Called when this entry is committed (drag-to-center + Ir, or tap the
  /// centered option).
  final VoidCallback onApply;
}

/// The Perilla dial overlay — a glass scrim with a curved radial dial anchored
/// off the left edge. Drag up/down to rotate; the centered option is "active"
/// and live-previews (scrim tint + big Fraunces label). Committing fires the
/// item's [DialItemData.onApply]; tapping empty space cancels.
///
/// Geometry ported 1:1 from `docs/design/_dial_engine.js` (authored for a
/// ~340px phone; expressed as fractions of device width so it scales).
class DialOverlay extends StatefulWidget {
  const DialOverlay({
    super.key,
    required this.items,
    required this.initialIdx,
    required this.onClose,
  });

  final List<DialItemData> items;
  final int initialIdx;

  /// Cancel — tap outside / scrim. Reverts nothing (no commit happened).
  final VoidCallback onClose;

  @override
  State<DialOverlay> createState() => _DialOverlayState();
}

class _DialOverlayState extends State<DialOverlay>
    with SingleTickerProviderStateMixin {
  static const double _step = 25; // degrees between options

  late double _rot;
  late int _activeIdx;
  late final AnimationController _snapCtrl;
  Animation<double>? _snapAnim;

  @override
  void initState() {
    super.initState();
    _activeIdx = widget.initialIdx.clamp(0, widget.items.length - 1);
    _rot = _activeIdx * _step;
    _snapCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  double get _maxRot => (widget.items.length - 1) * _step + _step * 0.5;

  void _onDragUpdate(DragUpdateDetails d) {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    setState(() {
      _rot = (_rot + d.delta.dy * 0.42).clamp(-_step * 0.5, _maxRot);
      final idx = (_rot / _step).round().clamp(0, widget.items.length - 1);
      if (idx != _activeIdx) {
        _activeIdx = idx;
        HapticFeedback.selectionClick();
      }
    });
  }

  void _onDragEnd(DragEndDetails d) => _snapTo((_rot / _step).round());

  void _snapTo(int idx) {
    idx = idx.clamp(0, widget.items.length - 1);
    final from = _rot;
    final to = idx * _step;
    _snapAnim = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic),
    )..addListener(() => setState(() => _rot = _snapAnim!.value));
    _activeIdx = idx;
    _snapCtrl.forward(from: 0);
  }

  void _apply() {
    HapticFeedback.selectionClick();
    widget.items[_activeIdx].onApply();
  }

  Offset _optPos(int i, Size size) {
    final w = size.width;
    final cx = -0.206 * w;
    final r = 0.735 * w;
    final cy = size.height / 2 + 8;
    final ang = i * _step - _rot;
    final th = ang * math.pi / 180;
    return Offset(cx + r * math.cos(th), cy + r * math.sin(th));
  }

  void _onTapUp(TapUpDetails d, Size size) {
    // Tap near the centered option commits it; tap on empty space cancels.
    final activePos = _optPos(_activeIdx, size);
    if ((d.localPosition - activePos).distance < 110) {
      _apply();
    } else {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final active = widget.items[_activeIdx];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onTapUp: (d) => _onTapUp(d, size),
      child: Stack(
        children: [
          // Glass scrim, tinted with the active section's brand color.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 11, sigmaY: 11),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.1, 0),
                    radius: 1.3,
                    colors: [
                      active.color.withValues(alpha: 0.34),
                      Colors.black.withValues(alpha: 0.58),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Curved dial options.
          for (int i = 0; i < widget.items.length; i++) _buildOption(i, size),
          // Big active label (bottom-left), Fraunces italic like the app title.
          Positioned(
            left: 24,
            right: 24,
            bottom: 116,
            child: IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active.kicker.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 12,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    active.label,
                    style: GoogleFonts.fraunces(
                      fontSize: 40,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Commit button.
          Positioned(
            left: 24,
            right: 24,
            bottom: 44,
            child: GestureDetector(
              onTap: _apply,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF4D774), Color(0xFFD4AF37)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: -3,
                    ),
                  ],
                ),
                child: Text(
                  'Ir a ${active.label}',
                  style: const TextStyle(
                    color: Color(0xFF231A06),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(int i, Size size) {
    final ang = i * _step - _rot;
    final d = ang.abs();
    final op = d > 78 ? 0.0 : math.max(0.0, 1 - d / 72);
    if (op <= 0.01) return const SizedBox.shrink();
    final scale = math.max(0.5, 1 - d / 150);
    final pos = _optPos(i, size);
    final activeOpt = d < _step / 2;
    return Positioned(
      left: pos.dx - 6,
      top: pos.dy - 24,
      child: IgnorePointer(
        child: Opacity(
          opacity: op,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.centerLeft,
            child: _DialOption(item: widget.items[i], active: activeOpt),
          ),
        ),
      ),
    );
  }
}

/// A single dial option: icon disc + label + kicker.
class _DialOption extends StatelessWidget {
  const _DialOption({required this.item, required this.active});

  final DialItemData item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 48,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFF4D774), Color(0xFFA67C1A)],
                    )
                  : null,
              color: active ? null : Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: active ? Colors.transparent : Colors.white24,
                width: 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                        blurRadius: 14,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              item.icon,
              size: 21,
              color: active ? const Color(0xFF231A06) : Colors.white70,
            ),
          ),
          const SizedBox(width: 11),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white70,
                    fontSize: active ? 17 : 15,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Text(
                  item.kicker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFD4AF37)
                        .withValues(alpha: active ? 1.0 : 0.5),
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
