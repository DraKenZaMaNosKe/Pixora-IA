import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/auto_rotate_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/theme_service.dart';
import '../../../core/services/wallpaper_service.dart';
import '../../../core/utils/locale_helper.dart';
import '../../favorites/providers/favorites_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _autoRotateEnabled = false;
  bool _loading = true;
  int _intervalMinutes = 5;
  int _target = 2; // 0=Home, 1=Lock, 2=Both
  String? _category; // null = all, 'PANORAMIC' = only panoramic
  String _cacheSizeMB = '0.0';
  int _cachedCount = 0;
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
    _loadStatus();
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

  Future<void> _loadStatus() async {
    final status = await AutoRotateService.instance.getStatus();
    if (mounted) {
      setState(() {
        _autoRotateEnabled = status['enabled'] == true;
        _intervalMinutes = status['intervalMinutes'] as int? ?? 5;
        _target = status['target'] as int? ?? 2;
        _category = status['category'] as String?;
        _cacheSizeMB = status['cacheSizeMB'] as String? ?? '0.0';
        _cachedCount = status['cachedCount'] as int? ?? 0;
        _loading = false;
      });
    }
  }

  Future<void> _toggleAutoRotate(bool enabled) async {
    setState(() => _loading = true);

    if (enabled) {
      final success = await AutoRotateService.instance.start(
        intervalMinutes: _intervalMinutes,
        target: _target,
        category: _category,
      );
      if (mounted) {
        setState(() {
          _autoRotateEnabled = success;
          _loading = false;
        });
        if (success) {
          final label = _category == 'PANORAMIC' ? 'panoramic' : 'all';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Auto-rotate ON — $label, every $_intervalMinutes min'),
              backgroundColor: HudTokens.goldDeep,
            ),
          );
        }
      }
    } else {
      await AutoRotateService.instance.stop();
      if (mounted) {
        setState(() {
          _autoRotateEnabled = false;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Auto-rotate OFF'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    }
  }

  String _targetLabel(int target) {
    switch (target) {
      case 0:
        return 'Home screen';
      case 1:
        return 'Lock screen';
      default:
        return 'Both screens';
    }
  }

  String _intervalLabel(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    return '$hours hr';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Account section
        const _SectionHeader('Account'),
        _buildAccountSection(),
        const SizedBox(height: 20),
        const _SectionHeader('Auto-Rotate'),
        _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      Icons.autorenew,
                      color:
                          _autoRotateEnabled ? HudTokens.gold : Colors.white54,
                    ),
                    title: const Text('Auto-rotate wallpaper'),
                    subtitle: Text(
                      _autoRotateEnabled
                          ? 'Changes every ${_intervalLabel(_intervalMinutes)}'
                          : 'Automatically change your wallpaper',
                      style: const TextStyle(color: Colors.white38),
                    ),
                    value: _autoRotateEnabled,
                    onChanged: _toggleAutoRotate,
                    activeColor: HudTokens.gold,
                  ),
                  if (_autoRotateEnabled) ...[
                    const SizedBox(height: 4),
                    // Category filter
                    _SettingsTile(
                      icon: _category == 'PANORAMIC'
                          ? Icons.panorama_wide_angle
                          : Icons.photo_library,
                      title: 'Wallpapers',
                      subtitle: _category == 'PANORAMIC'
                          ? 'Panoramic only'
                          : 'All categories',
                      onTap: () => _showCategoryPicker(),
                    ),
                    // Interval selector
                    _SettingsTile(
                      icon: Icons.timer,
                      title: 'Interval',
                      subtitle: _intervalLabel(_intervalMinutes),
                      onTap: () => _showIntervalPicker(),
                    ),
                    // Target selector
                    _SettingsTile(
                      icon: Icons.wallpaper,
                      title: 'Apply to',
                      subtitle: _targetLabel(_target),
                      onTap: () => _showTargetPicker(),
                    ),
                    // Cache info
                    _SettingsTile(
                      icon: Icons.sd_storage,
                      title: 'Cache',
                      subtitle: '$_cachedCount wallpapers ($_cacheSizeMB MB)',
                      onTap: () async {
                        await AutoRotateService.instance.clearCache();
                        await _loadStatus();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Auto-rotate cache cleared')),
                          );
                        }
                      },
                    ),
                  ],
                ],
              ),
        const Divider(color: Colors.white12),
        _SectionHeader(LocaleHelper.pick(
          es: 'Efecto al tocar',
          en: 'Touch effect',
        )),
        _buildTouchTrailSection(),
        const Divider(color: Colors.white12),
        _SectionHeader(LocaleHelper.pick(
          es: 'Overlays del wallpaper',
          en: 'Wallpaper overlays',
        )),
        _buildOverlaysSection(),
        const Divider(color: Colors.white12),
        const _SectionHeader('General'),
        const _ThemePickerSection(),
        const Divider(color: Colors.white12),
        const _SectionHeader('About'),
        _SettingsTile(
          icon: Icons.info_outline,
          title: 'Pixora IA',
          subtitle: _appVersion.isEmpty ? 'Version —' : 'Version $_appVersion',
        ),
        const _SettingsTile(
          icon: Icons.code,
          title: 'Made by',
          subtitle: 'Orbix Studio',
        ),
        const SizedBox(height: 12),
        const Divider(color: Colors.white12),
        _SectionHeader(LocaleHelper.pick(
          es: 'Zona de peligro',
          en: 'Danger zone',
        )),
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
        const SizedBox(height: 40),
      ],
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

    return Column(
      children: trails.map((t) {
        final id = t.$1;
        final selected = _touchTrail == id;
        return RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          secondary:
              Icon(t.$2, color: selected ? HudTokens.gold : Colors.white54),
          title: Text(t.$3,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? HudTokens.gold : Colors.white,
              )),
          subtitle: Text(t.$4, style: const TextStyle(color: Colors.white38)),
          value: id,
          groupValue: _touchTrail,
          activeColor: HudTokens.gold,
          onChanged: (v) {
            if (v != null) _setTouchTrail(v);
          },
        );
      }).toList(),
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
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary:
              Icon(t.$2, color: enabled ? HudTokens.gold : Colors.white54),
          title: Text(t.$3),
          subtitle: Text(t.$4, style: const TextStyle(color: Colors.white38)),
          value: enabled,
          activeColor: HudTokens.gold,
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
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
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
                          style: const TextStyle(
                              fontSize: 20, color: Colors.white),
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
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
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
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: HudTokens.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Synced',
                    style: TextStyle(
                        color: HudTokens.gold,
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
                  foregroundColor: Colors.white54,
                  side: const BorderSide(color: Colors.white12),
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_sync,
              size: 40, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 12),
          const Text(
            'Sign in to sync favorites',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Keep your favorites safe across devices',
            style:
                TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
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
            style:
                TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.3)),
          ),
        ],
      ),
    );
  }

  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: HudTokens.nightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Rotate wallpapers from',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...[
              (null, 'All categories', Icons.photo_library),
              ('PANORAMIC', 'Panoramic only', Icons.panorama_wide_angle),
            ].map((entry) => ListTile(
                  leading: Icon(entry.$3, color: Colors.white54),
                  title: Text(entry.$2),
                  trailing: entry.$1 == _category
                      ? const Icon(Icons.check, color: HudTokens.gold)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _category = entry.$1);
                    if (_autoRotateEnabled) {
                      await AutoRotateService.instance.start(
                        intervalMinutes: _intervalMinutes,
                        target: _target,
                        category: entry.$1,
                      );
                      _loadStatus();
                    }
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showIntervalPicker() {
    final intervals = [1, 3, 5, 10, 15, 30, 60, 120];
    showModalBottomSheet(
      context: context,
      backgroundColor: HudTokens.nightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Change interval',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...intervals.map((mins) => ListTile(
                  title: Text(_intervalLabel(mins)),
                  trailing: mins == _intervalMinutes
                      ? const Icon(Icons.check, color: HudTokens.gold)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _intervalMinutes = mins);
                    if (_autoRotateEnabled) {
                      await AutoRotateService.instance.start(
                        intervalMinutes: mins,
                        target: _target,
                        category: _category,
                      );
                      _loadStatus();
                    }
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showTargetPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: HudTokens.nightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Apply wallpaper to',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...[
              (0, 'Home screen', Icons.home),
              (1, 'Lock screen', Icons.lock),
              (2, 'Both screens', Icons.phone_android),
            ].map((entry) => ListTile(
                  leading: Icon(entry.$3, color: Colors.white54),
                  title: Text(entry.$2),
                  trailing: entry.$1 == _target
                      ? const Icon(Icons.check, color: HudTokens.gold)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _target = entry.$1);
                    if (_autoRotateEnabled) {
                      await AutoRotateService.instance.start(
                        intervalMinutes: _intervalMinutes,
                        target: entry.$1,
                        category: _category,
                      );
                      _loadStatus();
                    }
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
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
    final color = iconColor ?? Colors.white54;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: iconColor == HudTokens.goldDeep
            ? const TextStyle(color: HudTokens.goldDeep)
            : null,
      ),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white38)),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                LocaleHelper.pick(es: 'TEMA VISUAL', en: 'VISUAL THEME'),
                style: TextStyle(
                  fontFamily: h.monoFontFamily,
                  fontSize: 11,
                  letterSpacing: 2.4,
                  color: h.textDim,
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
    final h = context.hud;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: h.divider, width: 0.5),
          ),
          color:
              active ? h.surfaceHi.withValues(alpha: 0.5) : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? h.accent : h.divider,
                  width: 1.5,
                ),
                color: active ? h.accent : Colors.transparent,
              ),
              child: active ? Icon(Icons.check, size: 14, color: h.bg) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ThemeService.labelFor(id),
                    style: TextStyle(
                      fontFamily: h.bodyFontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: h.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ThemeService.taglineFor(id),
                    style: TextStyle(
                      fontFamily: h.monoFontFamily,
                      fontSize: 10,
                      letterSpacing: 0.6,
                      color: h.textDim,
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
      case 'day':
        preview = HudTheme.day;
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
