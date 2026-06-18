import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/services/ad_service.dart';
import '../../../../core/services/preview_player_service.dart';
import '../../../../core/services/ringtone_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../data/models/ringtone_pack.dart';

/// RINGTONE PACK page — Cassette A/B Sides (concept #01, picked by
/// Eduardo 2026-05-16). The whole pack is presented as a physical
/// cassette tape: hero shows the cassette label with twin reels
/// spinning when something plays; the tones are split into SIDE A
/// and SIDE B (half each); each tone is a horizontal "track strip"
/// with mono track number, title, duration and a play/pause button.
/// Active track gets a pink-neon glow halo + pause icon.
class RingtonePackPage extends StatefulWidget {
  final RingtonePack pack;
  const RingtonePackPage({super.key, required this.pack});

  @override
  State<RingtonePackPage> createState() => _RingtonePackPageState();
}

class _RingtonePackPageState extends State<RingtonePackPage> {
  // ── Synthwave cassette palette (always-dark, theme-agnostic) ──────
  static const _bg = Color(0xFF0A0220);
  static const _bgMid = Color(0xFF1A0D3D);
  static const _cassetteLabelA = Color(0xFFFF2BD6); // pink neon
  static const _cassetteLabelB = Color(0xFFC016FF); // magenta
  static const _neonPink = Color(0xFFFF2BD6);
  static const _neonCyan = Color(0xFF19F0FF);
  static const _violet = Color(0xFF7C3AFF);
  static const _cream = Color(0xFFF6F1E0);
  static const _cassetteShellA = Color(0xFF2C0A4D);
  static const _cassetteShellB = Color(0xFF18062E);

