import 'package:flutter/material.dart';
import '../../../../core/services/ringtone_service.dart';
import '../../data/models/ringtone_pack.dart';

class RingtonePackPage extends StatefulWidget {
  final RingtonePack pack;
  const RingtonePackPage({super.key, required this.pack});

  @override
  State<RingtonePackPage> createState() => _RingtonePackPageState();
}

class _RingtonePackPageState extends State<RingtonePackPage> {
  String? _playingId;
  String? _settingId;

  Color get _glowColor {
    try {
      final hex = widget.pack.glowColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.deepPurple;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'ringtone': return Icons.phone_in_talk;
      case 'notification': return Icons.notifications;
      case 'alarm': return Icons.alarm;
      default: return Icons.music_note;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'ringtone': return 'Ringtone';
      case 'notification': return 'Notification';
      case 'alarm': return 'Alarm';
      default: return 'Sound';
    }
  }

  Future<void> _setAs(RingtoneTone tone, int type) async {
    // Check permission first
    final hasPermission = await RingtoneService.instance.checkPermission();
    if (!hasPermission) {
      if (mounted) await _showPermissionDialog(tone, type);
      return;
    }

    await _doSetAs(tone, type);
  }

  Future<void> _showPermissionDialog(RingtoneTone tone, int type) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.amber, size: 24),
            SizedBox(width: 10),
            Text('Permission needed', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: const Text(
          'To set ringtones, Pixora needs permission to modify system settings.\n\n'
          'Tap "Open Settings" below, then enable the toggle. Come back and try again.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await RingtoneService.instance.requestPermission();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _glowColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _doSetAs(RingtoneTone tone, int type) async {
    setState(() => _settingId = tone.id);

    final path = await RingtoneService.instance.downloadTone(tone);
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed'), backgroundColor: Colors.red),
        );
      }
      setState(() => _settingId = null);
      return;
    }

    final typeNames = ['Ringtone', 'Notification', 'Alarm'];
    final success = await RingtoneService.instance.setAsRingtone(path, tone.name, type);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '${tone.name} set as ${typeNames[type]}!'
              : 'Failed to set ringtone'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
    setState(() => _settingId = null);
  }

  void _showSetAsDialog(RingtoneTone tone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tone.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildSetOption(ctx, Icons.phone_in_talk, 'Ringtone', () {
              Navigator.pop(ctx);
              _setAs(tone, 0);
            }),
            _buildSetOption(ctx, Icons.notifications, 'Notification', () {
              Navigator.pop(ctx);
              _setAs(tone, 1);
            }),
            _buildSetOption(ctx, Icons.alarm, 'Alarm', () {
              Navigator.pop(ctx);
              _setAs(tone, 2);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSetOption(BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: _glowColor),
      title: Text(label),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifications = widget.pack.notificationTones;
    final ringtones = widget.pack.ringtoneTones;
    final alarms = widget.pack.alarmTones;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        title: Text(widget.pack.name),
        backgroundColor: const Color(0xFF0A0A0F),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Pack header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [_glowColor.withOpacity(0.15), Colors.transparent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.library_music, color: _glowColor, size: 48),
                const SizedBox(height: 12),
                Text(widget.pack.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(widget.pack.description,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('${widget.pack.tones.length} sounds',
                    style: TextStyle(color: _glowColor, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Notifications section
          if (notifications.isNotEmpty) ...[
            _SectionHeader(title: 'Notifications', icon: Icons.notifications, color: _glowColor),
            ...notifications.map((t) => _ToneCard(
              tone: t, glowColor: _glowColor, typeIcon: _typeIcon(t.suggestedType),
              isSetting: _settingId == t.id,
              onSetAs: () => _showSetAsDialog(t),
            )),
          ],

          // Ringtones section
          if (ringtones.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionHeader(title: 'Ringtones', icon: Icons.phone_in_talk, color: _glowColor),
            ...ringtones.map((t) => _ToneCard(
              tone: t, glowColor: _glowColor, typeIcon: _typeIcon(t.suggestedType),
              isSetting: _settingId == t.id,
              onSetAs: () => _showSetAsDialog(t),
            )),
          ],

          // Alarms section
          if (alarms.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionHeader(title: 'Alarms', icon: Icons.alarm, color: _glowColor),
            ...alarms.map((t) => _ToneCard(
              tone: t, glowColor: _glowColor, typeIcon: _typeIcon(t.suggestedType),
              isSetting: _settingId == t.id,
              onSetAs: () => _showSetAsDialog(t),
            )),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionHeader({required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _ToneCard extends StatelessWidget {
  final RingtoneTone tone;
  final Color glowColor;
  final IconData typeIcon;
  final bool isSetting;
  final VoidCallback onSetAs;

  const _ToneCard({
    required this.tone,
    required this.glowColor,
    required this.typeIcon,
    required this.isSetting,
    required this.onSetAs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: glowColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(typeIcon, color: glowColor, size: 20),
        ),
        title: Text(tone.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(tone.durationFormatted,
            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
        trailing: isSetting
            ? SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: glowColor),
              )
            : ElevatedButton(
                onPressed: onSetAs,
                style: ElevatedButton.styleFrom(
                  backgroundColor: glowColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(0, 34),
                ),
                child: const Text('Set as...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }
}
