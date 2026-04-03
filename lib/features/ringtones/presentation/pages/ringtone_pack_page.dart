import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/services/ringtone_service.dart';
import '../../data/models/ringtone_pack.dart';

const _defaultPreviewAsset = 'assets/tone_preview_default.webp';

class RingtonePackPage extends StatefulWidget {
  final RingtonePack pack;
  const RingtonePackPage({super.key, required this.pack});

  @override
  State<RingtonePackPage> createState() => _RingtonePackPageState();
}

class _RingtonePackPageState extends State<RingtonePackPage> {
  final AudioPlayer _player = AudioPlayer();
  String? _playingId;
  String? _settingId;
  StreamSubscription? _playerSub;

  Color get _glowColor => parseHexColor(widget.pack.glowColor, fallback: Colors.deepPurple);

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
      default: return 'Tone';
    }
  }

  List<Color> _toneGradient(RingtoneTone tone) {
    final n = tone.name.toLowerCase();
    if (n.contains('mario') || n.contains('yoshi') || n.contains('coin')) return [const Color(0xFFE52521), const Color(0xFF8B0000)];
    if (n.contains('goku') || n.contains('saiyan') || n.contains('kamehameha') || n.contains('dbgt')) return [const Color(0xFFFF8C00), const Color(0xFF8B4513)];
    if (n.contains('zelda') || n.contains('navi') || n.contains('hyrule') || n.contains('fairy') || n.contains('rupee')) return [const Color(0xFF00FF7F), const Color(0xFF006400)];
    if (n.contains('homero') || n.contains('simpson')) return [const Color(0xFFFFD700), const Color(0xFF8B6914)];
    if (n.contains('bob') || n.contains('esponja') || n.contains('sponge') || n.contains('patricio')) return [const Color(0xFFFFEB3B), const Color(0xFF795548)];
    if (n.contains('death') || n.contains('note')) return [const Color(0xFF9C27B0), const Color(0xFF311B92)];
    if (n.contains('shrek')) return [const Color(0xFF4CAF50), const Color(0xFF1B5E20)];
    if (n.contains('nokia') || n.contains('retro') || n.contains('vintage') || n.contains('classic') || n.contains('rotary')) return [const Color(0xFFFFD700), const Color(0xFF5D4037)];
    if (n.contains('iphone') || n.contains('modern') || n.contains('digital') || n.contains('future')) return [const Color(0xFF00B4D8), const Color(0xFF0D47A1)];
    if (n.contains('soft') || n.contains('gentle') || n.contains('ambient') || n.contains('chill') || n.contains('morning')) return [const Color(0xFF7C4DFF), const Color(0xFF1A237E)];
    if (n.contains('minecraft')) return [const Color(0xFF4CAF50), const Color(0xFF33691E)];
    if (n.contains('fnaf')) return [const Color(0xFF7B1FA2), const Color(0xFF12005E)];
    if (n.contains('hadouken')) return [const Color(0xFF2196F3), const Color(0xFF0D47A1)];
    if (n.contains('fall guys')) return [const Color(0xFFE91E63), const Color(0xFF880E4F)];
    if (n.contains('hazbin') || n.contains('alastor')) return [const Color(0xFFD32F2F), const Color(0xFF4A0000)];
    if (n.contains('casa') || n.contains('papel')) return [const Color(0xFFD32F2F), const Color(0xFF4A0000)];
    if (n.contains('pou')) return [const Color(0xFF795548), const Color(0xFF3E2723)];
    if (n.contains('kill bill')) return [const Color(0xFFFFD700), const Color(0xFF8B6914)];
    if (n.contains('huawei')) return [const Color(0xFFE53935), const Color(0xFF880E4F)];
    if (n.contains('havana')) return [const Color(0xFFFF7043), const Color(0xFF4E342E)];
    return [_glowColor, _glowColor.withOpacity(0.3)];
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ── Preview playback ──────────────────────────────────────────────

  Future<void> _togglePreview(RingtoneTone tone) async {
    if (_playingId == tone.id) {
      await _player.stop();
      setState(() => _playingId = null);
      return;
    }

    setState(() => _playingId = tone.id);

    try {
      await _player.stop();
      await _player.setUrl(tone.fileUrl);
      _player.play();

      _playerSub?.cancel();
      _playerSub = _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _playingId = null);
        }
      });
    } catch (e) {
      debugPrint('[Pixora] Preview failed: $e');
      if (mounted) {
        setState(() => _playingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play preview'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Set as ringtone/notification/alarm ─────────────────────────────

  Future<void> _setAs(RingtoneTone tone, int type) async {
    if (_playingId != null) {
      await _player.stop();
      setState(() => _playingId = null);
    }

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
          'Tap "Open Settings" below, then enable the toggle.',
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
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
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
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final allTones = widget.pack.tones;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: CustomScrollView(
        slivers: [
          // Header with pack info + default image background
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: const Color(0xFF0A0A0F),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.pack.name, style: const TextStyle(fontSize: 16)),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Default preview image as background
                  Image.asset(_defaultPreviewAsset, fit: BoxFit.cover),
                  // Glow color tint
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _glowColor.withOpacity(0.4),
                          _glowColor.withOpacity(0.15),
                        ],
                      ),
                    ),
                  ),
                  // Dark gradient for readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                  // Content
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 40),
                        Icon(Icons.library_music, color: _glowColor, size: 44),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            widget.pack.description,
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: _glowColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _glowColor.withOpacity(0.4)),
                          ),
                          child: Text(
                            '${allTones.length} tones  •  Tap to preview',
                            style: TextStyle(color: _glowColor, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Grid of tone cards — NO staggered animation
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final tone = allTones[index];
                  final gradient = _toneGradient(tone);
                  return _ToneCard(
                    tone: tone,
                    glowColor: _glowColor,
                    gradient: gradient,
                    typeIcon: _typeIcon(tone.suggestedType),
                    typeLabel: _typeLabel(tone.suggestedType),
                    isPlaying: _playingId == tone.id,
                    isSetting: _settingId == tone.id,
                    onPlay: () => _togglePreview(tone),
                    onSetAs: () => _showSetAsDialog(tone),
                  );
                },
                childCount: allTones.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

// ── Tone Card with default image background ─────────────────────────
class _ToneCard extends StatelessWidget {
  final RingtoneTone tone;
  final Color glowColor;
  final List<Color> gradient;
  final IconData typeIcon;
  final String typeLabel;
  final bool isPlaying;
  final bool isSetting;
  final VoidCallback onPlay;
  final VoidCallback onSetAs;

  const _ToneCard({
    required this.tone,
    required this.glowColor,
    required this.gradient,
    required this.typeIcon,
    required this.typeLabel,
    required this.isPlaying,
    required this.isSetting,
    required this.onPlay,
    required this.onSetAs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPlay,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: isPlaying
              ? Border.all(color: glowColor, width: 2)
              : Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: isPlaying
              ? [BoxShadow(color: glowColor.withOpacity(0.4), blurRadius: 16, spreadRadius: 2)]
              : [BoxShadow(color: glowColor.withOpacity(0.08), blurRadius: 8)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background: default image + color tint
              Image.asset(_defaultPreviewAsset, fit: BoxFit.cover),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      gradient[0].withOpacity(0.5),
                      gradient[1].withOpacity(0.4),
                    ],
                  ),
                ),
              ),

              // Dark overlay for text
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.05),
                      Colors.black.withOpacity(0.8),
                    ],
                    stops: const [0.35, 1.0],
                  ),
                ),
              ),

              // Duration + type badge (top-left)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, size: 10, color: glowColor),
                      const SizedBox(width: 4),
                      Text(
                        tone.durationFormatted,
                        style: const TextStyle(fontSize: 9, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),

              // Play/Stop button (prominent)
              Center(
                child: _PlayStopButton(
                  isPlaying: isPlaying,
                  isSetting: isSetting,
                  glow: glowColor,
                ),
              ),

              // Playing wave indicator
              if (isPlaying)
                Positioned(
                  bottom: 50,
                  left: 0,
                  right: 0,
                  child: Center(child: _PlayingWave(color: glowColor)),
                ),

              // Bottom: name + set button
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tone.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        height: 30,
                        child: ElevatedButton(
                          onPressed: isSetting ? null : onSetAs,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: glowColor,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            isSetting ? 'Installing...' : 'Set as...',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Play/Stop Button ────────────────────────────────────────────────
class _PlayStopButton extends StatelessWidget {
  final bool isPlaying;
  final bool isSetting;
  final Color glow;

  const _PlayStopButton({
    required this.isPlaying,
    required this.isSetting,
    required this.glow,
  });

  @override
  Widget build(BuildContext context) {
    if (isSetting) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2.5, color: glow),
        ),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isPlaying ? glow : Colors.white.withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: isPlaying ? glow : Colors.white.withOpacity(0.4),
          width: 2,
        ),
        boxShadow: isPlaying
            ? [BoxShadow(color: glow.withOpacity(0.6), blurRadius: 16, spreadRadius: 2)]
            : [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
      ),
      child: Icon(
        isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
        color: Colors.white,
        size: 28,
      ),
    );
  }
}

// ── Animated wave bars ──────────────────────────────────────────────
class _PlayingWave extends StatefulWidget {
  final Color color;
  const _PlayingWave({required this.color});

  @override
  State<_PlayingWave> createState() => _PlayingWaveState();
}

class _PlayingWaveState extends State<_PlayingWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final phase = (_controller.value + i * 0.15) % 1.0;
          final h = 6.0 + 14.0 * (0.5 + 0.5 * math.sin(phase * math.pi * 2));
          return Container(
            width: 3,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(color: widget.color.withOpacity(0.4), blurRadius: 4)],
            ),
          );
        }),
      ),
    );
  }
}
