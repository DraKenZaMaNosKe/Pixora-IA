import 'dart:math';
import 'package:flutter/material.dart';

enum LoadingPhase { downloading, sprites, installing, done, error }

class LoadingOverlay extends StatefulWidget {
  final bool visible;
  final double? progress;
  final String status;
  final Color accentColor;
  final LoadingPhase phase;

  const LoadingOverlay({
    super.key,
    required this.visible,
    this.progress,
    this.status = '',
    this.accentColor = const Color(0xFF7C4DFF),
    this.phase = LoadingPhase.downloading,
  });

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _checkController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkAnimation = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void didUpdateWidget(LoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase == LoadingPhase.done &&
        oldWidget.phase != LoadingPhase.done) {
      _checkController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  IconData _phaseIcon() {
    switch (widget.phase) {
      case LoadingPhase.downloading:
        return Icons.cloud_download_rounded;
      case LoadingPhase.sprites:
        return Icons.auto_awesome;
      case LoadingPhase.installing:
        return Icons.wallpaper_rounded;
      case LoadingPhase.done:
        return Icons.check_circle_rounded;
      case LoadingPhase.error:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    final isDone = widget.phase == LoadingPhase.done;
    final isError = widget.phase == LoadingPhase.error;
    final accent = isError ? Colors.redAccent : widget.accentColor;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: widget.visible ? 1.0 : 0.0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 44),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: accent.withValues(alpha: 0.35), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.2),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildIndicator(isDone, isError, accent),
                const SizedBox(height: 20),
                if (widget.status.isNotEmpty)
                  Text(
                    widget.status,
                    style: TextStyle(
                      color: isDone ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight:
                          isDone ? FontWeight.w600 : FontWeight.normal,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                if (!isDone && !isError) ...[
                  const SizedBox(height: 16),
                  _buildProgressBar(accent),
                  const SizedBox(height: 10),
                  _buildPhaseSteps(accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIndicator(bool isDone, bool isError, Color accent) {
    if (isDone) {
      return ScaleTransition(
        scale: _checkAnimation,
        child: Icon(Icons.check_circle_rounded, color: Colors.greenAccent,
            size: 52),
      );
    }

    if (isError) {
      return Icon(Icons.error_outline_rounded, color: Colors.redAccent,
          size: 52);
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, child) {
        final scale = _pulseAnimation.value;
        return Transform.scale(
          scale: 0.9 + scale * 0.1,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.3 * scale),
                  blurRadius: 20 * scale,
                  spreadRadius: 2 * scale,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: widget.progress,
                    strokeWidth: 3,
                    color: accent,
                    backgroundColor: Colors.white12,
                  ),
                ),
                Icon(_phaseIcon(), color: accent, size: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressBar(Color accent) {
    final p = widget.progress ?? 0.0;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: p > 0 ? p : null,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
            minHeight: 5,
          ),
        ),
        if (p > 0 && p < 1) ...[
          const SizedBox(height: 6),
          Text(
            '${(p * 100).toInt()}%',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPhaseSteps(Color accent) {
    final steps = <_StepData>[
      _StepData('Download', LoadingPhase.downloading),
      _StepData('Sprites', LoadingPhase.sprites),
      _StepData('Install', LoadingPhase.installing),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Container(
              width: 20,
              height: 1,
              color: _stepDone(steps[i].phase)
                  ? accent.withValues(alpha: 0.6)
                  : Colors.white12,
            ),
          _buildStep(steps[i], accent),
        ],
      ],
    );
  }

  bool _stepDone(LoadingPhase step) {
    return step.index < widget.phase.index;
  }

  bool _stepActive(LoadingPhase step) {
    return step == widget.phase;
  }

  Widget _buildStep(_StepData step, Color accent) {
    final done = _stepDone(step.phase);
    final active = _stepActive(step.phase);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                done ? accent : (active ? accent.withValues(alpha: 0.2) : Colors.white10),
            border: active
                ? Border.all(color: accent, width: 2)
                : null,
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : (active
                    ? Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: accent),
                      )
                    : null),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          step.label,
          style: TextStyle(
            color: done || active ? Colors.white60 : Colors.white24,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _StepData {
  final String label;
  final LoadingPhase phase;
  const _StepData(this.label, this.phase);
}
