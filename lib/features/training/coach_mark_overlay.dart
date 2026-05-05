import 'package:flutter/material.dart';
import '../../core/design/hud_tokens.dart';
import 'training_service.dart';

/// Single step of a coach-mark tour: which widget to spotlight, what to
/// say, and (optionally) a custom hole shape.
class CoachStep {
  /// GlobalKey of the widget being highlighted. Its bounding box becomes
  /// the "hole" in the dark overlay.
  final GlobalKey targetKey;

  /// Title above the body text. Short, often a single word.
  final String title;

  /// Body — explains what the target does. 1-2 short sentences.
  final String body;

  /// 'circle' for round targets (FAB, avatar) — 'rrect' for cards/buttons.
  final CoachHoleShape shape;

  /// Extra padding around the target before drawing the hole, in logical px.
  final double padding;

  const CoachStep({
    required this.targetKey,
    required this.title,
    required this.body,
    this.shape = CoachHoleShape.rrect,
    this.padding = 6,
  });
}

enum CoachHoleShape { circle, rrect }

/// Full-screen overlay with a dark scrim, a transparent hole carved out
/// over the current step's target widget, and a floating tooltip card
/// with title + body + Skip / Next buttons.
///
/// Insert via `Overlay.of(context).insert(OverlayEntry(builder: (_) =>
/// CoachMarkOverlay(steps: ..., onFinish: ...)))` from the HomePage post-
/// frame callback.
class CoachMarkOverlay extends StatefulWidget {
  const CoachMarkOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
  });

  final List<CoachStep> steps;

  /// Called when the user reaches the last step's "Listo" or taps "Saltar"
  /// at any point. Receives `completed=true` if all steps were viewed,
  /// `false` if skipped.
  final void Function(bool completed) onFinish;

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fade.forward();
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= widget.steps.length - 1) {
      _finish(true);
    } else {
      setState(() => _index++);
    }
  }

  Future<void> _finish(bool completed) async {
    await _fade.reverse();
    await TrainingService.instance.markSeen();
    if (mounted) widget.onFinish(completed);
  }

  Rect _targetRect(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return Rect.zero;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return Rect.zero;
    final position = box.localToGlobal(Offset.zero);
    return position & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final step = widget.steps[_index];
    final raw = _targetRect(step.targetKey);
    if (raw == Rect.zero) {
      // Target not laid out yet — fallback skip
      WidgetsBinding.instance.addPostFrameCallback((_) => _next());
      return const SizedBox.shrink();
    }
    final target = raw.inflate(step.padding);
    final tooltipPos = _tooltipPosition(target, mq.size);

    return FadeTransition(
      opacity: _fade,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Dark scrim with cut-out
            Positioned.fill(
              child: GestureDetector(
                onTap: _next, // tap anywhere outside tooltip = next
                child: CustomPaint(
                  painter: _ScrimPainter(
                    holeRect: target,
                    shape: step.shape,
                  ),
                ),
              ),
            ),
            // Pulse ring around the target (subtle attention pull)
            _PulseRing(rect: target, shape: step.shape),

            // Tooltip card
            Positioned(
              left: tooltipPos.dx,
              top: tooltipPos.dy,
              width: mq.size.width - 36,
              child: _TooltipCard(
                title: step.title,
                body: step.body,
                stepIndex: _index,
                stepCount: widget.steps.length,
                onSkip: () => _finish(false),
                onNext: _next,
                isLast: _index == widget.steps.length - 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Place the tooltip below the target if there's room; above if not.
  /// Width is fixed to screen width minus margin; horizontal position is
  /// always 18px from left for consistency.
  Offset _tooltipPosition(Rect target, Size screen) {
    const horizontalMargin = 18.0;
    const verticalGap = 22.0;
    const tooltipHeight = 180.0; // approximate, used for fit decision
    final spaceBelow = screen.height - target.bottom;
    final placeBelow = spaceBelow >= tooltipHeight + verticalGap + 60;
    final y = placeBelow
        ? target.bottom + verticalGap
        : (target.top - verticalGap - tooltipHeight)
            .clamp(MediaQuery.of(context).padding.top + 12, screen.height);
    return Offset(horizontalMargin, y);
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.holeRect, required this.shape});
  final Rect holeRect;
  final CoachHoleShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.78);
    final fullPath = Path()..addRect(Offset.zero & size);
    final hole = Path();
    if (shape == CoachHoleShape.circle) {
      final radius = holeRect.shortestSide / 2 + 6;
      hole.addOval(Rect.fromCircle(center: holeRect.center, radius: radius));
    } else {
      hole.addRRect(
          RRect.fromRectAndRadius(holeRect, const Radius.circular(14)));
    }
    final combined = Path.combine(PathOperation.difference, fullPath, hole);
    canvas.drawPath(combined, scrim);
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) =>
      old.holeRect != holeRect || old.shape != shape;
}

class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.rect, required this.shape});
  final Rect rect;
  final CoachHoleShape shape;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
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
      builder: (_, __) {
        final t = _ctrl.value; // 0..1
        final inflate = 4 + 14 * t;
        final opacity = (1 - t).clamp(0.0, 1.0);
        final r = widget.rect.inflate(inflate);
        return Positioned(
          left: r.left,
          top: r.top,
          width: r.width,
          height: r.height,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: widget.shape == CoachHoleShape.circle
                    ? BoxShape.circle
                    : BoxShape.rectangle,
                borderRadius: widget.shape == CoachHoleShape.rrect
                    ? BorderRadius.circular(14 + inflate * 0.6)
                    : null,
                border: Border.all(
                  color:
                      const Color(0xFFD9B14A).withValues(alpha: opacity * 0.7),
                  width: 2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.title,
    required this.body,
    required this.stepIndex,
    required this.stepCount,
    required this.onSkip,
    required this.onNext,
    required this.isLast,
  });

  final String title;
  final String body;
  final int stepIndex;
  final int stepCount;
  final VoidCallback onSkip;
  final VoidCallback onNext;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: h.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: h.accent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${stepIndex + 1} / $stepCount',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: h.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onSkip,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Saltar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: h.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: h.text,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: h.textDim,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: h.accent,
                foregroundColor: h.isDark ? Colors.black : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              child: Text(
                isLast ? '¡Listo!' : 'Siguiente →',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
