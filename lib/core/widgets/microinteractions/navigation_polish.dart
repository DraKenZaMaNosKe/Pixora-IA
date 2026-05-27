import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────
// M14 — Tab Slide Content (replaces cut transitions)
// ─────────────────────────────────────────────────────────────────────

/// Wrapper que hace slide-in del contenido cuando cambia el valor de
/// [activeIndex]. Drop-in para reemplazar `IndexedStack` cuando quieres
/// transición visible al cambiar de tab.
class TabSlideContent extends StatefulWidget {
  const TabSlideContent({
    super.key,
    required this.activeIndex,
    required this.children,
    this.duration = const Duration(milliseconds: 350),
  });

  final int activeIndex;
  final List<Widget> children;
  final Duration duration;

  @override
  State<TabSlideContent> createState() => _TabSlideContentState();
}

class _TabSlideContentState extends State<TabSlideContent> {
  int _previousIndex = 0;

  @override
  void didUpdateWidget(TabSlideContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      _previousIndex = oldWidget.activeIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: widget.duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final forward = widget.activeIndex >= _previousIndex;
        final offset = Tween<Offset>(
          begin: Offset(forward ? 0.08 : -0.08, 0),
          end: Offset.zero,
        ).animate(animation);
        return SlideTransition(
          position: offset,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(widget.activeIndex),
        child: widget.children[widget.activeIndex],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// M15 — Hero Card → Preview (built-in Flutter Hero with custom curve)
// ─────────────────────────────────────────────────────────────────────

/// Hero animation con curve más cinematic que la default. Envuelve la card
/// origen y la pantalla destino con el mismo tag.
class CinematicHero extends StatelessWidget {
  const CinematicHero({
    super.key,
    required this.tag,
    required this.child,
  });

  final Object tag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      flightShuttleBuilder: (
        ctx,
        animation,
        flightDirection,
        fromCtx,
        toCtx,
      ) {
        return AnimatedBuilder(
          animation: animation,
          builder: (_, __) {
            final t = Curves.easeOutQuart.transform(animation.value);
            return Material(
              type: MaterialType.transparency,
              child: Transform.scale(
                scale: 1.0 + t * 0.05,
                child: child,
              ),
            );
          },
        );
      },
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// M17 — First Apply Tutorial Tooltip
// ─────────────────────────────────────────────────────────────────────

/// Tooltip flotante con flecha + dedo apuntando. Se muestra como overlay
/// la PRIMERA vez que algo pasa (ej: primer wallpaper aplicado → "Toca ♡
/// para favoritos"). Persiste hasta que el usuario lo dismisa.
class TutorialTooltip extends StatefulWidget {
  const TutorialTooltip({
    super.key,
    required this.message,
    required this.onDismiss,
    this.fingerEmoji = '👆',
  });

  final String message;
  final VoidCallback onDismiss;
  final String fingerEmoji;

  @override
  State<TutorialTooltip> createState() => _TutorialTooltipState();
}

class _TutorialTooltipState extends State<TutorialTooltip>
    with SingleTickerProviderStateMixin {
  static const Color _amber = Color(0xFFFFB400);
  static const Color _amberBright = Color(0xFFFFD66B);

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final t = _ctrl.value;
              return Transform.translate(
                offset: Offset(0, -4 * t),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3A2812), Color(0xFF1A1208)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _amber),
                    boxShadow: [
                      BoxShadow(
                        color: _amber.withValues(alpha: 0.2),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Text(
                    widget.message,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: _amberBright,
                    ),
                  ),
                ),
              );
            },
          ),
          // Arrow
          CustomPaint(
            size: const Size(12, 6),
            painter: _TooltipArrow(color: _amber),
          ),
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final t = _ctrl.value;
              final scale = 1.0 - t * 0.15;
              return Transform.translate(
                offset: Offset(0, 4 * t),
                child: Transform.scale(
                  scale: scale,
                  child: Text(
                    widget.fingerEmoji,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TooltipArrow extends CustomPainter {
  _TooltipArrow({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TooltipArrow old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────
// M19 — Long Press Context Menu (radial-ish stagger)
// ─────────────────────────────────────────────────────────────────────

/// Menú contextual con stagger animation. Se llama desde un GestureDetector
/// onLongPress sobre una card, retorna el index del item elegido o null.
class ContextMenu {
  static Future<int?> show({
    required BuildContext context,
    required Offset position,
    required List<ContextMenuItem> items,
  }) {
    return showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim, _) {
        return _ContextMenuOverlay(
          position: position,
          items: items,
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        return Opacity(opacity: anim.value, child: child);
      },
    );
  }
}

class ContextMenuItem {
  ContextMenuItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _ContextMenuOverlay extends StatelessWidget {
  const _ContextMenuOverlay({required this.position, required this.items});
  final Offset position;
  final List<ContextMenuItem> items;

  static const Color _amberBright = Color(0xFFFFD66B);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: position.dx - 70,
          top: position.dy - 100,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0A12).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _amberBright.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 40,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(items.length, (i) {
                  return _StaggerItem(
                    delay: Duration(milliseconds: 50 * i),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(i),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(items[i].icon,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.7)),
                            const SizedBox(width: 8),
                            Text(
                              items[i].label,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StaggerItem extends StatefulWidget {
  const _StaggerItem({required this.delay, required this.child});
  final Duration delay;
  final Widget child;
  @override
  State<_StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<_StaggerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        return Opacity(
          opacity: _ctrl.value,
          child: Transform.translate(
            offset: Offset(-8 * (1 - _ctrl.value), 0),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// M21 — New Day Greeting Staggered Cards
// ─────────────────────────────────────────────────────────────────────

/// Bienvenida cuando el usuario abre la app después de medianoche. Texto
/// "Buenos días, hay N nuevos" + cards con stagger entrando una por una.
/// Drop-in arriba del grid principal cuando es nuevo día.
class NewDayGreeting extends StatelessWidget {
  const NewDayGreeting({
    super.key,
    required this.newCount,
    required this.children,
    this.message = 'Buenos días, hay',
  });

  final int newCount;
  final String message;
  final List<Widget> children;

  static const Color _cream = Color(0xFFF0E6D2);
  static const Color _amberBright = Color(0xFFFFD66B);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          builder: (_, t, child) {
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - t)),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$message '),
                  TextSpan(
                    text: '$newCount nuevos',
                    style: TextStyle(
                      color: _amberBright,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: _cream,
              ),
            ),
          ),
        ),
        // Stagger cards
        for (var i = 0; i < children.length; i++)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 500 + i * 100),
            curve: Curves.easeOut,
            builder: (_, t, child) {
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - t)),
                  child: Transform.scale(
                    scale: 0.9 + t * 0.1,
                    child: child,
                  ),
                ),
              );
            },
            child: children[i],
          ),
      ],
    );
  }
}