  final _previewPlayer = PreviewPlayerService.instance;
  String? _playingId;
  String? _settingId;
  String _toneLoadingStatus = '';
  LoadingPhase _toneLoadingPhase = LoadingPhase.downloading;
  StreamSubscription? _playerSub;

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
            backgroundColor: _neonPink,
          ),
        );
      }
    }
  }

  // ── Set as ringtone/notification/alarm ────────────────────────────
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
    AdService.instance.showInterstitialAd(
      placement: 'ringtone_save',
      onAdDismissed: () {
        if (mounted) _doSetAs(tone, type);
      },
    );
  }

  Future<void> _showPermissionDialog(RingtoneTone tone, int type) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.settings, color: _neonCyan, size: 24),
            const SizedBox(width: 10),
            Text(
              LocaleHelper.pick(
                  es: 'Permiso necesario', en: 'Permission needed'),
              style: const TextStyle(fontSize: 17, color: _cream),
            ),
          ],
        ),
        content: Text(
          LocaleHelper.pick(
            es: 'Para configurar tonos, Pixora necesita permiso para '
                'modificar la configuración del sistema.\n\n'
                'Toca "Abrir configuración" abajo y activa el switch.',
            en: 'To set ringtones, Pixora needs permission to modify '
                'system settings.\n\nTap "Open Settings" below, then '
                'enable the toggle.',
          ),
          style: const TextStyle(color: _cream, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              LocaleHelper.pick(es: 'Cancelar', en: 'Cancel'),
              style: const TextStyle(color: _neonCyan),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await RingtoneService.instance.requestPermission();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _neonPink,
              foregroundColor: Colors.white,
            ),
            child: Text(
              LocaleHelper.pick(es: 'Abrir configuración', en: 'Open Settings'),
            ),
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
    final path = await RingtoneService.instance.downloadTone(tone);
    if (path == null) {
      if (mounted) {
        setState(() {
          _toneLoadingPhase = LoadingPhase.error;
          _toneLoadingStatus = 'Download failed';
        });
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        setState(() => _settingId = null);
      }
      return;
    }
    // Track download AFTER it succeeded (audit Sprint 1 fix).
    WallpaperStatsService.instance.trackDownload('tone_${tone.id}');

    if (mounted) {
      setState(() {
        _toneLoadingPhase = LoadingPhase.installing;
        _toneLoadingStatus = 'Setting as ${typeNames[type]}...';
      });
    }
    final success =
        await RingtoneService.instance.setAsRingtone(path, tone.name, type);
    if (success) {
      WallpaperStatsService.instance.trackInstall('tone_${tone.id}');
    }
    if (mounted) {
      setState(() {
        _toneLoadingPhase = success ? LoadingPhase.done : LoadingPhase.error;
        _toneLoadingStatus = success
            ? '${tone.name} set as ${typeNames[type]}!'
            : 'Failed to set ringtone';
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() => _settingId = null);
    }
  }

  void _showSetAsDialog(RingtoneTone tone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bgMid,
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
                color: _neonCyan.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(tone.name,
                style: GoogleFonts.bangers(
                  fontSize: 22,
                  color: _neonPink,
                  letterSpacing: 1.5,
                )),
            const SizedBox(height: 16),
            _setOption(ctx, Icons.phone_in_talk, 'RING', () {
              Navigator.pop(ctx);
              _setAs(tone, 0);
            }),
            _setOption(ctx, Icons.notifications, 'MSG', () {
              Navigator.pop(ctx);
              _setAs(tone, 1);
            }),
            _setOption(ctx, Icons.alarm, 'ALARMA', () {
              Navigator.pop(ctx);
              _setAs(tone, 2);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _setOption(
      BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: _neonCyan),
      title: Text(label,
          style: GoogleFonts.inter(
            color: _cream,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          )),
      trailing: const Icon(Icons.chevron_right, color: _neonPink),
      onTap: onTap,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final allTones = widget.pack.tones;
    final mid = (allTones.length / 2).ceil();
    final sideA = allTones.take(mid).toList();
    final sideB = allTones.skip(mid).toList();
    final totalSeconds =
        allTones.fold<int>(0, (sum, t) => sum + t.durationSeconds);
    final totalMin = (totalSeconds / 60).ceil();

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Cosmic gradient bg
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_bgMid, _bg],
                ),
              ),
            ),
          ),
          // Pixel grid overlay
          const Positioned.fill(child: IgnorePointer(child: _PixelGridBg())),
          // Content
          CustomScrollView(
            slivers: [
              const SliverPadding(padding: EdgeInsets.only(top: 50)),
              SliverToBoxAdapter(child: _topBar()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _cassetteHero(allTones.length, totalMin),
                ),
              ),
              SliverToBoxAdapter(
                child: _sideHeader(
                  'SIDE A',
                  _sideDuration(sideA),
                  _neonCyan,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _trackStrip(sideA[i], i + 1),
                  childCount: sideA.length,
                ),
              ),
              if (sideB.isNotEmpty)
                SliverToBoxAdapter(
                  child: _sideHeader(
                    'SIDE B',
                    _sideDuration(sideB),
                    _neonPink,
                  ),
                ),
              if (sideB.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _trackStrip(sideB[i], sideA.length + i + 1),
                    childCount: sideB.length,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 36)),
            ],
          ),
          LoadingOverlay(
            visible: _settingId != null,
            status: _toneLoadingStatus,
            accentColor: _neonPink,
            phase: _toneLoadingPhase,
          ),
        ],
      ),
    );
  }

  String _sideDuration(List<RingtoneTone> tones) {
    final secs = tones.fold<int>(0, (sum, t) => sum + t.durationSeconds);
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Top bar — back arrow only ─────────────────────────────────────
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.4),
                border: Border.all(
                    color: _neonPink.withValues(alpha: 0.6), width: 1),
              ),
              child: const Icon(Icons.arrow_back, color: _cream, size: 18),
            ),
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ── Cassette hero ─────────────────────────────────────────────────
  Widget _cassetteHero(int count, int totalMin) {
    final anyPlaying = _playingId != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_cassetteShellA, _cassetteShellB],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _neonPink, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _neonPink.withValues(alpha: 0.5),
            blurRadius: 28,
          ),
          BoxShadow(
            color: _neonCyan.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        children: [
          // Cassette label (pink/magenta gradient with text)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_cassetteLabelA, _cassetteLabelB],
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black, width: 1),
              boxShadow: [
                BoxShadow(
                  color: _cassetteLabelA.withValues(alpha: 0.6),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PIXORA TAPES · VOL ${widget.pack.id.hashCode % 99}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.pack.name.toUpperCase(),
                  style: GoogleFonts.bangers(
                    fontSize: 28,
                    color: Colors.white,
                    letterSpacing: 1.6,
                    height: 1.0,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$count TONES · ${totalMin}M · LO-FI MASTER',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Reels + tape bridge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Reel(size: 46, spinning: anyPlaying),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      color: _neonPink.withValues(alpha: 0.45),
                      boxShadow: [
                        BoxShadow(
                          color: _neonPink.withValues(alpha: 0.55),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _Reel(size: 46, spinning: anyPlaying),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ── SIDE A / SIDE B header ────────────────────────────────────────
  Widget _sideHeader(String label, String duration, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color, width: 1.2),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
              ],
            ),
            child: Text(
              label,
              style: GoogleFonts.bangers(
                fontSize: 14,
                color: color,
                letterSpacing: 2.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            duration,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _cream.withValues(alpha: 0.55),
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.35),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Track strip — single horizontal row ───────────────────────────
  Widget _trackStrip(RingtoneTone tone, int trackNum) {
    final isPlaying = _playingId == tone.id;
    final isSetting = _settingId == tone.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _togglePreview(tone),
          onLongPress: () => _showSetAsDialog(tone),
          borderRadius: BorderRadius.circular(8),
          splashColor: _neonPink.withValues(alpha: 0.2),
          highlightColor: _neonCyan.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            decoration: BoxDecoration(
              color: isPlaying
                  ? _neonPink.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isPlaying ? _neonPink : _violet.withValues(alpha: 0.25),
                width: isPlaying ? 1.5 : 1,
              ),
              boxShadow: isPlaying
                  ? [
                      BoxShadow(
                        color: _neonPink.withValues(alpha: 0.4),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Track number
                SizedBox(
                  width: 28,
                  child: Text(
                    trackNum.toString().padLeft(2, '0'),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _neonCyan.withValues(alpha: 0.75),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                // Title
                Expanded(
                  child: Text(
                    tone.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _cream,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                // Duration
                Text(
                  tone.durationFormatted,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _cream.withValues(alpha: 0.55),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 10),
                // Play / pause button — circle with neon glow when active
                _PlayCircle(
                  isPlaying: isPlaying,
                  isSetting: isSetting,
                ),
                // Menu icon for set-as
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  icon: Icon(
                    Icons.more_vert,
                    color: _cream.withValues(alpha: 0.4),
                    size: 18,
                  ),
                  onPressed: isSetting ? null : () => _showSetAsDialog(tone),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
//  Spinning cassette reel — twin disks on the hero
// ═════════════════════════════════════════════════════════════════════
class _Reel extends StatefulWidget {
  const _Reel({required this.size, required this.spinning});
  final double size;
  final bool spinning;
  @override
  State<_Reel> createState() => _ReelState();
}

class _ReelState extends State<_Reel> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.spinning) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _Reel old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_ctrl.isAnimating) _ctrl.repeat();
    if (!widget.spinning && _ctrl.isAnimating) _ctrl.stop();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.3, -0.3),
              colors: [Color(0xFF120829), Color(0xFF050010)],
            ),
            border: Border.all(
              color: _RingtonePackPageState._neonPink,
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: _RingtonePackPageState._neonPink.withValues(alpha: 0.5),
                blurRadius: 10,
              ),
            ],
          ),
          child: CustomPaint(
            painter: _ReelSpokesPainter(),
          ),
        ),
      ),
    );
  }
}

class _ReelSpokesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final hub = Paint()..color = _RingtonePackPageState._neonCyan;
    canvas.drawCircle(c, r * 0.18, hub);
    final spoke = Paint()
      ..color = _RingtonePackPageState._neonPink.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final a = (i / 6) * 2 * math.pi;
      canvas.drawLine(
        Offset(c.dx + math.cos(a) * r * 0.22, c.dy + math.sin(a) * r * 0.22),
        Offset(c.dx + math.cos(a) * r * 0.78, c.dy + math.sin(a) * r * 0.78),
        spoke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ReelSpokesPainter old) => false;
}

