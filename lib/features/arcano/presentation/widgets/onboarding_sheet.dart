import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/user_profile_service.dart';

/// Onboarding modal — Iridescent Liquid Metal (concept #05 v2, Eduardo
/// 2026-05-16). Always uses the dark variant for both themes since the
/// iridescent text effect needs a dark canvas to shine. Premium 2026 vibe
/// (Apple Vision Pro launch keynote).
///
/// - Background: deep ink gradient (#0A0512 → #050308)
/// - Title "Bienvenido." Fraunces italic with ANIMATED iridescent fill
///   (pink → lavender → cyan → mint cycling) + liquid sheen sweep
/// - Inputs: minimal underline (no boxes)
/// - CTA: cream-glass pill with subtle iridescent border
class ArcanoOnboardingSheet extends StatefulWidget {
  const ArcanoOnboardingSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    // 2026-05-16: non-dismissable + explicit close (X) button. A phantom
    // tap-outside was closing the modal at ~1.2s when isDismissible was
    // true (likely the launching tap propagating to the barrier).
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const ArcanoOnboardingSheet(),
    );
    return result ?? false;
  }

  @override
  State<ArcanoOnboardingSheet> createState() => _ArcanoOnboardingSheetState();
}

class _ArcanoOnboardingSheetState extends State<ArcanoOnboardingSheet> {
  static const _bgTop = Color(0xFF0A0512);
  static const _bgBot = Color(0xFF050308);
  static const _cyanAccent = Color(0xFF67E8F9);
  static const _iridescent = [
    Color(0xFFEC4899), // pink
    Color(0xFFC4B5FD), // lavender
    Color(0xFF67E8F9), // cyan
    Color(0xFFA7F3D0), // mint
    Color(0xFFEC4899), // back to pink
  ];

