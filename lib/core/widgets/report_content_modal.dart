import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/report_service.dart';
import '../utils/locale_helper.dart';

/// Modal serio (no "cosmos") para reportar contenido ofensivo.
/// Diseño intencionalmente neutro — superficie gris/blanco con acento
/// rojo apagado sólo en el icono/botón final. NO usa el theme dorado
/// de Pixora porque la moderación no debería sentirse "premium" o
/// "celebratoria"; debe sentirse seria, accesible y rápida.
///
/// Llamar desde cualquier visor con:
///   showReportContentModal(
///     context,
///     wallpaperId: w.id,
///     kind: ReportableKind.aiGenerated,
///     wallpaperMeta: {...},
///   );
Future<void> showReportContentModal(
  BuildContext context, {
  required String wallpaperId,
  required ReportableKind kind,
  Map<String, dynamic>? wallpaperMeta,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ReportContentSheet(
      wallpaperId: wallpaperId,
      kind: kind,
      wallpaperMeta: wallpaperMeta,
    ),
  );
}

class _ReportContentSheet extends StatefulWidget {
  const _ReportContentSheet({
    required this.wallpaperId,
    required this.kind,
    required this.wallpaperMeta,
  });
  final String wallpaperId;
  final ReportableKind kind;
  final Map<String, dynamic>? wallpaperMeta;

  @override
  State<_ReportContentSheet> createState() => _ReportContentSheetState();
}

class _ReportContentSheetState extends State<_ReportContentSheet> {
  ReportReason? _selected;
  final _descCtrl = TextEditingController();
  bool _submitting = false;
  bool _success = false;

  static const _surface = Color(0xFF1C1C1E);
  static const _surfaceLight = Color(0xFF2C2C2E);
  static const _text = Color(0xFFE8E8EC);
  static const _textDim = Color(0xFF98989D);
  static const _accentRed = Color(0xFFC2410C);

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null || _submitting) return;
    setState(() => _submitting = true);
    final id = await ReportService.instance.submitReport(
      wallpaperId: widget.wallpaperId,
      kind: widget.kind,
      reason: _selected!,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      wallpaperMeta: widget.wallpaperMeta,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _success = id != null;
    });
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocaleHelper.pick(
            es: 'No se pudo enviar el reporte. Intenta de nuevo.',
            en: 'Could not send report. Try again.',
          )),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        child: SafeArea(
          top: false,
          child: _success ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: _textDim.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.flag_outlined, color: _accentRed, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  LocaleHelper.pick(
                    es: 'Reportar contenido',
                    en: 'Report content',
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: _text,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            LocaleHelper.pick(
              es: 'Cuéntanos por qué consideras que este contenido viola las políticas. Revisamos cada reporte en 24-48 h.',
              en: 'Tell us why this content violates the rules. We review every report within 24-48h.',
            ),
            style: GoogleFonts.inter(
              fontSize: 13,
              color: _textDim,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            LocaleHelper.pick(es: 'MOTIVO', en: 'REASON'),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _textDim,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ReportReason.values
                .map((r) => _reasonChip(r))
                .toList(growable: false),
          ),
          const SizedBox(height: 18),
          Text(
            LocaleHelper.pick(
                es: 'DETALLES (OPCIONAL)', en: 'DETAILS (OPTIONAL)'),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _textDim,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            maxLength: 500,
            style: GoogleFonts.inter(fontSize: 14, color: _text),
            cursorColor: _accentRed,
            decoration: InputDecoration(
              hintText: LocaleHelper.pick(
                es: 'Agrega contexto si quieres…',
                en: 'Add context if you want…',
              ),
              hintStyle: GoogleFonts.inter(
                fontSize: 14,
                color: _textDim.withValues(alpha: 0.65),
              ),
              filled: true,
              fillColor: _surfaceLight,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _accentRed, width: 1.5),
              ),
              counterStyle: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: _textDim,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: _textDim,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    LocaleHelper.pick(es: 'Cancelar', en: 'Cancel'),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: _selected == null || _submitting ? null : _submit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accentRed,
                    side: BorderSide(
                      color: _selected == null
                          ? _textDim.withValues(alpha: 0.3)
                          : _accentRed,
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _accentRed,
                          ),
                        )
                      : Text(
                          LocaleHelper.pick(
                            es: 'Enviar reporte',
                            en: 'Send report',
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reasonChip(ReportReason r) {
    final selected = _selected == r;
    return ChoiceChip(
      label: Text(
        LocaleHelper.pick(es: r.esLabel, en: r.enLabel),
        style: GoogleFonts.inter(
          fontSize: 13,
          color: selected ? Colors.white : _text,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _selected = r),
      backgroundColor: _surfaceLight,
      selectedColor: _accentRed,
      side: BorderSide(
        color: selected ? _accentRed : _textDim.withValues(alpha: 0.25),
        width: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildSuccess() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _accentRed.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: _accentRed, size: 32),
          ),
          const SizedBox(height: 18),
          Text(
            LocaleHelper.pick(es: 'Reporte enviado', en: 'Report sent'),
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            LocaleHelper.pick(
              es: 'Gracias por ayudarnos a mantener Pixora seguro. Revisaremos el contenido en 24-48 h.',
              en: 'Thanks for helping keep Pixora safe. We will review the content within 24-48h.',
            ),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: _textDim,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _text,
                side: BorderSide(
                  color: _textDim.withValues(alpha: 0.3),
                  width: 1,
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                LocaleHelper.pick(es: 'Cerrar', en: 'Close'),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