// ═════════════════════════════════════════════════════════════════════
//  Play / pause / loading circle for each track row
// ═════════════════════════════════════════════════════════════════════
class _PlayCircle extends StatelessWidget {
  const _PlayCircle({required this.isPlaying, required this.isSetting});
  final bool isPlaying;
  final bool isSetting;

  @override
  Widget build(BuildContext context) {
    if (isSetting) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: _RingtonePackPageState._neonPink,
        ),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            isPlaying ? _RingtonePackPageState._neonPink : Colors.transparent,
        border: Border.all(
          color: isPlaying
              ? _RingtonePackPageState._neonPink
              : _RingtonePackPageState._neonCyan.withValues(alpha: 0.7),
          width: 1.2,
        ),
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color:
                      _RingtonePackPageState._neonPink.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Icon(
        isPlaying ? Icons.pause : Icons.play_arrow,
        size: 16,
        color: isPlaying ? Colors.white : _RingtonePackPageState._neonCyan,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
//  Pixel grid bg — neon pink/cyan thin lines
// ═════════════════════════════════════════════════════════════════════
class _PixelGridBg extends StatelessWidget {
  const _PixelGridBg();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 14.0;
    final pinkPaint = Paint()
      ..color = _RingtonePackPageState._neonPink.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    final cyanPaint = Paint()
      ..color = _RingtonePackPageState._neonCyan.withValues(alpha: 0.035)
      ..strokeWidth = 0.5;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), cyanPaint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pinkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

extension on RingtoneTone {
  int get durationSeconds {
    // durationFormatted is like "0:28" — parse it
    final parts = durationFormatted.split(':');
    if (parts.length != 2) return 0;
    final m = int.tryParse(parts[0]) ?? 0;
    final s = int.tryParse(parts[1]) ?? 0;
    return m * 60 + s;
  }
}
