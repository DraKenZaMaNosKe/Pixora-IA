import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/theme_service.dart';
import '../../../core/services/wallpaper_service.dart';
import '../../../core/utils/locale_helper.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../../training/training_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _appVersion = '';

  // Wallpaper overlay toggles (read from / written to native SharedPreferences).
  final Map<String, bool> _overlays = {
    'clock': true,
    'battery': true,
    'ram': true,
    'storage': true,
    'equalizer': true,
  };

  // User-picked touch trail style (gold dust, aurora, lightning, etc.)
  String _touchTrail = 'aurora';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadOverlays();
    _loadTouchTrail();
  }

  Future<void> _loadTouchTrail() async {
    final v = await WallpaperService.instance.getTouchTrail();
    if (!mounted) return;
    setState(() => _touchTrail = v);
  }

  Future<void> _setTouchTrail(String style) async {
    setState(() => _touchTrail = style);
    final ok = await WallpaperService.instance.setTouchTrail(style);
    if (!ok && mounted) {
      // revert if native call failed
      final actual = await WallpaperService.instance.getTouchTrail();
      if (mounted) setState(() => _touchTrail = actual);
    }
  }

  Future<void> _loadOverlays() async {
    final values = await WallpaperService.instance.getOverlayVisibility();
    if (!mounted || values.isEmpty) return;
    setState(() {
      for (final key in _overlays.keys) {
        if (values.containsKey(key)) _overlays[key] = values[key]!;
      }
    });
  }

  Future<void> _setOverlay(String key, bool value) async {
    // Optimistic update — instant feedback in the UI while the native call runs.
    setState(() => _overlays[key] = value);
    final ok = await WallpaperService.instance.setOverlayVisibility(key, value);
    if (!ok && mounted) {
      // Revert on failure.
      setState(() => _overlays[key] = !value);
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = '${info.version}+${info.buildNumber}');
    }
  }

  // All AutoRotate UI + state moved to PixoraDailyPage 2026-05-05.
  // Settings is no longer the entry point — see PixoraDailyBanner widget
  // on the Wallpapers home (lib/features/wallpapers/presentation/widgets/).

  @override
  Widget build(BuildContext context) {
    // Control Deck HUD — picked 2026-05-16. Always-black bg + CRT
    // scanlines + cyan grid + terminal-style section headers and rows.
    return Container(
      color: const Color(0xFF050505),
      child: Stack(
        children: [
          // CRT scanlines + grid overlay
          const Positioned.fill(
            child: IgnorePointer(child: _HudCrtBg()),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
            children: [
              const _HudSectionHeader('SYSTEM', 'ACCOUNT'),
              _buildAccountSection(),
              const SizedBox(height: 14),
              const _HudDivider(),
              _HudSectionHeader('PRESENTATION',
                  LocaleHelper.pick(es: 'TOUCH_EFFECT', en: 'TOUCH_EFFECT')),
              _buildTouchTrailSection(),
              const _HudDivider(),
              _HudSectionHeader('WALLPAPER',
                  LocaleHelper.pick(es: 'OVERLAYS', en: 'OVERLAYS')),
              _buildOverlaysSection(),
              const _HudDivider(),
              const _HudSectionHeader('GENERAL', 'PREFERENCES'),
              const _ThemePickerSection(),
              _SettingsTile(
                icon: Icons.school_outlined,
                title: LocaleHelper.pick(
                  es: 'Reabrir tutorial guiado',
                  en: 'Restart guided tutorial',
                ),
                subtitle: LocaleHelper.pick(
                  es: 'Vuelve a ver las indicaciones de las secciones',
                  en: 'See the section walkthrough again',
                ),
                onTap: () async {
                  await TrainingService.instance.reset();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(LocaleHelper.pick(
                        es: 'Tutorial reactivado. Toca cualquier sección para verlo.',
                        en: 'Tutorial reactivated. Open any section to see it.',
                      )),
                    ),
                  );
                },
              ),
              const _HudDivider(),
              const _HudSectionHeader('INFO', 'ABOUT'),
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'Pixora IA',
                subtitle: _appVersion.isEmpty ? 'v —' : 'v$_appVersion',
              ),
              const _SettingsTile(
                icon: Icons.code,
                title: 'Made by',
                subtitle: 'Orbix Studio',
              ),
              const SizedBox(height: 8),
              const _HudDivider(),
              _HudSectionHeader('CRITICAL',
                  LocaleHelper.pick(es: 'DANGER_ZONE', en: 'DANGER_ZONE')),
              _SettingsTile(
                icon: Icons.delete_forever,
                title: LocaleHelper.pick(
                  es: 'Eliminar mi cuenta',
                  en: 'Delete my account',
                ),
                subtitle: LocaleHelper.pick(
                  es: 'Borra permanentemente tu cuenta y todos tus datos',
                  en: 'Permanently delete your account and all your data',
                ),
                onTap: _confirmDeleteAccount,
                iconColor: HudTokens.goldDeep,
              ),
              const SizedBox(height: 60),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final isSpanish = LocaleHelper.isSpanish;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTokens.nightSurface,
        title:
            Text(isSpanish ? '¿Eliminar tu cuenta?' : 'Delete your account?'),
        content: Text(isSpanish
            ? 'Esta acción es PERMANENTE. Perderás:\n'
                '• Todos tus diamantes\n'
                '• Tu historial de favoritos sincronizados\n'
                '• Tu historial de generaciones con IA\n'
                '• Tu suscripción (si tienes una activa, cancélala primero en Google Play)\n\n'
                '¿Seguro quieres continuar?'
            : 'This action is PERMANENT. You will lose:\n'
                '• All your diamonds\n'
                '• Your synced favorites history\n'
                '• Your AI generation history\n'
                '• Your subscription (if you have one active, cancel it in Google Play first)\n\n'
                'Are you sure you want to continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isSpanish ? 'Cancelar' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: HudTokens.goldDeep),
            child: Text(isSpanish ? 'Eliminar' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _performDeleteAccount();
  }

  Future<void> _performDeleteAccount() async {
    try {
      await Supabase.instance.client.rpc('delete_my_account');
      // RPC succeeded — user row is deleted in auth.users. Sign out cleanly
      // to clear the local session token.
      await AuthService.instance.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LocaleHelper.pick(
          es: 'Cuenta eliminada.',
          en: 'Account deleted.',
        )),
        backgroundColor: HudTokens.goldDeep,
      ));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final code = e.message;
      final msg = code.contains('active_subscription_cancel_first')
          ? LocaleHelper.pick(
              es: 'Tienes una suscripción activa. Cancélala primero en Google Play → Suscripciones, y vuelve después.',
              en: 'You have an active subscription. Cancel it first in Google Play → Subscriptions and come back.',
            )
          : LocaleHelper.pick(
              es: 'No se pudo eliminar la cuenta: ${e.message}',
              en: 'Could not delete account: ${e.message}',
            );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: HudTokens.goldDeep,
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LocaleHelper.pick(
          es: 'Error inesperado: $e',
          en: 'Unexpected error: $e',
        )),
        backgroundColor: HudTokens.goldDeep,
      ));
    }
  }

  Widget _buildTouchTrailSection() {
    // (id, icon, name ES/EN, tagline ES/EN)
    final List<(String, IconData, String, String)> trails = [
      (
        'aurora',
        Icons.gradient,
        LocaleHelper.pick(es: 'Aurora', en: 'Aurora'),
        LocaleHelper.pick(
            es: 'Cinta de colores cambiantes', en: 'Color-shifting ribbon')
      ),
      (
        'sparks',
        Icons.auto_awesome,
        LocaleHelper.pick(es: 'Chispas', en: 'Sparks'),
        LocaleHelper.pick(
            es: 'Estallido mágico que cae', en: 'Magic burst that falls')
      ),
      (
        'comet',
        Icons.bedtime_outlined,
        LocaleHelper.pick(es: 'Cometa', en: 'Comet'),
        LocaleHelper.pick(
            es: 'Cabeza brillante + cola azul', en: 'Bright head + blue tail')
      ),
      (
        'lightning',
        Icons.bolt,
        LocaleHelper.pick(es: 'Rayo', en: 'Lightning'),
        LocaleHelper.pick(
            es: 'Líneas eléctricas jagged', en: 'Jagged electric lines')
      ),
      (
        'petals',
        Icons.local_florist,
        LocaleHelper.pick(es: 'Pétalos', en: 'Petals'),
        LocaleHelper.pick(
            es: 'Pétalos sakura cayendo', en: 'Falling sakura petals')
      ),
      (
        'stardust',
        Icons.star_outline,
        LocaleHelper.pick(es: 'Polvo de estrellas', en: 'Stardust'),
        LocaleHelper.pick(es: 'Estrellas parpadeantes', en: 'Twinkling stars')
      ),
      (
        'pixora_gold',
        Icons.workspace_premium,
        LocaleHelper.pick(es: 'Oro Pixora', en: 'Pixora Gold'),
        LocaleHelper.pick(
            es: 'Espiral dorada con halo', en: 'Gold spiral with halo')
      ),
    ];

    final current = trails.firstWhere(
      (t) => t.$1 == _touchTrail,
      orElse: () => trails.first,
    );
    return _SettingsTile(
      icon: current.$2,
      iconColor: context.hud.accent,
      title: current.$3,
      subtitle: current.$4,
      onTap: () => _showTouchTrailPicker(trails),
    );
  }

  Future<void> _showTouchTrailPicker(
      List<(String, IconData, String, String)> trails) async {
    final h = context.hud;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: h.surface,
      // Allow the sheet to grow taller than the default 50% so the 7-row
      // list fits without overflow on smaller phones.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final ch = ctx.hud;
        // Cap the sheet at ~75% of viewport so the user still sees app
        // chrome above; ListView inside scrolls if rows exceed available
        // space (handles phones with smaller screen heights).
        final maxH = MediaQuery.of(ctx).size.height * 0.75;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ch.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    LocaleHelper.pick(
                      es: 'Efecto al tocar',
                      en: 'Touch effect',
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ch.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: trails.length,
                      itemBuilder: (_, i) {
                        final t = trails[i];
                        final id = t.$1;
                        final selected = _touchTrail == id;
                        return ListTile(
                          leading: Icon(t.$2,
                              color: selected ? ch.accent : ch.textDim),
                          title: Text(t.$3,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected ? ch.accent : ch.text,
                              )),
                          subtitle:
                              Text(t.$4, style: TextStyle(color: ch.textDim)),
                          trailing: selected
                              ? Icon(Icons.check_rounded, color: ch.accent)
                              : null,
                          onTap: () {
                            _setTouchTrail(id);
                            Navigator.of(ctx).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlaysSection() {
    // (key, icon, title, subtitle) — subtitle is bilingual.
    final items = [
      (
        'clock',
        Icons.access_time,
        LocaleHelper.pick(es: 'Reloj', en: 'Clock'),
        LocaleHelper.pick(
          es: 'Muestra el reloj decorativo sobre el fondo',
          en: 'Show the decorative clock on the wallpaper',
        ),
      ),
      (
        'battery',
        Icons.battery_charging_full,
        LocaleHelper.pick(es: 'Batería', en: 'Battery'),
        LocaleHelper.pick(
          es: 'Muestra el indicador circular de batería',
          en: 'Show the circular battery indicator',
        ),
      ),
      (
        'ram',
        Icons.memory,
        'RAM',
        LocaleHelper.pick(
          es: 'Muestra el anillo de uso de RAM',
          en: 'Show the RAM usage ring',
        ),
      ),
      (
        'storage',
        Icons.sd_storage,
        LocaleHelper.pick(es: 'Disco', en: 'Disk'),
        LocaleHelper.pick(
          es: 'Muestra el anillo de almacenamiento',
          en: 'Show the storage usage ring',
        ),
      ),
      (
        'equalizer',
        Icons.equalizer,
        LocaleHelper.pick(es: 'Ecualizador', en: 'Equalizer'),
        LocaleHelper.pick(
          es: 'Barras reactivas al audio que esté sonando',
          en: 'Bars that react to the audio playing',
        ),
      ),
    ];

    return Column(
      children: items.map((t) {
        final key = t.$1;
        final enabled = _overlays[key] ?? true;
        return _HudOverlayRow(
          icon: t.$2,
          title: t.$3,
          subtitle: t.$4,
          enabled: enabled,
          onChanged: (v) => _setOverlay(key, v),
        );
      }).toList(),
    );
  }

  Widget _buildAccountSection() {
    final auth = AuthService.instance;

    if (auth.isLoggedIn) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.hud.divider),
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: auth.avatarUrl != null
                      ? NetworkImage(auth.avatarUrl!)
                      : null,
                  backgroundColor: HudTokens.gold,
                  child: auth.avatarUrl == null
                      ? Text(
                          (auth.displayName ?? 'U')[0].toUpperCase(),
                          style:
                              TextStyle(fontSize: 20, color: context.hud.text),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              auth.displayName ?? 'User',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: context.hud.text,
                              ),
                            ),
                          ),
                          const _PlusPill(),
                        ],
                      ),
                      Text(
                        auth.email ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: HudTokens.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Synced',
                    style: TextStyle(
                        color: context.hud.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await auth.signOut();
                  ref.read(favoritesProvider.notifier).reset();
                  if (mounted) setState(() {});
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.hud.textDim,
                  side: BorderSide(color: context.hud.divider),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Sign out'),
              ),
            ),
          ],
        ),
      );
    }

    // Not logged in
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.hud.divider),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_sync,
              size: 40, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'Sign in to sync favorites',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.hud.text),
          ),
          const SizedBox(height: 4),
          Text(
            'Keep your favorites safe across devices',
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () async {
                final success = await auth.signInWithGoogle();
                if (success && mounted) {
                  setState(() {});
                  // Favorites auto-sync via FavoritesNotifier's auth listener.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Signed in! Favorites synced.'),
                      backgroundColor: HudTokens.gold,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.g_mobiledata, size: 24),
              label: const Text(
                'Continue with Google',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Optional — app works fully without an account',
            style: TextStyle(
                fontSize: 10, color: Colors.white.withValues(alpha: 0.3)),
          ),
        ],
      ),
    );
  }

  // Pickers for AutoRotate config moved to PixoraDailyPage.
}

