import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/services/ad_service.dart';
import '../../../../core/services/preview_player_service.dart';
import '../../../../core/services/ringtone_service.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
import '../../providers/ringtone_providers.dart';
import '../../data/models/ringtone_pack.dart';
import 'ringtone_pack_page.dart';

// ── Retro Cassette palette (concept #05, Eduardo 2026-05-15) ──────────
// Synthwave 80s — TONES tiene su propia personalidad audio (rompe a propósito
// con el Black & Gold del resto del app).
const _neonPink = Color(0xFFFF1493);
const _neonCyan = Color(0xFF00FFFF);
const _cream = Color(0xFFFFE6F8);
const _bgTop = Color(0xFF2A0A4A);
const _bgMid = Color(0xFF0A0533);
const _bgBot = Color(0xFF1A0A2A);
const _bodyA = Color(0xFF1A0A4A);
const _bodyB = Color(0xFF0A0530);

// ── Filter type ────────────────────────────────────────────────────
enum _ToneFilter { all, ringtone, notification, alarm }

class RingtonesPage extends ConsumerStatefulWidget {
  const RingtonesPage({super.key});

  @override
  ConsumerState<RingtonesPage> createState() => _RingtonesPageState();
}

class _RingtonesPageState extends ConsumerState<RingtonesPage> {
  _ToneFilter _filter = _ToneFilter.all;
  final _previewPlayer = PreviewPlayerService.instance;
  String? _playingId;
  String? _settingId;
  StreamSubscription? _playerSub;

  @override
  void dispose() {
    _playerSub?.cancel();
    _previewPlayer.stop();
    super.dispose();
  }

