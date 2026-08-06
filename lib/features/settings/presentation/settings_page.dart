import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/subscription_service.dart';
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

  // Hidden reviewer unlock: 7 taps on the version row (like Android's
  // dev-mode) opens a key dialog. Resets if taps are >2s apart.
  int _versionTaps = 0;
  DateTime? _lastVersionTap;

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
  // HUD preset — controls clock typography, EQ style, and monitor layout.
  String _hudPreset = 'classic';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadOverlays();
    _loadTouchTrail();
    _loadHudPreset();
  }

  Future<void> _loadHudPreset() async {
    final raw = await WallpaperService.instance.getHudPreset();
    // Migrate legacy keys ('sacred' + 6 deleted presets) to 'classic' so the
    // picker shows a valid selection. Native side does the same in fromKey.
    final validKeys = WallpaperService.hudPresets.map((p) => p.key).toSet();
    final v = validKeys.contains(raw) ? raw : 'classic';
    if (!mounted) return;
    setState(() => _hudPreset = v);
    // Persist the migrated value if it changed, so SharedPrefs stays clean.
    if (v != raw) {
      await WallpaperService.instance.setHudPreset(v);
    }
  }

  Future<void> _setHudPreset(String preset) async {
    setState(() => _hudPreset = preset);
    final ok = await WallpaperService.instance.setHudPreset(preset);
    if (!ok && mounted) {
      final actual = await WallpaperService.instance.getHudPreset();
      if (mounted) setState(() => _hudPreset = actual);
    }
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

  // ── Hidden reviewer access ────────────────────────────────────────────
  // 7 taps on the version row → key dialog. The correct key signs into the
  // pre-provisioned review account (active subscription) so Play reviewers can
  // use AI generation with no Google Sign-In and no billing. Documented in
  // Play Console "Sign-in details". Added 2026-08-06 for the takedown appeal.
  void _onVersionTap() {
    final now = DateTime.now();
    if (_lastVersionTap == null ||
        now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTaps = 0;
    }
    _lastVersionTap = now;
    _versionTaps++;
    if (_versionTaps >= 7) {
      _versionTaps = 0;
      _showReviewerKeyDialog();
    } else if (_versionTaps >= 4) {
      final remaining = 7 - _versionTaps;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 700),
          content: Text('$remaining more taps...'),
        ));
    }
  }

  Future<void> _showReviewerKeyDialog() async {
    final controller = TextEditingController();
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Reviewer access'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Access key'),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() => busy = true);
                      final ok = await AuthService.instance
                          .signInAsReviewer(controller.text.trim());
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Reviewer mode enabled — full access granted'
                            : 'Invalid key'),
                      ));
                      if (ok) setState(() {});
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
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
              const _GrimorioPageHeader(),
              const _HudSectionHeader('SYSTEM', 'ACCOUNT'),
              _buildAccountSection(),
              const SizedBox(height: 14),
              const _HudDivider(),
              _HudSectionHeader('PRESENTATION',
                  LocaleHelper.pick(es: 'HUD_STYLE', en: 'HUD_STYLE')),
              _buildHudPresetSection(),
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
                onTap: _onVersionTap,
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

  Widget _buildHudPresetSection() {
    const presets = WallpaperService.hudPresets;
    final current = presets.firstWhere(
      (p) => p.key == _hudPreset,
      orElse: () => presets.first,
    );
    return _SettingsTile(
      icon: Icons.dashboard_customize_outlined,
      iconColor: context.hud.accent,
      title: current.name,
      subtitle: current.sub,
      onTap: _showHudPresetPicker,
    );
  }

  Future<void> _showHudPresetPicker() async {
    final h = context.hud;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: h.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final ch = ctx.hud;
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
                    LocaleHelper.pick(es: 'ESTILO DE HUD', en: 'HUD STYLE'),
                    style: TextStyle(
                      color: ch.accent,
                      fontSize: 12,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    LocaleHelper.pick(
                        es: 'Cambia reloj + EQ + monitores',
                        en: 'Changes clock + EQ + monitors'),
                    style: TextStyle(
                      color: ch.textDim,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: WallpaperService.hudPresets.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: ch.divider.withValues(alpha: 0.3),
                      ),
                      itemBuilder: (lc, i) {
                        final p = WallpaperService.hudPresets[i];
                        final selected = _hudPreset == p.key;
                        return ListTile(
                          dense: false,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected ? ch.accent : ch.divider,
                                width: selected ? 1.5 : 1,
                              ),
                              color: selected
                                  ? ch.accent.withValues(alpha: 0.12)
                                  : Colors.transparent,
                            ),
                            child: Icon(
                              selected ? Icons.check : Icons.circle_outlined,
                              color: selected ? ch.accent : ch.textDim,
                              size: selected ? 18 : 12,
                            ),
                          ),
                          title: Text(
                            p.name,
                            style: TextStyle(
                              color: selected ? ch.accent : ch.text,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            p.sub,
                            style: TextStyle(color: ch.textDim, fontSize: 12),
                          ),
                          onTap: () {
                            _setHudPreset(p.key);
                            Navigator.of(lc).pop();
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

/// Grimorio page header — an illuminated chapter title: a Caveat kicker over
/// a large Cinzel Decorative "Ajustes", closed by a fleuron rule.
class _GrimorioPageHeader extends StatelessWidget {
  const _GrimorioPageHeader();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
      child: Column(
        children: [
          Text(
            LocaleHelper.pick(es: 'el tomo de', en: 'the tome of'),
            style: GoogleFonts.caveat(
              fontSize: 20,
              color: const Color(0xFFA8763E),
            ),
          ),
          Text(
            LocaleHelper.pick(es: 'Ajustes', en: 'Settings'),
            style: GoogleFonts.cinzelDecorative(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: HudTokens.goldBright,
              shadows: const [
                Shadow(color: Color(0xFF6E4A1E), offset: Offset(0, 1)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 130,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: HudTokens.gold.withValues(alpha: 0.3),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('❧',
                      style: TextStyle(color: Color(0xFF8B2E2E), fontSize: 12)),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    color: HudTokens.gold.withValues(alpha: 0.3),
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

class _HudCrtBg extends StatelessWidget {
  const _HudCrtBg();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CrtPainter());
}

class _CrtPainter extends CustomPainter {
  // Grimorio parchment glow — warm gold haze at the top + a faint seal-red
  // ember low-left, over the near-black ink. No grid, no scanlines.
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 240),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.topCenter,
          radius: 1.1,
          colors: [Color(0x24C9A650), Color(0x00000000)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, 240)),
    );
    final emberC = Offset(size.width * 0.16, size.height * 0.82);
    canvas.drawCircle(
      emberC,
      size.width * 0.55,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x168B2E2E), Color(0x00000000)],
        ).createShader(
            Rect.fromCircle(center: emberC, radius: size.width * 0.55)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Grimorio divider — a gold hairline broken by a fleuron (❧).
class _HudDivider extends StatelessWidget {
  const _HudDivider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    HudTokens.gold.withValues(alpha: 0.0),
                    HudTokens.gold.withValues(alpha: 0.35),
                  ]),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('❧',
                  style: TextStyle(color: HudTokens.gold, fontSize: 14)),
            ),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    HudTokens.gold.withValues(alpha: 0.35),
                    HudTokens.gold.withValues(alpha: 0.0),
                  ]),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Grimorio section header — a fleuron seal (❧) + a Cinzel Decorative title
/// in warm gold, trailed by a fading gold rule. Reads like a chapter mark in
/// an illuminated tome.
class _HudSectionHeader extends StatelessWidget {
  const _HudSectionHeader(this.category, this.title);
  final String category;
  final String title;

  static const Color _seal = Color(0xFF8B2E2E);

  String _pretty() {
    switch (title.toUpperCase()) {
      case 'ACCOUNT':
        return LocaleHelper.pick(es: 'Cuenta', en: 'Account');
      case 'HUD_STYLE':
        return LocaleHelper.pick(es: 'Estilo de HUD', en: 'HUD Style');
      case 'TOUCH_EFFECT':
        return LocaleHelper.pick(es: 'Efecto táctil', en: 'Touch Effect');
      case 'OVERLAYS':
        return LocaleHelper.pick(es: 'Overlays', en: 'Overlays');
      case 'PREFERENCES':
        return LocaleHelper.pick(es: 'Preferencias', en: 'Preferences');
      case 'ABOUT':
        return LocaleHelper.pick(es: 'Acerca de', en: 'About');
      case 'DANGER_ZONE':
        return LocaleHelper.pick(es: 'Zona crítica', en: 'Danger Zone');
      default:
        return title;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 0, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('❧', style: TextStyle(color: _seal, fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            _pretty(),
            style: GoogleFonts.cinzelDecorative(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: HudTokens.goldBright,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  HudTokens.gold.withValues(alpha: 0.4),
                  HudTokens.gold.withValues(alpha: 0.0),
                ]),
              ),
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
    const seal = Color(0xFF8B2E2E);
    final accent = isDanger ? seal : HudTokens.gold;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF23180D).withValues(alpha: 0.7),
                const Color(0xFF120C07).withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: accent.withValues(alpha: isDanger ? 0.55 : 0.3),
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Icon(icon,
                    color: isDanger
                        ? const Color(0xFFD98A8A)
                        : HudTokens.goldBright,
                    size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.cinzel(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isDanger
                            ? const Color(0xFFD98A8A)
                            : HudTokens.nightText,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: GoogleFonts.caveat(
                          fontSize: 15,
                          color: const Color(0xFFA8763E),
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Text('›',
                    style: TextStyle(
                        fontSize: 20, color: accent.withValues(alpha: 0.8))),
              ],
            ],
          ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => onChanged(!enabled),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF23180D).withValues(alpha: 0.7),
                const Color(0xFF120C07).withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: HudTokens.gold.withValues(alpha: enabled ? 0.35 : 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      HudTokens.gold.withValues(alpha: enabled ? 0.14 : 0.06),
                  border: Border.all(
                    color:
                        HudTokens.gold.withValues(alpha: enabled ? 0.5 : 0.22),
                  ),
                ),
                child: Icon(icon,
                    color:
                        enabled ? HudTokens.goldBright : HudTokens.nightTextDim,
                    size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.cinzel(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? HudTokens.nightText
                            : HudTokens.nightTextDim,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: GoogleFonts.caveat(
                          fontSize: 15,
                          color: const Color(0xFFA8763E),
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _HudSwitch(enabled: enabled),
            ],
          ),
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
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: enabled
            ? const LinearGradient(colors: [HudTokens.gold, Color(0xFFA8763E)])
            : null,
        color: enabled ? null : const Color(0xFF2A1D10),
        border: Border.all(
          color: enabled ? HudTokens.goldBright : const Color(0xFF5A4526),
          width: 1,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: HudTokens.gold.withValues(alpha: 0.35),
                  blurRadius: 7,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment:
            enabled ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFECDCB8),
            ),
          ),
        ],
      ),
    );
  }
}