// ── HUD palette (Control Deck) ─────────────────────────────────────
const _hudGreen = Color(0xFF5BFF8E);
const _hudCyan = Color(0xFF19F0FF);
const _hudRed = Color(0xFFFF4D4D);
const _hudInk = Color(0xFFD9F8E6);
const _hudInkDim = Color(0x99D9F8E6);
const _hudGrid = Color(0x1419F0FF);

/// CRT background — scanlines + cyan grid + faint green glow at top.
class _HudCrtBg extends StatelessWidget {
  const _HudCrtBg();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CrtPainter());
}

class _CrtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Faint green halo top
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 120),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x1A5BFF8E), Color(0x00000000)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, 120)),
    );
    // Cyan grid
    final grid = Paint()
      ..color = _hudGrid
      ..strokeWidth = 0.4;
    const step = 22.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // Horizontal scanlines (CRT)
    final scan = Paint()..color = const Color(0x0E000000);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scan);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Thin cyan-dim divider between HUD sections.
class _HudDivider extends StatelessWidget {
  const _HudDivider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _hudCyan.withValues(alpha: 0.0),
                _hudCyan.withValues(alpha: 0.35),
                _hudCyan.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      );
}

/// Terminal header — `> CATEGORY // TITLE_NAME` mono with LED dot.
class _HudSectionHeader extends StatelessWidget {
  const _HudSectionHeader(this.category, this.title);
  final String category;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 0, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hudGreen,
              boxShadow: [
                BoxShadow(
                  color: _hudGreen.withValues(alpha: 0.6),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '> $category ',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _hudGreen,
              letterSpacing: 1.4,
            ),
          ),
          Text(
            '// ${title.toUpperCase()}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _hudCyan,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 0.6,
              color: _hudCyan.withValues(alpha: 0.25),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final isDanger = iconColor == HudTokens.goldDeep;
    final accent = isDanger ? _hudRed : (iconColor ?? _hudGreen);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0x1419F0FF), width: 0.6),
          ),
        ),
        child: Row(
          children: [
            // Bracketed icon panel — like a hardware indicator
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDanger ? _hudRed : _hudInk,
                      letterSpacing: 1.2,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        color: _hudInkDim,
                        letterSpacing: 0.6,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Text(
                '►',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: accent.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Plus subscription pill ─────────────────────────────────────────
// Small gold chip next to the displayName when the user has an active
// Pixora Plus subscription. Listens to SubscriptionService reactively.
class _PlusPill extends StatelessWidget {
  const _PlusPill();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionService.instance,
      builder: (context, _) {
        final hasPlus = SubscriptionService.instance.status.hasAccess;
        if (!hasPlus) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [HudTokens.goldBright, HudTokens.gold],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text(
            'PLUS',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              letterSpacing: 1.2,
              height: 1,
            ),
          ),
        );
      },
    );
  }
}

