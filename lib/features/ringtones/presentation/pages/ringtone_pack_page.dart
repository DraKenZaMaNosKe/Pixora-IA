import 'dart:async';
import '../../../../core/design/hud_tokens.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../../../core/services/preview_player_service.dart';
import '../../../../core/services/ringtone_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../../core/widgets/ticket_stub_card.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
import '../../data/models/ringtone_pack.dart';

class RingtonePackPage extends StatefulWidget {
  final RingtonePack pack;
  const RingtonePackPage({super.key, required this.pack});

  @override
  State<RingtonePackPage> createState() => _RingtonePackPageState();
}

class _RingtonePackPageState extends State<RingtonePackPage> {
  final _previewPlayer = PreviewPlayerService.instance;
  String? _playingId;
  String? _settingId;
  String _toneLoadingStatus = '';
  LoadingPhase _toneLoadingPhase = LoadingPhase.downloading;
  StreamSubscription? _playerSub;

  Color get _glowColor => HudTokens
      .gold; // Was: parseHexColor(pack.glowColor, fallback: deepPurple)

  IconData _typeIcon(String type) {
    switch (type) {
      case 'ringtone':
        return Icons.phone_in_talk;
      case 'notification':
        return Icons.notifications;
      case 'alarm':
        return Icons.alarm;
      default:
        return Icons.music_note;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'ringtone':
        return 'Ringtone';
      case 'notification':
        return 'Notification';
      case 'alarm':
        return 'Alarm';
      default:
        return 'Tone';
    }
  }

  List<Color> _toneGradient(RingtoneTone tone, Color glow) {
    // Black & Gold: ignore per-character brand colors — every tone renders on
    // a unified gold gradient. Was previously 22 hardcoded palettes.
    return [HudTokens.goldDeep, Theme.of(context).extension<HudTheme>()?.bg ?? HudTokens.nightBg];
  }

  @override
  void initState() {
    super.initState();
    WallpaperStatsService.instance.trackView('tone_pack_${widget.pack.id}');
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _previewPlayer.stop();
    super.dispose();
  }

  // ── Preview playback ──────────────────────────────────────────────

