import 'package:flutter/material.dart';
import '../../../core/services/download_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
          subtitle: 'Version 1.0.0',
        ),
        const _SettingsTile(
          icon: Icons.code,
          title: 'Made by',
          subtitle: 'Orbix Studio',
        ),
      ],
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
