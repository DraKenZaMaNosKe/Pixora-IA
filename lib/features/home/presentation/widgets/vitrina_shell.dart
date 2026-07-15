import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/home_section.dart';
import 'dial/dial_overlay.dart';

/// Full-bleed home shell for the "Vitrina + Perilla" navigation.
///
/// Release A shipped a temporary list selector; Release B swaps it for the real
/// Perilla dial: the gold button on the left edge opens a glass overlay with a
/// curved radial dial (drag up/down to rotate, the centered section is active).
/// The 10 primary sections live on the dial; an 11th "Más" entry opens a sheet
/// with Stories / Tonos / AI Create. Settings stays on the top-bar gear.
///
/// The shell reserves top padding equal to the floating top bar so bare content
/// pages (Aura, Favoritos) don't slide under it.
class VitrinaShell extends StatefulWidget {
  const VitrinaShell({
    super.key,
    required this.currentIndex,
    required this.topBar,
    required this.onSelectSection,
    required this.children,
  });

  /// Active section index (matches [HomeSection.index] and the [children] order).
  final int currentIndex;

  /// The floating top bar.
  final Widget topBar;

  /// Fired with the chosen section's index.
  final ValueChanged<int> onSelectSection;

  /// Section pages in [HomeSection.index] order (kept mounted via IndexedStack).
  final List<Widget> children;

  @override
  State<VitrinaShell> createState() => _VitrinaShellState();
}

class _VitrinaShellState extends State<VitrinaShell> {
  static const double _topBarHeight = 52;

  bool _dialOpen = false;

  void _openDial() {
    HapticFeedback.selectionClick();
    setState(() => _dialOpen = true);
  }

  void _closeDial() {
    if (mounted) setState(() => _dialOpen = false);
  }

  List<DialItemData> _dialItems() {
    final items = kDialSections
        .map((m) => DialItemData(m.label, m.kicker, m.icon, m.brandColor, () {
              widget.onSelectSection(m.section.index);
              _closeDial();
            }))
        .toList();
    // 11th entry — opens the secondary "Más" sheet (Stories / Tonos / IA).
    items.add(DialItemData(
      'Más',
      'Stories · Tonos · IA',
      Icons.more_horiz_rounded,
      const Color(0xFFD4AF37),
      () {
        _closeDial();
        _openMoreSheet();
      },
    ));
    return items;
  }

  int _initialDialIdx() {
    final i =
        kDialSections.indexWhere((m) => m.section.index == widget.currentIndex);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Section content — reserves space for the floating bar on top.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: mq.padding.top + _topBarHeight),
              child: IndexedStack(
                  index: widget.currentIndex, children: widget.children),
            ),
          ),
          // Floating top bar.
          Positioned(top: 0, left: 0, right: 0, child: widget.topBar),
          // Perilla — a tab flush to the left edge, vertically centered
          // (hidden while the dial is open).
          if (!_dialOpen)
            Positioned(
              left: 0,
              top: mq.size.height * 0.5 - 36,
              child: _PerillaButton(onTap: _openDial),
            ),
          // Perilla dial overlay.
          if (_dialOpen)
            Positioned.fill(
              child: DialOverlay(
                items: _dialItems(),
                initialIdx: _initialDialIdx(),
                onClose: _closeDial,
              ),
            ),
        ],
      ),
    );
  }

  void _openMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF17140F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0x33D4AF37),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Text(
                  'MÁS',
                  style: TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                ...kMoreSections.map((m) {
                  final active = m.section.index == widget.currentIndex;
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(m.icon,
                        color: active ? m.brandColor : const Color(0xFFE8E6E0),
                        size: 22),
                    title: Text(
                      m.label,
                      style: TextStyle(
                        color: active ? m.brandColor : const Color(0xFFE8E6E0),
                        fontSize: 15,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      m.kicker,
                      style: const TextStyle(
                          color: Color(0x99E8E6E0), fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      widget.onSelectSection(m.section.index);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Gold "Perilla" button on the left edge. Tapping it opens the dial overlay.
class _PerillaButton extends StatelessWidget {
  const _PerillaButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF4D774), Color(0xFFA67C1A)],
          ),
          // Rounded only on the right — reads as a tab growing from the edge.
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
              blurRadius: 20,
              spreadRadius: -1,
            ),
            const BoxShadow(
              color: Color(0x66000000),
              blurRadius: 8,
              offset: Offset(2, 3),
            ),
          ],
        ),
        // Up/down chevrons signal "drag me vertically".
        child:
            const Icon(Icons.unfold_more, color: Color(0xFF231A06), size: 22),
      ),
    );
  }
}