  Future<void> _togglePreview(RingtoneTone tone) async {
    if (_playingId == tone.id) {
      await _previewPlayer.stop();
      setState(() => _playingId = null);
      return;
    }

    setState(() => _playingId = tone.id);

    try {
      await _previewPlayer.play(
        url: tone.fileUrl,
        id: tone.id,
        title: tone.name,
        album: 'Pixora Tones',
        artist: widget.pack.name,
      );

      _playerSub?.cancel();
      _playerSub = _previewPlayer.playerStateStream?.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _playingId = null);
        }
      });
    } catch (e) {
      debugPrint('[Pixora] Preview failed: $e');
      if (mounted) {
        setState(() => _playingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not play preview'),
              backgroundColor: HudTokens.goldDeep),
        );
      }
    }
  }

  // ── Set as ringtone/notification/alarm ─────────────────────────────

  Future<void> _setAs(RingtoneTone tone, int type) async {
    if (_playingId != null) {
      await _previewPlayer.stop();
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
        title: Row(
          children: [
            Icon(Icons.settings, color: context.hud.accent2, size: 24),
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
            child: Text('Cancel',
                style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await RingtoneService.instance.requestPermission();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _glowColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _doSetAs(RingtoneTone tone, int type) async {
    final typeNames = ['Ringtone', 'Notification', 'Alarm'];
    setState(() {
      _settingId = tone.id;
      _toneLoadingPhase = LoadingPhase.downloading;
      _toneLoadingStatus = 'Downloading ${tone.name}...';
    });
    WallpaperStatsService.instance.trackDownload('tone_${tone.id}');

    final path = await RingtoneService.instance.downloadTone(tone);
    if (path == null) {
      if (mounted) {
        setState(() {
          _toneLoadingPhase = LoadingPhase.error;
          _toneLoadingStatus = 'Download failed';
        });
        await Future.delayed(const Duration(milliseconds: 1200));
        setState(() => _settingId = null);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _toneLoadingPhase = LoadingPhase.installing;
        _toneLoadingStatus = 'Setting as ${typeNames[type]}...';
      });
    }

    final success =
        await RingtoneService.instance.setAsRingtone(path, tone.name, type);

    if (mounted) {
      setState(() {
        _toneLoadingPhase = success ? LoadingPhase.done : LoadingPhase.error;
        _toneLoadingStatus = success
            ? '${tone.name} set as ${typeNames[type]}!'
            : 'Failed to set ringtone';
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      setState(() => _settingId = null);
    }
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
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(tone.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

  Widget _buildSetOption(
      BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
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
      body: Stack(children: [
        CustomScrollView(
          slivers: [
            // Header with pack info + default image background
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              backgroundColor: const Color(0xFF0A0A0F),
              flexibleSpace: FlexibleSpaceBar(
                title: Text(widget.pack.name,
                    style: const TextStyle(fontSize: 16)),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Default preview image as background
                    // [old placeholder asset removed — Black & Gold radial bg in overlaying Container below]
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
                          Icon(Icons.library_music,
                              color: _glowColor, size: 44),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              widget.pack.description,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: _glowColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: _glowColor.withOpacity(0.4)),
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
                    final gradient = _toneGradient(tone, _glowColor);
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
        LoadingOverlay(
          visible: _settingId != null,
          status: _toneLoadingStatus,
          accentColor: _glowColor,
          phase: _toneLoadingPhase,
        ),
      ]),
    );
  }
}

// ── Tone Card with default image background ─────────────────────────
class _ToneCard extends StatelessWidget {
  final RingtoneTone tone;
  final Color glowColor; // kept for API compat — ignored; uses gold
  final List<Color> gradient; // kept for API compat — ignored
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
    return TicketStubCard(
      admitLabel: isPlaying ? 'NOW' : 'TONE',
      title: tone.name,
      category: '${typeLabel.toUpperCase()} · ${tone.durationFormatted}',
      isHighlighted: isPlaying,
      onTap: onPlay,
      overlayTopRight: WallpaperStatsBar(
        wallpaperId: 'tone_${tone.id}',
        glowColor: context.hud.accent,
      ),
      child: Column(
        children: [
          // Image / icon panel — gold radial on dark.
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.hud.surfaceHi,
                gradient: RadialGradient(
                  colors: [
                    context.hud.accent.withOpacity(isPlaying ? 0.35 : 0.14),
                    context.hud.surface,
                  ],
                  radius: 0.85,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(typeIcon, color: context.hud.accent, size: 24),
                        const SizedBox(height: 10),
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.hud.bg.withOpacity(0.55),
                            border: Border.all(color: context.hud.accent, width: 1),
                          ),
                          child: _PlayStopButton(
                            isPlaying: isPlaying,
                            isSetting: isSetting,
                            glow: context.hud.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isPlaying)
                    Positioned(
                      bottom: 6,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _PlayingWave(color: context.hud.accent),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // "Set as..." CTA bar — flat gold under the image panel, above
          // the perforation. Tapping this specifically triggers set-as
          // without starting preview playback.
          GestureDetector(
            onTap: isSetting ? null : onSetAs,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              margin: const EdgeInsets.only(top: 4),
              color: isSetting
                  ? context.hud.surfaceHi
                  : context.hud.accent.withOpacity(0.9),
              alignment: Alignment.center,
              child: Text(
                isSetting ? 'INSTALLING…' : 'SET AS ↗',
                style: HudTokens.mono(
                  size: 10,
                  weight: FontWeight.w700,
                  color: isSetting ? context.hud.accent : Colors.black,
                  letterSpacing: 0.25,
                ),
              ),
            ),
          ),
        ],
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
            ? [
                BoxShadow(
                    color: glow.withOpacity(0.6),
                    blurRadius: 16,
                    spreadRadius: 2)
              ]
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
              boxShadow: [
                BoxShadow(color: widget.color.withOpacity(0.4), blurRadius: 4)
              ],
            ),
          );
        }),
      ),
    );
  }
}
