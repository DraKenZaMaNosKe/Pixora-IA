import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/analytics_service.dart';
import '../../../core/services/legal_service.dart';

/// First-launch gate: user must accept Terms & Privacy before reaching
/// any other screen.
///
/// Design: Apple Premium (concept #01 from `docs/design/pixora_terms_concepts.html`)
///   - Pure white bg
///   - Gold lock icon header
///   - Scrollable card with key sections
///   - "Acepto y continuar" — Apple system blue, full-width
///   - "No acepto" — text button. Tapping opens a confirmation that exits
///     the app, since Pixora cannot run without accepted terms.
///
/// The page calls `onFinish(context)` once the user accepts, mirroring the
/// onboarding/pitch funnel pattern. The active page's context is passed so
/// the splash's stale context isn't reused.
class TermsAcceptancePage extends StatefulWidget {
  const TermsAcceptancePage({super.key, required this.onFinish});

  final void Function(BuildContext context) onFinish;

  @override
  State<TermsAcceptancePage> createState() => _TermsAcceptancePageState();
}

class _TermsAcceptancePageState extends State<TermsAcceptancePage> {
  static const _appleBlue = Color(0xFF0A84FF);
  static const _appleBlueDark = Color(0xFF0072E0);
  static const _gold = Color(0xFFD9B14A);
  static const _goldBright = Color(0xFFF5D676);
  static const _ink = Color(0xFF1D1D1F);
  static const _inkSoft = Color(0xFF494949);
  static const _gray = Color(0xFF86868B);
  static const _divider = Color(0xFFE5E5E7);

  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.track('terms_gate_shown', {
      'version': LegalService.kCurrentTermsVersion,
    });
  }

  Future<void> _onAccept() async {
    if (_accepting) return;
    setState(() => _accepting = true);
    await LegalService.instance.markAccepted();
    if (!mounted) return;
    widget.onFinish(context);
  }

  Future<void> _onDecline() async {
    AnalyticsService.instance.track('terms_decline_tap');
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: _ink,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 13,
          color: _inkSoft,
          height: 1.4,
        ),
        title: const Text('¿Salir de Pixora?'),
        content: const Text(
            'Para usar Pixora necesitas aceptar los Términos y el Aviso de Privacidad. Si no aceptas, la app se cerrará.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Volver',
              style: TextStyle(color: _appleBlue, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Salir',
              style: TextStyle(color: Color(0xFFCC4545)),
            ),
          ),
        ],
      ),
    );
    if (exit == true) {
      AnalyticsService.instance.track('terms_declined_exit');
      // Best-effort flush so the analytics row reaches Supabase before exit.
      await AnalyticsService.instance.flushNow();
      // Close the app on Android; on iOS this is a no-op (Apple disallows
      // programmatic exit). The user can swipe-close manually.
      await SystemNavigator.pop();
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Force dark status bar icons over the white bg so iOS-style overlay reads.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildScroll()),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 22),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _divider, width: 0.5)),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_gold, _goldBright],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child:
                const Icon(Icons.lock_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 18),
          const Text(
            'Términos y Privacidad',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: _ink,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Por favor revisa antes de continuar',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              color: _gray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScroll() {
    return Scrollbar(
      thickness: 3,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(
              '1. Aceptación',
              'Al instalar Pixora aceptas quedar vinculado por estos Términos y por nuestro Aviso de Privacidad. Si no estás de acuerdo, debes desinstalar la aplicación.',
            ),
            _section(
              '2. Identidad del Proveedor',
              'Pixora IA es desarrollada por Eduardo Javier Contreras Román, persona física con actividad empresarial, operando bajo el nombre comercial Orbix Studio (RFC: CORE830606279). Domicilio fiscal disponible mediante solicitud al correo pixoramain@gmail.com.',
            ),
            _section(
              '3. Edad mínima',
              'Para usar Pixora debes ser mayor de 13 años. Entre 13 y 18 años requieres consentimiento de un tutor.',
            ),
            _section(
              '5. Suscripción Pixora Pro',
              'La suscripción Pixora Pro tiene un costo de \$9.99 USD (\$199.00 MXN) mensuales, \$24.99 USD (\$499.00 MXN) trimestrales o \$89.99 USD (\$1,799.00 MXN) anuales. Se cobra mediante Google Play Billing. La cancelación se realiza desde Google Play Store, no desde la app. Conservas acceso hasta el fin del periodo pagado.',
            ),
            _section(
              '8. Generación con IA',
              'Las imágenes generadas con IA son para uso personal no comercial. No solicites contenido que viole derechos de terceros, sea ilícito, o represente menores en contextos inapropiados.',
            ),
            _section(
              '11. Propiedad Intelectual',
              'Todo el contenido (wallpapers, sonidos AURA, ilustraciones, código, marca) es propiedad de Orbix Studio. Se otorga licencia personal, no exclusiva y no transferible para uso dentro de la App.',
            ),
            _section(
              '14. Datos Personales',
              'Recolectamos: correo (si inicias sesión), ID de dispositivo, modelo, versión de OS, datos de uso, prompts de IA, suscripción. NUNCA recibimos tu tarjeta — Google Play maneja los pagos. Tus derechos ARCO se ejercen al correo pixoramain@gmail.com.',
            ),
            _section(
              '22. Ley aplicable',
              'Estos Términos se rigen por las leyes de los Estados Unidos Mexicanos. Las partes se someten a la jurisdicción de los tribunales competentes en Guadalajara, Jalisco, México.',
            ),
            const SizedBox(height: 8),
            _linkRow(
              icon: Icons.description_outlined,
              label: 'Ver Términos completos',
              url: LegalService.kTermsUrl,
            ),
            _linkRow(
              icon: Icons.shield_outlined,
              label: 'Ver Aviso de Privacidad completo',
              url: LegalService.kPrivacyUrl,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _ink,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              color: _inkSoft,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkRow({
    required IconData icon,
    required String label,
    required String url,
  }) {
    return InkWell(
      onTap: () => _openUrl(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _appleBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _appleBlue,
                ),
              ),
            ),
            const Icon(Icons.open_in_new, size: 16, color: _appleBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _divider, width: 0.5)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _accepting ? null : _onAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: _appleBlue,
                disabledBackgroundColor: _appleBlue.withValues(alpha: 0.5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ).copyWith(
                overlayColor: WidgetStateProperty.all(_appleBlueDark),
              ),
              child: _accepting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Acepto y continuar',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _accepting ? null : _onDecline,
            style: TextButton.styleFrom(
              foregroundColor: _appleBlue,
              padding: const EdgeInsets.symmetric(vertical: 10),
              minimumSize: const Size(double.infinity, 36),
            ),
            child: const Text(
              'No acepto',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