  final _nameCtrl = TextEditingController();
  DateTime? _birthDate;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty && _birthDate != null && !_saving;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1925),
      lastDate: DateTime(now.year - 5, now.month, now.day),
      initialDate: _birthDate ?? DateTime(1995, 1, 1),
      helpText: 'Tu fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _cyanAccent,
              onPrimary: Color(0xFF050308),
              surface: Color(0xFF14101A),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF14101A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      await UserProfileService.instance.save(
        name: _nameCtrl.text.trim(),
        birthDate: _birthDate!,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBot],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.86,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top row: drag handle (visual) + Close (X) button so
                  // the user has a clear exit path. Modal is otherwise
                  // non-dismissable (no tap-outside, no swipe).
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(false),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.08),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white70, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Eyebrow
                  Text(
                    'PIXORA · ONBOARDING',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      letterSpacing: 3.0,
                      color: _cyanAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Iridescent animated title
                  const _IridescentTitle('Bienvenido.'),
                  const SizedBox(height: 10),

                  // Description
                  Text(
                    'Dos datos para abrir tu mundo: galería personalizada, '
                    'calendario zodiacal y horóscopo diario.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.65),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 26),

                  // Name field
                  const _MinimalLabel('NOMBRE'),
                  const SizedBox(height: 4),
                  _MinimalUnderlineField(
                    controller: _nameCtrl,
                    hintText: 'Eduardo',
                    // 2026-05-16: autofocus removed so the keyboard
                    // doesn't pop the moment the modal opens (caused
                    // viewInsets rebuilds + possibly the phantom dismiss).
                    autofocus: false,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 18),

                  // Birth date
                  const _MinimalLabel('FECHA DE NACIMIENTO'),
                  const SizedBox(height: 4),
                  _MinimalUnderlineDate(
                    date: _birthDate,
                    onTap: _pickDate,
                  ),

                  // Live zodiac preview
                  if (_birthDate != null) ...[
                    const SizedBox(height: 12),
                    _ZodiacPreview(date: _birthDate!),
                  ],
                  const SizedBox(height: 26),

                  // CTA
                  _IridescentCta(
                    enabled: _canSave,
                    saving: _saving,
                    onTap: _save,
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      'Datos locales · cifrados en tu dispositivo',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        letterSpacing: 0.5,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
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

// ═════════════════════════════════════════════════════════════════════
// Iridescent animated title — Fraunces italic with shifting gradient fill
// + diagonal liquid sheen sweep.
// ═════════════════════════════════════════════════════════════════════
class _IridescentTitle extends StatefulWidget {
  const _IridescentTitle(this.text);
  final String text;

  @override
  State<_IridescentTitle> createState() => _IridescentTitleState();
}

class _IridescentTitleState extends State<_IridescentTitle>
    with TickerProviderStateMixin {
  late final AnimationController _hue;
  late final AnimationController _sheen;

  @override
  void initState() {
    super.initState();
    _hue = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _sheen = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
  }

  @override
  void dispose() {
    _hue.dispose();
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.fraunces(
      fontSize: 38,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w500,
      color: Colors.white,
      letterSpacing: -0.5,
      height: 1.05,
    );

    return Stack(
      children: [
        // Iridescent gradient text — RepaintBoundary so the 60fps
        // ShaderMask doesn't trigger the whole modal to repaint each frame.
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _hue,
            builder: (_, __) {
              final shift = (_hue.value * 2.0) - 1.0;
              return ShaderMask(
                shaderCallback: (bounds) {
                  return LinearGradient(
                    begin: Alignment(-1.0 + shift, -0.2),
                    end: Alignment(1.0 + shift, 0.2),
                    colors: _ArcanoOnboardingSheetState._iridescent,
                    stops: const [0.0, 0.25, 0.50, 0.75, 1.0],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.srcIn,
                child: Text(widget.text, style: style),
              );
            },
          ),
        ),
        // Liquid sheen sweep overlay
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _sheen,
                builder: (_, __) {
                  final v = _sheen.value;
                  final double t;
                  final double opacity;
                  if (v < 0.65) {
                    t = -1.2;
                    opacity = 0;
                  } else if (v < 0.85) {
                    final p = (v - 0.65) / 0.20;
                    t = -1.2 + p * 2.4;
                    opacity = (1 - (p - 0.5).abs() * 2) * 0.55;
                  } else {
                    t = 1.2;
                    opacity = 0;
                  }
                  return FractionalTranslation(
                    translation: Offset(t, 0),
                    child: Opacity(
                      opacity: opacity,
                      child: ShaderMask(
                        shaderCallback: (bounds) {
                          return const LinearGradient(
                            begin: Alignment(-0.5, -1),
                            end: Alignment(0.5, 1),
                            colors: [
                              Colors.transparent,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0.30, 0.50, 0.70],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.srcIn,
                        child: Text(widget.text, style: style),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MinimalLabel extends StatelessWidget {
  const _MinimalLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 9,
        letterSpacing: 2.4,
        color: Colors.white.withValues(alpha: 0.5),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _MinimalUnderlineField extends StatelessWidget {
  const _MinimalUnderlineField({
    required this.controller,
    required this.hintText,
    required this.autofocus,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hintText;
  final bool autofocus;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    const cyan = _ArcanoOnboardingSheetState._cyanAccent;
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      textCapitalization: TextCapitalization.words,
      autofocus: autofocus,
      cursorColor: cyan,
      style: GoogleFonts.inter(
        fontSize: 18,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        hintText: hintText,
        hintStyle: GoogleFonts.inter(
          fontSize: 18,
          color: Colors.white.withValues(alpha: 0.25),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: cyan, width: 1.5),
        ),
      ),
    );
  }
}

class _MinimalUnderlineDate extends StatelessWidget {
  const _MinimalUnderlineDate({required this.date, required this.onTap});
  final DateTime? date;
  final VoidCallback onTap;

  static const _months = [
    '',
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    final label = hasDate
        ? '${date!.day.toString().padLeft(2, '0')} / ${_months[date!.month]} / ${date!.year}'
        : 'Toca para escoger';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    color: hasDate
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.25),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.4),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IridescentCta extends StatefulWidget {
  const _IridescentCta({
    required this.enabled,
    required this.saving,
    required this.onTap,
  });
  final bool enabled;
  final bool saving;
  final VoidCallback onTap;

  @override
  State<_IridescentCta> createState() => _IridescentCtaState();
}

class _IridescentCtaState extends State<_IridescentCta>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.enabled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.enabled ? widget.onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: disabled
                ? LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0.08),
                    ],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFE9F2F5),
                      Color(0xFFCDE5EC),
                      Color(0xFFE9F2F5),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
            border: Border.all(
              color: disabled
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.55),
              width: 0.8,
            ),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color: _ArcanoOnboardingSheetState._cyanAccent
                          .withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: const Color(0xFFEC4899).withValues(alpha: 0.20),
                      blurRadius: 22,
                      spreadRadius: -4,
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.saving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0A0512),
                    ),
                  )
                else
                  Text(
                    widget.enabled ? 'Continuar' : 'Completa los datos',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: disabled
                          ? Colors.white.withValues(alpha: 0.40)
                          : const Color(0xFF0A0512),
                      letterSpacing: 0.2,
                    ),
                  ),
                // Subtle shimmer sweep on the button
                if (!disabled)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _shimmer,
                          builder: (_, __) {
                            final v = _shimmer.value;
                            final double t;
                            final double opacity;
                            if (v < 0.7) {
                              t = -1.0;
                              opacity = 0;
                            } else if (v < 0.9) {
                              final p = (v - 0.7) / 0.20;
                              t = -1.0 + p * 2.0;
                              opacity = (1 - (p - 0.5).abs() * 2) * 0.35;
                            } else {
                              t = 1.0;
                              opacity = 0;
                            }
                            return FractionalTranslation(
                              translation: Offset(t, 0),
                              child: Opacity(
                                opacity: opacity,
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment(-0.5, -1),
                                      end: Alignment(0.5, 1),
                                      colors: [
                                        Colors.transparent,
                                        Colors.white,
                                        Colors.transparent,
                                      ],
                                      stops: [0.30, 0.50, 0.70],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZodiacPreview extends StatelessWidget {
  const _ZodiacPreview({required this.date});
  final DateTime date;

  ZodiacSign _signFor(int month, int day) {
    bool after(int sm, int sd) => month > sm || (month == sm && day >= sd);
    if (after(12, 22)) return ZodiacSign.capricorn;
    if (after(11, 22)) return ZodiacSign.sagittarius;
    if (after(10, 23)) return ZodiacSign.scorpio;
    if (after(9, 23)) return ZodiacSign.libra;
    if (after(8, 23)) return ZodiacSign.virgo;
    if (after(7, 23)) return ZodiacSign.leo;
    if (after(6, 21)) return ZodiacSign.cancer;
    if (after(5, 21)) return ZodiacSign.gemini;
    if (after(4, 20)) return ZodiacSign.taurus;
    if (after(3, 21)) return ZodiacSign.aries;
    if (after(2, 19)) return ZodiacSign.pisces;
    if (after(1, 20)) return ZodiacSign.aquarius;
    return ZodiacSign.capricorn;
  }

  @override
  Widget build(BuildContext context) {
    final sign = _signFor(date.month, date.day);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            sign.glyph,
            style: GoogleFonts.inter(
              fontSize: 24,
              color: _ArcanoOnboardingSheetState._cyanAccent,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TU SIGNO',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8,
                    letterSpacing: 2,
                    color: _ArcanoOnboardingSheetState._cyanAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sign.label,
                  style: GoogleFonts.fraunces(
                    fontSize: 18,
                    fontStyle: FontStyle.italic,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
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