  // ── Preview playback ─────────────────────────────────────────────
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
      placement: 'ringtone_play',
      onAdDismissed: () {
        if (mounted) _doSetAs(tone, type);
      },
    );
  }

  Future<void> _showPermissionDialog(RingtoneTone tone, int type) async {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _bodyA,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _neonPink, width: 1),
          ),
          title: Row(
            children: [
              const Icon(Icons.settings, color: _neonCyan, size: 22),
              const SizedBox(width: 10),
              Text(
                LocaleHelper.pick(
                    es: 'Permiso necesario', en: 'Permission needed'),
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w700, color: _cream),
              ),
            ],
          ),
          content: Text(
            LocaleHelper.pick(
              es: 'Para asignar tonos, Pixora necesita permiso para modificar '
                  'la configuración del sistema. Toca "Abrir ajustes" y '
                  'activa el switch.',
              en: 'To set ringtones, Pixora needs permission to modify '
                  'system settings. Tap "Open Settings" and enable the toggle.',
            ),
            style: GoogleFonts.inter(
                color: _cream.withValues(alpha: 0.75),
                fontSize: 13,
                height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                LocaleHelper.pick(es: 'Cancelar', en: 'Cancel'),
                style: GoogleFonts.inter(color: _neonCyan),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              child: Text(
                LocaleHelper.pick(es: 'Abrir ajustes', en: 'Open Settings'),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _doSetAs(RingtoneTone tone, int type) async {
    setState(() => _settingId = tone.id);
    final path = await RingtoneService.instance.downloadTone(tone);
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download failed'),
            backgroundColor: _neonPink,
          ),
        );
      }
      setState(() => _settingId = null);
      return;
    }
    final typeNames = ['Ringtone', 'Notification', 'Alarm'];
    final success =
        await RingtoneService.instance.setAsRingtone(path, tone.name, type);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '${tone.name} → ${typeNames[type]}'
              : 'Failed to set ringtone'),
          backgroundColor: success ? _neonCyan : _neonPink,
        ),
      );
    }
    setState(() => _settingId = null);
  }

  void _showSetAsDialog(RingtoneTone tone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bodyA,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: _neonPink, width: 1),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: _neonCyan.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tone.name.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _cream,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              _buildSetOption(
                Icons.phone_in_talk,
                LocaleHelper.pick(es: 'Tono de llamada', en: 'Ringtone'),
                () {
                  Navigator.pop(ctx);
                  _setAs(tone, 0);
                },
              ),
              _buildSetOption(
                Icons.notifications,
                LocaleHelper.pick(es: 'Notificación', en: 'Notification'),
                () {
                  Navigator.pop(ctx);
                  _setAs(tone, 1);
                },
              ),
              _buildSetOption(
                Icons.alarm,
                LocaleHelper.pick(es: 'Alarma', en: 'Alarm'),
                () {
                  Navigator.pop(ctx);
                  _setAs(tone, 2);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSetOption(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: _neonCyan),
      title: Text(label,
          style: GoogleFonts.inter(
              color: _cream, fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: Icon(Icons.chevron_right, color: _cream.withValues(alpha: 0.4)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final packsAsync = ref.watch(ringtonePacksProvider);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.5, 1.0],
          colors: [_bgTop, _bgMid, _bgBot],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _PixelGridBg()),
          // Synthwave horizon at bottom
          Positioned(
            left: -60,
            right: -60,
            bottom: -60,
            height: 220,
            child: IgnorePointer(
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(0.7),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        _neonPink.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.7],
                    ),
                  ),
                ),
              ),
            ),
          ),
          packsAsync.when(
            loading: () => const _ShimmerLoading(),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: _neonPink, size: 48),
                  const SizedBox(height: 12),
                  Text('Failed to load tones',
                      style: GoogleFonts.inter(
                          color: _cream.withValues(alpha: 0.6))),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.invalidate(ringtonePacksProvider),
                    child: Text('Retry',
                        style: GoogleFonts.inter(color: _neonCyan)),
                  ),
                ],
              ),
            ),
            data: (packs) {
              if (packs.isEmpty) {
                return Center(
                  child: Text(
                    'No tones available yet',
                    style:
                        GoogleFonts.inter(color: _cream.withValues(alpha: 0.6)),
                  ),
                );
              }
              return _buildDiscoveryView(packs);
            },
          ),
        ],
      ),
    );
  }

  List<RingtoneTone> _packFilteredTones(RingtonePack pack) {
    if (_filter == _ToneFilter.all) return pack.tones;
    return pack.tones.where((t) {
      switch (_filter) {
        case _ToneFilter.ringtone:
          return t.suggestedType == 'ringtone';
        case _ToneFilter.notification:
          return t.suggestedType == 'notification';
        case _ToneFilter.alarm:
          return t.suggestedType == 'alarm';
        case _ToneFilter.all:
          return true;
      }
    }).toList();
  }

  Widget _buildDiscoveryView(List<RingtonePack> packs) {
    final featured = packs.first;
    final featuredFiltered = _packFilteredTones(featured);

    final recommended = <RingtoneTone>[];
    for (final pack in packs.skip(1)) {
      final filtered = _packFilteredTones(pack);
      if (filtered.isNotEmpty) {
        recommended.add(filtered[0]);
        if (filtered.length > 2) recommended.add(filtered[2]);
      }
    }

    final packSections = <Widget>[];
    for (final pack in packs.skip(1)) {
      final filtered = _packFilteredTones(pack);
      if (filtered.isNotEmpty) {
        packSections.add(const SizedBox(height: 22));
        packSections.add(_buildSectionHeader(pack.name, () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => RingtonePackPage(pack: pack)));
        }));
        packSections.add(const SizedBox(height: 10));
        packSections.add(_buildToneGrid(filtered));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          _buildFilterChips(),
          const SizedBox(height: 14),
          // ── Featured Cassette Hero ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _CassetteHero(
              pack: featured,
              currentlyPlayingTone: featuredFiltered.firstWhere(
                (t) => t.id == _playingId,
                orElse: () => featuredFiltered.isNotEmpty
                    ? featuredFiltered.first
                    : RingtoneTone(
                        id: '',
                        name: featured.name,
                        file: '',
                        duration: 0,
                        suggestedType: 'ringtone',
                      ),
              ),
              isPlaying: _playingId != null &&
                  featuredFiltered.any((t) => t.id == _playingId),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RingtonePackPage(pack: featured),
                ),
              ),
            ),
          ),
          if (recommended.isNotEmpty) ...[
            const SizedBox(height: 22),
            _buildSectionHeader(
              LocaleHelper.pick(es: 'TOP MIXTAPE', en: 'TOP MIXTAPE'),
              null,
            ),
            const SizedBox(height: 10),
            _buildRecommendedRow(recommended, packs),
          ],
          ...packSections,
        ],
      ),
    );
  }

  // ── Filter Chips (neon synthwave) ─────────────────────────────────
  Widget _buildFilterChips() {
    final filters = [
      (
        _ToneFilter.all,
        LocaleHelper.pick(es: 'TODOS', en: 'ALL'),
        Icons.music_note
      ),
      (
        _ToneFilter.ringtone,
        LocaleHelper.pick(es: 'RING', en: 'RING'),
        Icons.phone_in_talk
      ),
      (
        _ToneFilter.notification,
        LocaleHelper.pick(es: 'MSG', en: 'MSG'),
        Icons.notifications
      ),
      (
        _ToneFilter.alarm,
        LocaleHelper.pick(es: 'ALARMA', en: 'ALARM'),
        Icons.alarm
      ),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (filter, label, icon) = filters[i];
          final selected = _filter == filter;
          return GestureDetector(
            onTap: () => setState(() => _filter = filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? _neonPink : _neonCyan.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color:
                      selected ? _neonPink : _neonCyan.withValues(alpha: 0.45),
                  width: 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: _neonPink.withValues(alpha: 0.55),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 13,
                    color: selected ? Colors.white : _neonCyan,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : _neonCyan,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Section Header (neon glow) ────────────────────────────────────
  Widget _buildSectionHeader(String title, VoidCallback? onSeeAll) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('★', style: TextStyle(color: _neonPink, fontSize: 11)),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _cream,
                  letterSpacing: 2.0,
                  shadows: [
                    Shadow(
                      color: _neonPink.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    LocaleHelper.pick(es: 'VER TODO', en: 'SEE ALL'),
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: _neonCyan,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right, size: 14, color: _neonCyan),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Top Mixtape (horizontal mini cassettes) ───────────────────────
  Widget _buildRecommendedRow(
      List<RingtoneTone> tones, List<RingtonePack> packs) {
    return SizedBox(
      // 120, not 86 — _TapeMini content (top stripe + reels + title + duration
      // + indicator + WallpaperStatsBar) is ~96-116px depending on whether the
      // stats bar is in its 20px or 40px state. Previous 86 over-flowed by 23px
      // on Samsung A15 (4 simultaneous warnings, one per visible card).
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: tones.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final tone = tones[i];
          return _TapeMini(
            title: tone.name,
            duration: tone.durationFormatted,
            isPlaying: _playingId == tone.id,
            isSetting: _settingId == tone.id,
            onTap: () => _togglePreview(tone),
            onLongPress: () => _showSetAsDialog(tone),
            width: 110,
            statsId: 'tone_${tone.id}',
          );
        },
      ),
    );
  }

  // ── Tone Grid (3 columns, mini cassettes) ─────────────────────────
  Widget _buildToneGrid(List<RingtoneTone> tones) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          // 0.82 (height > width) — the cassette mini has top stripe + reels
          // row + title + duration + bottom stats. Previous 1.05 over-flowed
          // by ~23px on Samsung. 2026-05-16 fix.
          childAspectRatio: 0.82,
        ),
        itemCount: tones.length > 6 ? 6 : tones.length,
        itemBuilder: (_, i) {
          final tone = tones[i];
          return _TapeMini(
            title: tone.name,
            duration: tone.durationFormatted,
            isPlaying: _playingId == tone.id,
            isSetting: _settingId == tone.id,
            onTap: () => _togglePreview(tone),
            onLongPress: () => _showSetAsDialog(tone),
            statsId: 'tone_${tone.id}',
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Pixel grid background overlay
// ═════════════════════════════════════════════════════════════════════
class _PixelGridBg extends StatelessWidget {
  const _PixelGridBg();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 14.0;
    final pinkPaint = Paint()
      ..color = _neonPink.withValues(alpha: 0.05)
      ..strokeWidth = 0.6;
    final cyanPaint = Paint()
      ..color = _neonCyan.withValues(alpha: 0.04)
      ..strokeWidth = 0.6;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), cyanPaint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pinkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═════════════════════════════════════════════════════════════════════
// Cassette Hero — featured pack as a giant cassette tape
// ═════════════════════════════════════════════════════════════════════
class _CassetteHero extends StatelessWidget {
  const _CassetteHero({
    required this.pack,
    required this.currentlyPlayingTone,
    required this.isPlaying,
    required this.onTap,
  });
  final RingtonePack pack;
  final RingtoneTone currentlyPlayingTone;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = (isPlaying && currentlyPlayingTone.name.isNotEmpty)
        ? currentlyPlayingTone.name
        : pack.name;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 168,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bodyA, _bodyB],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _neonPink, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _neonPink.withValues(alpha: 0.4),
              blurRadius: 24,
            ),
            BoxShadow(
              color: _neonCyan.withValues(alpha: 0.08),
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Top stripe — pink to cyan gradient
            Container(
              height: 12,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_neonPink, _neonCyan],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _neonCyan.withValues(alpha: 0.10),
                      border: Border.all(
                        color: _neonCyan.withValues(alpha: 0.45),
                        width: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      pack.category.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: _neonCyan,
                        letterSpacing: 1.8,
                        shadows: [
                          Shadow(
                            color: _neonCyan.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'SIDE A',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: _neonPink,
                      letterSpacing: 2,
                      shadows: [
                        Shadow(
                          color: _neonPink.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Reels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Reel(size: 36, spinning: isPlaying),
                  _Reel(size: 36, spinning: isPlaying),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _cream,
                  letterSpacing: 0.6,
                  shadows: [
                    Shadow(
                      color: _neonPink.withValues(alpha: 0.65),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${pack.tones.length} ${LocaleHelper.pick(es: "TRACKS", en: "TRACKS")} · ${pack.description.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: _neonCyan.withValues(alpha: 0.9),
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Mini cassette tape — used for both Top Mixtape row and tone grid
// ═════════════════════════════════════════════════════════════════════
class _TapeMini extends StatelessWidget {
  const _TapeMini({
    required this.title,
    required this.duration,
    required this.isPlaying,
    required this.isSetting,
    required this.onTap,
    required this.onLongPress,
    required this.statsId,
    this.width,
  });
  final String title;
  final String duration;
  final bool isPlaying;
  final bool isSetting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String statsId;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: width,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bodyA, _bodyB],
          ),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isPlaying ? _neonCyan : _neonPink.withValues(alpha: 0.5),
            width: isPlaying ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (isPlaying ? _neonCyan : _neonPink)
                  .withValues(alpha: isPlaying ? 0.6 : 0.18),
              blurRadius: isPlaying ? 18 : 8,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Top stripe
            Container(
              height: 5,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_neonPink, _neonCyan],
                ),
              ),
            ),
            // Reels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Reel(size: 14, spinning: isPlaying),
                  _Reel(size: 14, spinning: isPlaying),
                ],
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: _cream,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '— $duration',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 7.5,
                fontWeight: FontWeight.w600,
                color: _neonCyan.withValues(alpha: 0.7),
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            // Bottom indicator: playing state + stats
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSetting)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: _neonPink,
                      ),
                    )
                  else if (isPlaying)
                    const _MiniWave(color: _neonCyan)
                  else
                    Icon(
                      Icons.play_arrow_rounded,
                      size: 14,
                      color: _neonPink.withValues(alpha: 0.85),
                    ),
                ],
              ),
            ),
            // Stats bar (small footer)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 2),
              color: Colors.black.withValues(alpha: 0.25),
              child: Center(
                child: WallpaperStatsBar(
                  wallpaperId: statsId,
                  glowColor: _neonCyan,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Cassette reel — conic gradient pink/cyan, spins when playing
// ═════════════════════════════════════════════════════════════════════
class _Reel extends StatefulWidget {
  const _Reel({required this.size, required this.spinning});
  final double size;
  final bool spinning;

  @override
  State<_Reel> createState() => _ReelState();
}

class _ReelState extends State<_Reel> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.spinning) _c.repeat();
  }

  @override
  void didUpdateWidget(_Reel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.spinning && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Transform.rotate(
          angle: _c.value * 2 * math.pi,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(
                colors: [_neonCyan, _neonPink, _neonCyan],
              ),
              border: Border.all(
                color: _neonCyan.withValues(alpha: 0.5),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: _neonPink.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: widget.size * 0.32,
                height: widget.size * 0.32,
                decoration: BoxDecoration(
                  color: _bgBot,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _neonPink.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Mini playing wave (4 bars)
// ═════════════════════════════════════════════════════════════════════
class _MiniWave extends StatefulWidget {
  final Color color;
  const _MiniWave({required this.color});

  @override
  State<_MiniWave> createState() => _MiniWaveState();
}

class _MiniWaveState extends State<_MiniWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(4, (i) {
          final phase = (_c.value + i * 0.18) % 1.0;
          final h = 3.0 + 8.0 * (0.5 + 0.5 * math.sin(phase * math.pi * 2));
          return Container(
            width: 2,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(1),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.6),
                  blurRadius: 3,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Shimmer Loading
// ═════════════════════════════════════════════════════════════════════
class _ShimmerLoading extends StatelessWidget {
  const _ShimmerLoading();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              3,
              (i) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Shimmer.fromColors(
                  baseColor: _bodyA,
                  highlightColor: _bodyB,
                  child: Container(
                    width: 70,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _bodyA,
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Shimmer.fromColors(
            baseColor: _bodyA,
            highlightColor: _bodyB,
            child: Container(
              height: 168,
              decoration: BoxDecoration(
                color: _bodyA,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Shimmer.fromColors(
            baseColor: _bodyA,
            highlightColor: _bodyB,
            child: Container(
              width: 140,
              height: 14,
              decoration: BoxDecoration(
                color: _bodyA,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
