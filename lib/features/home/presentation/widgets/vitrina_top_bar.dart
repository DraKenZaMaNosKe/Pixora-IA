import 'package:flutter/material.dart';

/// Floating top row for the Vitrina home — avatar on the left, glass pills on
/// the right (optional trailing action, Free Hour chip, credits, and a gear
/// that opens Settings). Sits on top of the full-bleed content, so keep it slim
/// and let the wallpaper breathe underneath.
///
/// The big section title does NOT live here (it moves to the hero block near
/// the bottom in Release B). This bar only carries identity + wallet + settings.
class VitrinaTopBar extends StatelessWidget {
  const VitrinaTopBar({
    super.key,
    required this.avatar,
    required this.creditsBadge,
    required this.onSettingsTap,
    this.freeHourChip = const SizedBox.shrink(),
    this.trailingIcon,
    this.onTrailingTap,
  });

  /// The identity avatar (already wired to open Perfil on tap).
  final Widget avatar;

  /// The diamonds/credits badge (already wired to open the wallet sheet).
  final Widget creditsBadge;

  /// Opens Settings (the gear replaces the old Ajustes tab).
  final VoidCallback onSettingsTap;

  /// Free Hour countdown chip — collapses to zero space when off/premium.
  final Widget freeHourChip;

  /// Optional context action icon (e.g. search on the Estáticos section).
  final IconData? trailingIcon;

  /// Tap handler for [trailingIcon].
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.only(top: topPad + 8, left: 12, right: 12, bottom: 8),
      child: Row(
        children: [
          avatar,
          const Spacer(),
          if (trailingIcon != null) ...[
            _GlassButton(
              onTap: onTrailingTap,
              child:
                  Icon(trailingIcon, color: const Color(0xFFE8E6E0), size: 20),
            ),
            const SizedBox(width: 8),
          ],
          freeHourChip,
          const SizedBox(width: 8),
          creditsBadge,
          const SizedBox(width: 8),
          _GlassButton(
            onTap: onSettingsTap,
            child: const Icon(Icons.settings_outlined,
                color: Color(0xFFE8E6E0), size: 20),
          ),
        ],
      ),
    );
  }
}

/// Small glass-morphism pill button used for the gear and the trailing action.
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x33000000),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x33D4AF37), width: 1),
        ),
        child: child,
      ),
    );
  }
}
