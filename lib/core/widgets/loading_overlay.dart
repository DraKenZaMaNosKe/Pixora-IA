import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/design/hud_tokens.dart';
import '../utils/locale_helper.dart';

enum LoadingPhase { downloading, sprites, installing, done, error }

/// Editorial Bauhaus loading overlay.
///
/// Eduardo eligió este de 5 conceptos el 2026-05-15. Restraint suizo:
/// mono percent grande izquierda + eyebrow mono derecha + título italic
/// Fraunces + barra oro firme + retícula 01·02·03 + status dot pulsante.
///
/// Compartido por TODAS las features que descargan: stories, wallpapers,
/// hot_wallpapers, ringtones, day_cycle, aura. La paleta es siempre gold
/// — el parámetro `accentColor` se ignora (se mantiene por API compat).
class LoadingOverlay extends StatefulWidget {
  final bool visible;
  final double? progress;
  final String status;
  final Color accentColor; // ignored — kept for API compat
  final LoadingPhase phase;

  const LoadingOverlay({
    super.key,
    required this.visible,
    this.progress,
    this.status = '',
    this.accentColor = HudTokens.gold,
    this.phase = LoadingPhase.downloading,
  });

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _checkController;
  late AnimationController _barShimmerController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(
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

    _barShimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
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
    _barShimmerController.dispose();
    super.dispose();
  }

  String _eyebrowLabel() {
    switch (widget.phase) {
      case LoadingPhase.downloading:
        return LocaleHelper.pick(es: 'DESCARGANDO', en: 'DOWNLOADING');
      case LoadingPhase.sprites:
        return LocaleHelper.pick(es: 'PROCESANDO', en: 'PROCESSING');
      case LoadingPhase.installing:
        return LocaleHelper.pick(es: 'INSTALANDO', en: 'INSTALLING');
      case LoadingPhase.done:
        return LocaleHelper.pick(es: 'LISTO', en: 'DONE');
      case LoadingPhase.error:
        return LocaleHelper.pick(es: 'ERROR', en: 'ERROR');
    }
  }

  int _activeStepIndex() {
    switch (widget.phase) {
      case LoadingPhase.downloading:
        return 0;
      case LoadingPhase.sprites:
        return 1;
      case LoadingPhase.installing:
        return 2;
      case LoadingPhase.done:
        return 3;
      case LoadingPhase.error:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    final isDone = widget.phase == LoadingPhase.done;
    final isError = widget.phase == LoadingPhase.error;
    final p = widget.progress ?? 0.0;
    final percent = (p * 100).clamp(0, 100).toInt();

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: widget.visible ? 1.0 : 0.0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            decoration: BoxDecoration(
              color: const Color(0xFF070710),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: HudTokens.gold.withValues(alpha: 0.30),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDone)
                  _buildDoneState()
                else if (isError)
                  _buildErrorState()
                else ...[
                  _buildHeader(percent),
                  const SizedBox(height: 10),
                  _buildTitle(),
                  const SizedBox(height: 22),
                  _buildBar(p),
                  const SizedBox(height: 22),
                  _buildSteps(),
                  const SizedBox(height: 12),
                  _buildStatusLine(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int percent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Big mono percent (left)
        Text(
          '$percent',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 56,
            fontWeight: FontWeight.w300,
            color: HudTokens.goldBright,
            height: 0.95,
            letterSpacing: -2,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '%',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 18,
              fontWeight: FontWeight.w400,
              color: HudTokens.gold.withValues(alpha: 0.7),
              height: 1,
            ),
          ),
        ),
        const Spacer(),
        // Eyebrow (right)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _eyebrowLabel(),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: HudTokens.gold,
              letterSpacing: 2.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitle() {
    final raw = widget.status.isEmpty
        ? LocaleHelper.pick(es: 'Descargando', en: 'Downloading')
        : widget.status;
    return Text(
      raw,
      style: GoogleFonts.fraunces(
        fontSize: 16,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        color: Colors.white.withValues(alpha: 0.92),
        height: 1.25,
        letterSpacing: -0.2,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildBar(double p) {
    return SizedBox(
      height: 6,
      child: AnimatedBuilder(
        animation: _barShimmerController,
        builder: (_, __) {
          return Stack(
            children: [
              Positioned.fill(
                child: Container(color: Colors.white.withValues(alpha: 0.05)),
              ),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: p > 0 ? p.clamp(0.0, 1.0) : null,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        HudTokens.gold,
                        HudTokens.goldBright,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: HudTokens.goldBright.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
              // Bright leading edge
              if (p > 0 && p < 1)
                Positioned(
                  left: (MediaQuery.of(context).size.width - 96) * p - 1,
                  top: -2,
                  bottom: -2,
                  child: Container(
                    width: 2,
                    color: const Color(0xFFFFE89A),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSteps() {
    final steps = <_StepData>[
      _StepData('01', LocaleHelper.pick(es: 'Bajada', en: 'Download')),
      _StepData('02', LocaleHelper.pick(es: 'Frames', en: 'Sprites')),
      _StepData('03', LocaleHelper.pick(es: 'Listo', en: 'Install')),
    ];

    final activeIdx = _activeStepIndex();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: HudTokens.gold.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(
              child: Container(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(
                          left: BorderSide(
                            color: HudTokens.gold.withValues(alpha: 0.12),
                            width: 1,
                          ),
                        ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      steps[i].num,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: i == activeIdx
                            ? HudTokens.goldBright
                            : (i < activeIdx
                                ? HudTokens.goldDeep
                                : Colors.white.withValues(alpha: 0.18)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      steps[i].label.toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                        color: i == activeIdx
                            ? HudTokens.goldBright
                            : (i < activeIdx
                                ? HudTokens.goldDeep
                                : Colors.white.withValues(alpha: 0.18)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusLine() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (_, __) {
            return Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HudTokens.goldBright
                    .withValues(alpha: _pulseAnimation.value),
                boxShadow: [
                  BoxShadow(
                    color: HudTokens.goldBright
                        .withValues(alpha: 0.5 * _pulseAnimation.value),
                    blurRadius: 6,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        Text(
          LocaleHelper.pick(es: 'en progreso', en: 'in progress'),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.45),
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _buildDoneState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ScaleTransition(
              scale: _checkAnimation,
              child: const Icon(
                Icons.check_rounded,
                color: HudTokens.goldBright,
                size: 32,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              LocaleHelper.pick(es: 'LISTO', en: 'DONE'),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: HudTokens.gold,
                letterSpacing: 2.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          widget.status.isEmpty
              ? LocaleHelper.pick(es: 'Completado', en: 'Completed')
              : widget.status,
          style: GoogleFonts.fraunces(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.92),
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: HudTokens.goldDeep,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              LocaleHelper.pick(es: 'ERROR', en: 'ERROR'),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: HudTokens.goldDeep,
                letterSpacing: 2.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          widget.status.isEmpty
              ? LocaleHelper.pick(
                  es: 'Algo salió mal',
                  en: 'Something went wrong',
                )
              : widget.status,
          style: GoogleFonts.fraunces(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.92),
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _StepData {
  final String num;
  final String label;
  const _StepData(this.num, this.label);
}