/// "Tema visual" — three-option theme picker (Black & Gold / Cream Day / iOS White).
/// Phase 1 of iOS theme implementation.
class _ThemePickerSection extends StatelessWidget {
  const _ThemePickerSection();

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final activeId = ThemeService.instance.activeId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
              child: Text(
                LocaleHelper.pick(es: '── THEME_MODE', en: '── THEME_MODE'),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: _hudCyan.withValues(alpha: 0.65),
                ),
              ),
            ),
            for (final id in ThemeService.allIds)
              _ThemeOption(
                id: id,
                active: id == activeId,
                onTap: () => ThemeService.instance.setTheme(id),
              ),
          ],
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.id,
    required this.active,
    required this.onTap,
  });
  final String id;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
        decoration: BoxDecoration(
          border: const Border(
            bottom: BorderSide(color: Color(0x1419F0FF), width: 0.6),
          ),
          color:
              active ? _hudGreen.withValues(alpha: 0.06) : Colors.transparent,
        ),
        child: Row(
          children: [
            // Bracketed selector "[ • ]" / "[   ]"
            Text(
              active ? '[ ● ]' : '[   ]',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? _hudGreen : _hudInkDim,
                letterSpacing: 0.8,
                shadows: active
                    ? [
                        Shadow(
                          color: _hudGreen.withValues(alpha: 0.7),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ThemeService.labelFor(id).toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? _hudGreen : _hudInk,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ThemeService.taglineFor(id),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      letterSpacing: 0.6,
                      color: _hudInkDim,
                    ),
                  ),
                ],
              ),
            ),
            _SwatchPreview(themeId: id),
          ],
        ),
      ),
    );
  }
}

