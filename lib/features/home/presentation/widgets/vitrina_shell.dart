import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/home_section.dart';

/// Full-bleed home shell for the "Vitrina + Perilla" navigation (Release A).
///
/// Release A ships behind a flag with a TEMPORARY plain section selector — the
/// gold "Perilla" button on the left edge opens a bottom-sheet list of sections
/// (no curved dial yet; the real Perilla dial lands in Release B).
///
/// The shell reserves top padding equal to the floating top bar so bare content
/// pages (Aura, Favoritos) don't slide under it — a deliberate deviation from
/// the pure full-bleed mock, safe and predictable for the structural refactor.
class VitrinaShell extends StatelessWidget {
  const VitrinaShell({
    super.key,
    required this.currentIndex,
    required this.children,
    required this.topBar,
    required this.onSelectSection,
  });

  /// Active section index (matches [HomeSection.index] and the [children] order).
  final int currentIndex;

  /// The section pages, in [HomeSection.index] order (same list the old
  /// IndexedStack used — kept mounted so scroll + Riverpod state survive).
  final List<Widget> children;

  /// The floating [VitrinaTopBar].
  final Widget topBar;

  /// Fired with the chosen section's index when the user picks from the selector.
  final ValueChanged<int> onSelectSection;

  static const double _topBarHeight = 52;

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
              child: IndexedStack(index: currentIndex, children: children),
            ),
          ),
          // Floating top bar.
          Positioned(top: 0, left: 0, right: 0, child: topBar),
          // Perilla (placeholder) — left edge, vertically centered.
          Positioned(
            left: 12,
            top: mq.size.height * 0.5 - 28,
            child: _PerillaButton(onTap: () => _openSelector(context)),
          ),
        ],
      ),
    );
  }

  void _openSelector(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF17140F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: SingleChildScrollView(
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
                    'SECCIONES',
                    style: TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Dial sections first, then the "Más" group.
                  ..._sectionTiles(ctx, kDialSections),
                  if (kMoreSections.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 10, bottom: 4),
                      child: Text(
                        'MÁS',
                        style: TextStyle(
                          color: Color(0x99E8E6E0),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    ..._sectionTiles(ctx, kMoreSections),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _sectionTiles(BuildContext ctx, List<HomeSectionMeta> metas) {
    return metas.map((m) {
      final active = m.section.index == currentIndex;
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(m.icon,
            color: active ? m.brandColor : const Color(0xFFE8E6E0), size: 22),
        title: Text(
          m.label,
          style: TextStyle(
            color: active ? m.brandColor : const Color(0xFFE8E6E0),
            fontSize: 15,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        trailing: active
            ? const Icon(Icons.check, color: Color(0xFFD4AF37), size: 18)
            : null,
        onTap: () {
          Navigator.of(ctx).pop();
          onSelectSection(m.section.index);
        },
      );
    }).toList();
  }
}

/// Gold "Perilla" button on the left edge. In Release A tapping it opens the
/// section list; in Release B it becomes the draggable curved dial.
class _PerillaButton extends StatelessWidget {
  const _PerillaButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF4D774), Color(0xFFA67C1A)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.45),
              blurRadius: 16,
              spreadRadius: -2,
            ),
            const BoxShadow(
              color: Color(0x66000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child:
            const Icon(Icons.menu_rounded, color: Color(0xFF231A06), size: 26),
      ),
    );
  }
}
