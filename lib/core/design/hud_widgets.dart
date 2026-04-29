import 'package:flutter/material.dart';

import 'hud_shapes.dart';
import 'hud_tokens.dart';

/// Primary CTA button — accent filled, corner-cut, mono arrow on the right.
///
///   [ CREAR OTRA           ↗ ]
class HudPrimaryButton extends StatelessWidget {
  const HudPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.cut = HudTokens.cornerCutMd,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final double cut;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return SizedBox(
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(h.isIosStyle ? 14 : 0),
        child: ClipPath(
          clipper: CornerCutClipper(cut: h.isIosStyle ? 0 : cut),
          child: Material(
            color: h.accent,
            child: InkWell(
              onTap: busy ? null : onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HudTokens.sp6,
                  vertical: HudTokens.sp5,
                ),
                child: Row(
                  mainAxisAlignment: h.isIosStyle
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.spaceBetween,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 18),
                      const SizedBox(width: HudTokens.sp3),
                    ],
                    if (h.isIosStyle)
                      Text(
                        label,
                        style: HudTokens.body(
                          size: 16,
                          weight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      )
                    else
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          style: HudTokens.display(
                            size: 15,
                            weight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.05,
                          ),
                        ),
                      ),
                    if (busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else if (!h.isIosStyle)
                      Text(
                        '↗',
                        style: HudTokens.mono(
                          size: 20,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action button — ghost style, thin border, hover fills accent.
/// Usually stacked in a row of 3: guardar, wallpaper, compartir.
class HudGhostButton extends StatelessWidget {
  const HudGhostButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.cut = HudTokens.cornerCutSm,
  });

  final String label;
  final String icon; // any glyph — we control font via theme
  final VoidCallback? onPressed;
  final double cut;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    return ClipRRect(
      borderRadius: BorderRadius.circular(isIos ? 12 : 0),
      child: ClipPath(
        clipper: CornerCutClipper(cut: isIos ? 0 : cut),
        child: Material(
          color: isIos ? h.surface : h.surface,
          child: InkWell(
            onTap: onPressed,
            splashColor: h.accent.withValues(alpha: 0.2),
            child: Container(
              decoration: BoxDecoration(
                border: isIos ? null : Border.all(color: h.divider, width: 1),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: HudTokens.sp2,
                vertical: HudTokens.sp4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    icon,
                    style: TextStyle(color: h.accent, fontSize: 22, height: 1),
                  ),
                  const SizedBox(height: HudTokens.sp2),
                  Text(
                    isIos ? label : label.toUpperCase(),
                    style: HudTokens.mono(
                      size: isIos ? 11 : 10,
                      weight: isIos ? FontWeight.w600 : FontWeight.w500,
                      color: h.text,
                      letterSpacing: isIos ? -0.1 : 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small stat chip: "LV.24" or "120 ◆" or "9:16".
class HudStatChip extends StatelessWidget {
  const HudStatChip({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: HudTokens.mono(
            size: 10,
            color: h.textDim,
            letterSpacing: 0.15,
          ),
        ),
        const SizedBox(width: HudTokens.sp1),
        Text(
          value,
          style: HudTokens.mono(
            size: 11,
            weight: FontWeight.w700,
            color: color ?? h.accent2,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

/// Small rectangular badge: "NEW", "LV.8", "LIVE", "RARE".
class HudBadge extends StatelessWidget {
  const HudBadge({
    super.key,
    required this.text,
    this.color,
    this.onColor,
  });

  final String text;
  final Color? color;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final bg = color ?? h.accent;
    final fg = onColor ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HudTokens.sp2,
        vertical: 3,
      ),
      color: bg,
      child: Text(
        text.toUpperCase(),
        style: HudTokens.mono(
          size: 9,
          weight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}

/// Section header row: "// TRENDING" plus a trailing "[ VER TODO ]".
class HudSectionHeader extends StatelessWidget {
  const HudSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onActionTap,
  });

  final String title;
  final String? action;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HudTokens.sp5,
        vertical: HudTokens.sp3,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: h.divider, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '// ',
            style: HudTokens.display(
              size: 13,
              color: h.accent,
              letterSpacing: 0.08,
            ),
          ),
          Text(
            title.toUpperCase(),
            style: HudTokens.display(
              size: 13,
              color: h.text,
              letterSpacing: 0.08,
            ),
          ),
          const Spacer(),
          if (action != null)
            GestureDetector(
              onTap: onActionTap,
              child: Text(
                '[ ${action!.toUpperCase()} ]',
                style: HudTokens.mono(
                  size: 10,
                  weight: FontWeight.w700,
                  color: h.accent2,
                  letterSpacing: 0.1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// HUD-style status overlay that sits in the top-right of a hero panel.
///   [ ▲ LOADED ]
class HudStatusTag extends StatelessWidget {
  const HudStatusTag({super.key, required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final c = color ?? h.accent;
    return Container(
      decoration: BoxDecoration(
        color: h.bg.withValues(alpha: 0.7),
        border: Border.all(color: c, width: 1),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: HudTokens.sp2,
        vertical: 3,
      ),
      child: Text(
        text.toUpperCase(),
        style: HudTokens.mono(
          size: 9,
          weight: FontWeight.w700,
          color: c,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}