class _SwatchPreview extends StatelessWidget {
  const _SwatchPreview({required this.themeId});
  final String themeId;

  @override
  Widget build(BuildContext context) {
    HudTheme preview;
    switch (themeId) {
      case 'iosWhite':
        preview = HudTheme.iosWhite;
        break;
      default:
        preview = HudTheme.night;
    }
    return Container(
      width: 44,
      height: 28,
      decoration: BoxDecoration(
        color: preview.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: preview.divider, width: 1),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 6,
            top: 6,
            bottom: 6,
            child: Container(
              width: 10,
              decoration: BoxDecoration(
                color: preview.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── HUD Overlay row — hardware switch with LED indicator ──────────
class _HudOverlayRow extends StatelessWidget {
  const _HudOverlayRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!enabled),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0x1419F0FF), width: 0.6),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled
                    ? _hudGreen.withValues(alpha: 0.10)
                    : _hudInkDim.withValues(alpha: 0.05),
                border: Border.all(
                  color: enabled
                      ? _hudGreen.withValues(alpha: 0.5)
                      : _hudInkDim.withValues(alpha: 0.2),
                ),
              ),
              child:
                  Icon(icon, color: enabled ? _hudGreen : _hudInkDim, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: enabled ? _hudInk : _hudInkDim,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      color: _hudInkDim,
                      letterSpacing: 0.6,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _HudSwitch(enabled: enabled),
          ],
        ),
      ),
    );
  }
}

class _HudSwitch extends StatelessWidget {
  const _HudSwitch({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 44,
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: enabled
            ? _hudGreen.withValues(alpha: 0.18)
            : _hudInkDim.withValues(alpha: 0.06),
        border: Border.all(
          color: enabled ? _hudGreen : _hudInkDim.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: _hudGreen.withValues(alpha: 0.35),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment:
            enabled ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: enabled ? _hudGreen : _hudInkDim,
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: _hudGreen.withValues(alpha: 0.8),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
