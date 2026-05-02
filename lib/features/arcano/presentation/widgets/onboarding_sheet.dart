import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/hud_tokens.dart';
import '../../data/user_profile_service.dart';

/// Modal bottom sheet shown the first time the user opens ARCANO. Asks for
/// name + birth date, persists locally only (Hive). Returns true if the user
/// completed it; false if they dismissed without saving (caller can keep
/// nagging them or fall back to a generic, non-personalised view).
class ArcanoOnboardingSheet extends StatefulWidget {
  const ArcanoOnboardingSheet({super.key});

  static Future<bool> show(BuildContext context) async {
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

  Future<void> _pickDate(HudTheme hud) async {
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
        // Inherit Pixora's dark / iOS theme into Material's date picker so
        // the gold accent and dark surface match the rest of ARCANO.
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: hud.accent,
              brightness: hud.isDark ? Brightness.dark : Brightness.light,
            ).copyWith(
              primary: hud.accent,
              onPrimary: hud.isDark ? Colors.black : Colors.white,
              surface: hud.surface,
              onSurface: hud.text,
            ),
            dialogTheme: DialogThemeData(backgroundColor: hud.surface),
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
    final hud = context.hud;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          gradient: hud.isDark
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0A0512), Color(0xFF050308)],
                )
              : null,
          color: hud.isDark ? null : hud.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: hud.accent.withValues(alpha: 0.3)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // grabber
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: hud.textDim.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '⌬ BIENVENIDO AL UMBRAL',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  letterSpacing: 3,
                  color: hud.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Hola, cuéntanos de ti.',
                style: GoogleFonts.fraunces(
                  fontSize: 26,
                  fontStyle: FontStyle.italic,
                  color: hud.text,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Necesitamos solo dos datos para personalizar lecturas, '
                'frecuencia y signo. Nada se sube a internet — vive solo en '
                'este dispositivo.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: hud.textDim,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),

              // Name field
              _fieldLabel(hud, 'NOMBRE'),
              const SizedBox(height: 6),
              _NameField(
                  controller: _nameCtrl,
                  hud: hud,
                  onChanged: () => setState(() {})),
              const SizedBox(height: 16),

              // Birth date picker
              _fieldLabel(hud, 'FECHA DE NACIMIENTO'),
              const SizedBox(height: 6),
              _DateField(
                hud: hud,
                date: _birthDate,
                onTap: () => _pickDate(hud),
              ),
              const SizedBox(height: 22),

              // CTA
              _CtaButton(
                hud: hud,
                enabled: _canSave,
                saving: _saving,
                onTap: _save,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '🔒 SOLO EN ESTE DISPOSITIVO · NO SUBE A INTERNET',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8,
                    letterSpacing: 1.8,
                    color: hud.textDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(HudTheme hud, String label) => Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          letterSpacing: 2.4,
          color: hud.accent,
          fontWeight: FontWeight.w700,
        ),
      );
}

class _NameField extends StatelessWidget {
  final TextEditingController controller;
  final HudTheme hud;
  final VoidCallback onChanged;
  const _NameField(
      {required this.controller, required this.hud, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: hud.isDark ? hud.text.withValues(alpha: 0.06) : hud.surface,
        border: Border.all(color: hud.accent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        textCapitalization: TextCapitalization.words,
        autofocus: true,
        style: GoogleFonts.fraunces(
          fontSize: 18,
          color: hud.text,
        ),
        cursorColor: hud.accent,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Eduardo',
          hintStyle: GoogleFonts.fraunces(
            fontSize: 18,
            color: hud.textDim.withValues(alpha: 0.55),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final HudTheme hud;
  final DateTime? date;
  final VoidCallback onTap;
  const _DateField(
      {required this.hud, required this.date, required this.onTap});

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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: hud.isDark ? hud.text.withValues(alpha: 0.06) : hud.surface,
            border: Border.all(color: hud.accent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 18, color: hud.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasDate
                      ? '${date!.day} · ${_months[date!.month]} · ${date!.year}'
                      : 'Toca para escoger',
                  style: GoogleFonts.fraunces(
                    fontSize: 18,
                    color: hasDate ? hud.text : hud.textDim,
                    fontStyle: hasDate ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: hud.textDim, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  final HudTheme hud;
  final bool enabled;
  final bool saving;
  final VoidCallback onTap;
  const _CtaButton({
    required this.hud,
    required this.enabled,
    required this.saving,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = enabled
        ? [hud.accent, Color.lerp(hud.accent, Colors.black, 0.18)!]
        : [
            hud.textDim.withValues(alpha: 0.3),
            hud.textDim.withValues(alpha: 0.5),
          ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: hud.accent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (saving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              else
                const Icon(Icons.auto_awesome_rounded,
                    color: Colors.black, size: 18),
              const SizedBox(width: 10),
              Text(
                saving ? 'GUARDANDO...' : 'CRUZAR EL UMBRAL',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
