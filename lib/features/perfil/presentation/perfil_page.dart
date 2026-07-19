import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/credit_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../../../core/widgets/report_content_modal.dart';
import '../../../core/services/report_service.dart';
import '../../subscription/presentation/subscription_pitch_page.dart';
import 'payment_history_page.dart';
import 'ai_history_page.dart';

/// User profile screen — accessed via tap on the avatar in the AppBar.
/// Concept #01 "Apple Profile" picked by user 2026-05-05: iOS Settings
/// vibe, grouped tiles, clean and familiar.
///
/// Sections:
///   1. Header — avatar + name + email + Pro pill (or sign-in CTA)
///   2. Tu plan — subscription state + credits
///   3. Tus colecciones — favorites / aplicados / IA / eventos seguidos
///   4. Pagos — history + restore
///   5. Cuenta — sign out / delete account
class PerfilPage extends ConsumerStatefulWidget {
  const PerfilPage({super.key});

  @override
  ConsumerState<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends ConsumerState<PerfilPage> {
  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) => _buildBody(context, h),
    );
  }

  Widget _buildBody(BuildContext context, HudTheme h) {
    final user = AuthService.instance.currentUser;
    final isPro = SubscriptionService.instance.hasAccess;
    final credits = CreditService.instance.balance;
    final favCount = ref.watch(favoritesProvider).length;

    return Scaffold(
      backgroundColor: h.bg,
      appBar: AppBar(
        backgroundColor: h.bg,
        elevation: 0,
        title: Text(
          'Perfil',
          style: TextStyle(
            color: h.text,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: h.text),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        key: ValueKey('perfil-body:${user?.id ?? "guest"}'),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Header(
            user: user,
            isPro: isPro,
            onTapSignIn: _signIn,
          ),
          _SectionHeader(text: 'Tu plan', h: h),
          if (isPro)
            _Tile(
              icon: Icons.star_rounded,
              title: 'Pixora Plus',
              subtitle: '${_formatRenewal()}\nGestiona o cancela en Play Store',
              onTap: _openSubscriptionDetails,
              trailing: Icon(Icons.open_in_new, size: 16, color: h.textDim),
              h: h,
            )
          else
            _Tile(
              icon: Icons.workspace_premium_outlined,
              title: 'Hacerse Plus',
              subtitle: 'Sin anuncios + códices y eventos exclusivos',
              trailing: Text(
                // Real localized Play price, not a hardcoded currency.
                SubscriptionService.instance.monthlyProduct?.price ??
                    '\$199 MXN',
                style: const TextStyle(
                  color: Color(0xFFD9B14A),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              onTap: _openPitch,
              h: h,
            ),
          _Tile(
            icon: Icons.diamond_outlined,
            title: 'Créditos',
            subtitle: '$credits diamantes disponibles',
            trailing: Text(
              '+$credits',
              style: TextStyle(
                color: h.accent,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            onTap: () =>
                _showSnack('Gana créditos viendo anuncios. ¡Cada uno suma!'),
            h: h,
          ),
          _SectionGap(h: h),
          _SectionHeader(text: 'Tus colecciones', h: h),
          _Tile(
            icon: Icons.favorite_outline,
            title: 'Favoritos',
            trailing: _Count(value: favCount, h: h),
            onTap: () =>
                _showSnack('Abre la sección Favoritos desde el menú inferior.'),
            h: h,
          ),
          _Tile(
            icon: Icons.flash_on_outlined,
            title: 'Wallpapers aplicados',
            subtitle: 'Historial de instalaciones',
            trailing: const _CountPlaceholder(),
            onTap: () =>
                _showSnack('Próximamente: lista cronológica de instalaciones.'),
            h: h,
          ),
          _Tile(
            icon: Icons.auto_awesome_outlined,
            title: 'Imágenes IA generadas',
            subtitle: 'Tu galería personal de creaciones',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AIHistoryPage()),
            ),
            h: h,
          ),
          _Tile(
            icon: Icons.notifications_none,
            title: 'Eventos seguidos',
            subtitle: 'Te avisamos cuando arranque cada temporada',
            onTap: () =>
                _showSnack('Próximamente: gestionar avisos por evento.'),
            h: h,
          ),
          _SectionGap(h: h),
          // 2026-06-20 — Entry global de moderación. Permite reportar
          // contenido sin necesidad de estar viendo el wallpaper
          // específico. Requerido por la política de contenido generado
          // por IA de Google Play.
          _SectionHeader(text: 'Seguridad', h: h),
          _Tile(
            icon: Icons.flag_outlined,
            title: 'Reportar contenido',
            subtitle: 'Avísanos si algo viola las políticas',
            onTap: _openReportPicker,
            h: h,
          ),
          _SectionGap(h: h),
          _SectionHeader(text: 'Pagos', h: h),
          _Tile(
            icon: Icons.credit_card_outlined,
            title: 'Historial de pagos',
            subtitle: 'Todas tus transacciones',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PaymentHistoryPage()),
            ),
            h: h,
          ),
          _Tile(
            icon: Icons.refresh,
            title: 'Restaurar compras',
            subtitle: 'Recupera tu suscripción en otro dispositivo',
            onTap: _restorePurchases,
            h: h,
          ),
          _SectionGap(h: h),
          _SectionHeader(text: 'Cuenta', h: h),
          if (user != null)
            _DangerTile(
              text: 'Cerrar sesión',
              onTap: _signOut,
              h: h,
            ),
          _DangerTile(
            text: 'Eliminar mi cuenta',
            danger: true,
            onTap: _confirmDeleteAccount,
            h: h,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── Handlers ──────────────────────────────────────────────────────

  Future<void> _signIn() async {
    final ok = await AuthService.instance.signInWithGoogle();
    if (!mounted) return;
    if (ok) _showSnack('¡Sesión iniciada!');
    // No setState — AuthService is a ChangeNotifier and the surrounding
    // ListenableBuilder rebuilds the body automatically.
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          'Tus favoritos y compras siguen vinculados a tu cuenta. Puedes volver a iniciar sesión cuando quieras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await AuthService.instance.signOut();
      // No setState — ListenableBuilder rebuilds when AuthService notifies.
    }
  }

  void _openPitch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubscriptionPitchPage(
          onFinish: (ctx) => Navigator.pop(ctx),
        ),
      ),
    );
  }

  /// Opens the Play Store deep link directly to Pixora's subscription
  /// management page. Google policy: cancellation MUST happen in Play Store,
  /// the app cannot do it for the user. Best we can do is take them there
  /// in one tap.
  Future<void> _openSubscriptionDetails() async {
    const url =
        'https://play.google.com/store/account/subscriptions?package=com.orbix.pixora&sku=pixora_monthly';
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showSnack(
          'No pudimos abrir Play Store. Ve a Play Store › Pagos y suscripciones › Pixora.');
    }
  }

  /// 2026-06-20 — Entry point global de reporte. Muestra un picker
  /// liviano (dialog) para que el user escoja qué tipo de contenido
  /// reportar (wallpaper / live / AI / etc.) y después abre el modal
  /// con el campo ID prellenado (texto manual del user).
  Future<void> _openReportPicker() async {
    final h = context.hud;
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: h.surface,
          title: Text(
            'Reportar contenido',
            style: TextStyle(color: h.text, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Si estás viendo un wallpaper, pulsa el icono ⚐ en la esquina superior de la pantalla del visor. Si quieres reportar algo más general, pega aquí el ID del contenido o describe:',
                style: TextStyle(color: h.textDim, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                style: TextStyle(color: h.text),
                decoration: InputDecoration(
                  hintText: 'ID o descripción',
                  hintStyle: TextStyle(color: h.textDim),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    if (id == null || id.isEmpty || !mounted) return;
    await showReportContentModal(
      context,
      wallpaperId: id,
      kind: ReportableKind.other,
      wallpaperMeta: {'reported_via': 'profile_picker', 'user_text': id},
    );
  }

  Future<void> _restorePurchases() async {
    _showSnack('Restaurando compras...');
    final restored = await SubscriptionService.instance.restorePurchases();
    if (!mounted) return;
    _showSnack(restored > 0
        ? '✓ Restauradas $restored compras.'
        : 'No encontramos compras para restaurar.');
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
          'Esta acción es permanente. Se eliminarán tus favoritos, créditos, '
          'historial y datos de IA. Tu suscripción debe cancelarse aparte '
          'desde Google Play. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Color(0xFFCC4545)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    // Real deletion — the same RPC Settings uses. (This screen used to promise
    // deletion and then only show a "coming soon" snackbar.)
    try {
      await Supabase.instance.client.rpc('delete_my_account');
      await AuthService.instance.signOut();
      if (!mounted) return;
      _showSnack('Cuenta eliminada.');
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showSnack('No se pudo eliminar la cuenta. Intenta de nuevo.');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  String _formatRenewal() {
    final next = SubscriptionService.instance.expiresAt;
    if (next == null) return 'Activa · sin caducidad registrada';
    final now = DateTime.now();
    final days = next.difference(now).inDays;
    if (days < 0) return 'En periodo de gracia';
    final fmt =
        '${next.day.toString().padLeft(2, '0')}/${next.month.toString().padLeft(2, '0')}/${next.year}';
    final price =
        SubscriptionService.instance.monthlyProduct?.price ?? '\$199 MXN';
    return 'Próx. renovación $fmt · $price';
  }
}

// ── Header ──────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.isPro,
    required this.onTapSignIn,
  });
  final dynamic user; // AuthService user type
  final bool isPro;
  final VoidCallback onTapSignIn;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final email = user?.email as String?;
    final displayName = (user?.userMetadata?['full_name'] as String?) ??
        (user?.userMetadata?['name'] as String?) ??
        email?.split('@').first ??
        'Invitado';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          // Avatar — gold gradient circle with initial
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFD9B14A), Color(0xFFF5D676)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontStyle: FontStyle.italic,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: h.text,
                    height: 1.05,
                  ),
                ),
                if (email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: h.textDim,
                    ),
                  ),
                ],
                if (user == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton(
                      onPressed: onTapSignIn,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Iniciar sesión con Google',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: h.accent,
                        ),
                      ),
                    ),
                  )
                else if (isPro)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD9B14A), Color(0xFFF5D676)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '⭐ PIXORA PLUS',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Plan gratuito',
                      style: TextStyle(
                        fontSize: 11,
                        color: h.textDim,
                      ),
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

// ── Section header (small uppercase label) ─────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text, required this.h});
  final String text;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 10,
          letterSpacing: 1.8,
          color: h.textDim,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionGap extends StatelessWidget {
  const _SectionGap({required this.h});
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Container(height: 12, color: h.bg);
  }
}

// ── Tile (icon + title + optional subtitle/trailing + arrow) ───────

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
    required this.h,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: h.accent.withValues(alpha: 0.12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: h.accent, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: h.text,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: h.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right, color: h.textDim, size: 20),
          ],
        ),
      ),
    );
  }
}

class _DangerTile extends StatelessWidget {
  const _DangerTile({
    required this.text,
    this.danger = false,
    required this.onTap,
    required this.h,
  });
  final String text;
  final bool danger;
  final VoidCallback onTap;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: danger ? const Color(0xFFCC4545) : h.text,
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.h});
  final int value;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$value',
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: h.accent,
      ),
    );
  }
}

class _CountPlaceholder extends StatelessWidget {
  const _CountPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Text(
      '—',
      style: TextStyle(
        fontSize: 14,
        color: context.hud.textDim,
      ),
    );
  }
}
