import 'package:flutter/material.dart';
import '../../../core/services/auto_rotate_service.dart';
import '../../../core/services/download_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoRotateEnabled = false;
  bool _loading = true;
  int _intervalMinutes = 5;
  int _target = 2; // 0=Home, 1=Lock, 2=Both
  String? _category; // null = all, 'PANORAMIC' = only panoramic
  String _cacheSizeMB = '0.0';
  int _cachedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStatus();
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
              content: Text('Auto-rotate ON — $label, every $_intervalMinutes min'),
              backgroundColor: Colors.green.shade800,
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
      case 0: return 'Home screen';
      case 1: return 'Lock screen';
      default: return 'Both screens';
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
                      color: _autoRotateEnabled ? Colors.greenAccent : Colors.white54,
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
                    activeColor: Colors.greenAccent,
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
                            const SnackBar(content: Text('Auto-rotate cache cleared')),
                          );
                        }
                      },
                    ),
                  ],
                ],
              ),
        const Divider(color: Colors.white12),
        const _SectionHeader('General'),
        _SettingsTile(
          icon: Icons.delete_outline,
          title: 'Clear cache',
          subtitle: 'Remove downloaded wallpapers',
          onTap: () async {
            await DownloadService.instance.clearCache();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            }
          },
        ),
        const Divider(color: Colors.white12),
        const _SectionHeader('About'),
        const _SettingsTile(
          icon: Icons.info_outline,
          title: 'Pixora IA',
          subtitle: 'Version 1.1.0',
        ),
        const _SettingsTile(
          icon: Icons.code,
          title: 'Made by',
          subtitle: 'Orbix Studio',
        ),
      ],
    );
  }

  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Rotate wallpapers from', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...[
              (null, 'All categories', Icons.photo_library),
              ('PANORAMIC', 'Panoramic only', Icons.panorama_wide_angle),
            ].map((entry) => ListTile(
              leading: Icon(entry.$3, color: Colors.white54),
              title: Text(entry.$2),
              trailing: entry.$1 == _category
                  ? const Icon(Icons.check, color: Colors.greenAccent)
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
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Change interval', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...intervals.map((mins) => ListTile(
              title: Text(_intervalLabel(mins)),
              trailing: mins == _intervalMinutes
                  ? const Icon(Icons.check, color: Colors.greenAccent)
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
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Apply wallpaper to', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...[
              (0, 'Home screen', Icons.home),
              (1, 'Lock screen', Icons.lock),
              (2, 'Both screens', Icons.phone_android),
            ].map((entry) => ListTile(
              leading: Icon(entry.$3, color: Colors.white54),
              title: Text(entry.$2),
              trailing: entry.$1 == _target
                  ? const Icon(Icons.check, color: Colors.greenAccent)
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white54),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white38)),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }
}
