import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/widgets/ticket_stub_card.dart';
import '../../../../core/services/preview_player_service.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/widgets/section_hero_banner.dart';
import '../../../../core/services/ringtone_service.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
import '../../providers/ringtone_providers.dart';
import '../../data/models/ringtone_pack.dart';
import 'ringtone_pack_page.dart';

// ── Filter type ────────────────────────────────────────────────────
enum _ToneFilter { all, ringtone, notification, alarm }

// ── Main page ──────────────────────────────────────────────────────
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
              backgroundColor: HudTokens.goldDeep),
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
    await _doSetAs(tone, type);
  }

  Future<void> _showPermissionDialog(RingtoneTone tone, int type) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTokens.nightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.settings, color: HudTokens.goldBright, size: 24),
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
              backgroundColor: HudTokens.gold,
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
    setState(() => _settingId = tone.id);
    final path = await RingtoneService.instance.downloadTone(tone);
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Download failed'),
              backgroundColor: HudTokens.goldDeep),
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
              ? '${tone.name} set as ${typeNames[type]}!'
              : 'Failed to set ringtone'),
          backgroundColor: success ? HudTokens.gold : HudTokens.goldDeep,
        ),
      );
    }
    setState(() => _settingId = null);
  }

  void _showSetAsDialog(RingtoneTone tone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: HudTokens.nightSurface,
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
      leading: Icon(icon, color: HudTokens.gold),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────
  Color _parseGlow(String hex) => parseHexColor(hex);

  List<Color> _toneGradient(RingtoneTone tone, Color glow) {
    // Black & Gold: ignore per-character brand colors — every tone renders on
    // a unified gold gradient. Was previously 22 hardcoded palettes.
    return const [HudTokens.goldDeep, HudTokens.nightBg];
  }

  IconData _toneIcon(RingtoneTone tone) {
    final n = tone.name.toLowerCase();
    if (n.contains('mario') ||
        n.contains('yoshi') ||
        n.contains('coin') ||
        n.contains('powerup') ||
        n.contains('level')) return Icons.videogame_asset;
    if (n.contains('goku') ||
        n.contains('saiyan') ||
        n.contains('kamehameha') ||
        n.contains('dragon') ||
        n.contains('dbgt')) return Icons.flash_on;
    if (n.contains('zelda') ||
        n.contains('navi') ||
        n.contains('hyrule') ||
        n.contains('fairy') ||
        n.contains('rupee')) return Icons.shield;
    if (n.contains('homero') ||
        n.contains('simpson') ||
        n.contains('bob') ||
        n.contains('esponja') ||
        n.contains('sponge')) return Icons.tv;
    if (n.contains('death') || n.contains('note')) return Icons.menu_book;
    if (n.contains('shrek')) return Icons.forest;
    if (n.contains('phone') ||
        n.contains('rotary') ||
        n.contains('classic') ||
        n.contains('nokia')) return Icons.phone_callback;
    if (n.contains('iphone') ||
        n.contains('modern') ||
        n.contains('digital') ||
        n.contains('future')) return Icons.smartphone;
    if (n.contains('soft') ||
        n.contains('gentle') ||
        n.contains('ambient') ||
        n.contains('chill')) return Icons.spa;
    if (n.contains('alarm') || n.contains('alert')) return Icons.alarm;
    if (n.contains('minecraft')) return Icons.landscape;
    if (n.contains('fnaf')) return Icons.nights_stay;
    if (n.contains('hadouken') || n.contains('street')) return Icons.sports_mma;
    if (n.contains('fall guys')) return Icons.emoji_events;
    if (n.contains('hazbin') || n.contains('alastor'))
      return Icons.local_fire_department;
    if (n.contains('casa') || n.contains('papel')) return Icons.masks;
    if (n.contains('pou')) return Icons.pets;
    if (n.contains('kill bill')) return Icons.content_cut;
    return Icons.music_note;
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final packsAsync = ref.watch(ringtonePacksProvider);

    return packsAsync.when(
      loading: () => const _ShimmerLoading(),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: HudTokens.goldDeep, size: 48),
            const SizedBox(height: 12),
            const Text('Failed to load tones',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(ringtonePacksProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (packs) {
        if (packs.isEmpty) {
          return const Center(
            child: Text('No tones available yet',
                style: TextStyle(color: Colors.white54)),
          );
        }
        return _buildDiscoveryView(packs);
      },
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
    // Pick recommended tones (mix from different packs)
    final recommended = <RingtoneTone>[];
    for (final pack in packs) {
      final filtered = _packFilteredTones(pack);
      if (filtered.isNotEmpty) {
        recommended.add(filtered[0]);
        if (filtered.length > 2) recommended.add(filtered[2]);
      }
    }

    // Build pack section widgets
    final packSections = <Widget>[];
    for (final pack in packs) {
      final filtered = _packFilteredTones(pack);
      if (filtered.isNotEmpty) {
        packSections.add(const SizedBox(height: 24));
        packSections.add(_buildSectionHeader(pack.name, () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => RingtonePackPage(pack: pack)));
        }));
        packSections.add(const SizedBox(height: 12));
        packSections.add(_buildToneGrid(filtered, _parseGlow(pack.glowColor)));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Filter Chips ──────────────────────────────────────
          const SizedBox(height: 8),
          _buildFilterChips(),

          // ── Hero Banner ───────────────────────────────────────
          const SizedBox(height: 16),
          SectionHeroBanner(
            items: packs
                .take(5)
                .map((pack) => HeroBannerItem(
                      imageUrl: pack.previewUrl,
                      title: pack.name,
                      subtitle:
                          '${pack.tones.length} tones \u00b7 ${pack.description}',
                      badge: pack.category,
                      accentColor: HudTokens.gold,
                    ))
                .toList(),
            onTap: (i) => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RingtonePackPage(pack: packs[i]),
                )),
            height: 0.32,
          ),

          // ── Recommended ───────────────────────────────────────
          if (recommended.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSectionHeader('Recommended for You', null),
            const SizedBox(height: 12),
            _buildRecommendedRow(recommended, packs),
          ],

          // ── Pack Sections ─────────────────────────────────────
          ...packSections,
        ],
      ),
    );
  }

  // ── Filter Chips ──────────────────────────────────────────────────
  Widget _buildFilterChips() {
    final filters = [
      (_ToneFilter.all, 'All', Icons.music_note),
      (_ToneFilter.ringtone, 'Ringtones', Icons.phone_in_talk),
      (_ToneFilter.notification, 'Messages', Icons.notifications),
      (_ToneFilter.alarm, 'Alarms', Icons.alarm),
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (filter, label, icon) = filters[i];
          final selected = _filter == filter;
          return GestureDetector(
            onTap: () => setState(() => _filter = filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? HudTokens.gold : HudTokens.nightSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? HudTokens.gold : Colors.white12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 16,
                      color: selected ? Colors.white : Colors.white54),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: selected ? Colors.white : Colors.white54,
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

  // ── Section Header ────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, VoidCallback? onSeeAll) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 13,
                      color: HudTokens.gold.withOpacity(0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      size: 18, color: HudTokens.gold.withOpacity(0.9)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Recommended Row (horizontal scroll) ───────────────────────────
  Widget _buildRecommendedRow(
      List<RingtoneTone> tones, List<RingtonePack> packs) {
    // Assign badges
    final badges = <String, String>{};
    if (tones.isNotEmpty) badges[tones[0].id] = 'POPULAR';
    if (tones.length > 1) badges[tones[1].id] = 'NEW';
    if (tones.length > 3) badges[tones[3].id] = 'TOP';

    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tones.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final tone = tones[i];
          // Find glow color from parent pack
          final parentPack = packs.firstWhere(
            (p) => p.tones.any((t) => t.id == tone.id),
            orElse: () => packs.first,
          );
          final glow = _parseGlow(parentPack.glowColor);

          return _RecommendedCard(
            tone: tone,
            glow: glow,
            gradient: _toneGradient(tone, glow),
            icon: _toneIcon(tone),
            badge: badges[tone.id],
            isPlaying: _playingId == tone.id,
            isSetting: _settingId == tone.id,
            onTap: () => _togglePreview(tone),
            onLongPress: () => _showSetAsDialog(tone),
            index: i,
          );
        },
      ),
    );
  }

  // ── Tone Grid (2 columns per pack section) ────────────────────────
  Widget _buildToneGrid(List<RingtoneTone> tones, Color glow) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.6,
        ),
        itemCount: tones.length > 6 ? 6 : tones.length,
        itemBuilder: (_, i) {
          final tone = tones[i];
          return _ToneGridCard(
            tone: tone,
            glow: glow,
            gradient: _toneGradient(tone, glow),
            icon: _toneIcon(tone),
            isPlaying: _playingId == tone.id,
            isSetting: _settingId == tone.id,
            onTap: () => _togglePreview(tone),
            onLongPress: () => _showSetAsDialog(tone),
          );
        },
      ),
    );
  }
}

// ── Default preview helper ──────────────────────────────────────────
// No bundled asset anymore — the previous `tone_preview_default.webp`
// was a Supabase-generated placeholder with "DON'T USE UPLOADED BY 25 PIXELS"
// watermark rendered into the image itself. Now we draw a clean Black & Gold
// background with a soft radial vignette so it reads as intentional.
Widget _toneBackground(
        RingtoneTone tone, List<Color> gradient, IconData icon) =>
    _assetPreview(gradient, icon);

Widget _assetPreview(List<Color> gradient, IconData icon) {
  return Container(
    decoration: BoxDecoration(
      color: HudTokens.nightSurfaceHi,
      gradient: RadialGradient(
        colors: [
          HudTokens.gold.withOpacity(0.12),
          HudTokens.nightSurface,
        ],
        radius: 0.95,
      ),
    ),
  );
}

// ── Recommended Card ────────────────────────────────────────────────
/// Editorial Black & Gold card for a tone. Sharp gold frame, numeric index,
/// Playfair title, serif italic type label. No gradient backgrounds — the
/// color comes from a subtle breathing-gold glow around the play button.
class _RecommendedCard extends StatelessWidget {
  final RingtoneTone tone;
  final Color glow; // kept for API compat; ignored — always uses gold
  final List<Color> gradient; // kept for API compat; no longer rendered
  final IconData icon;
  final String? badge;
  final bool isPlaying;
  final bool isSetting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final int index;

  const _RecommendedCard({
    required this.tone,
    required this.glow,
    required this.gradient,
    required this.icon,
    this.badge,
    required this.isPlaying,
    required this.isSetting,
    required this.onTap,
    required this.onLongPress,
    this.index = 0,
  });

  String _roman(int n) {
    // Supports 1..20 (enough for horizontal card rows).
    const r = [
      '',
      'I',
      'II',
      'III',
      'IV',
      'V',
      'VI',
      'VII',
      'VIII',
      'IX',
      'X',
      'XI',
      'XII',
      'XIII',
      'XIV',
      'XV',
      'XVI',
      'XVII',
      'XVIII',
      'XIX',
      'XX',
    ];
    return n >= 1 && n < r.length ? r[n] : n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 150,
        decoration: BoxDecoration(
          color: HudTokens.nightSurface,
          border: Border.all(
            color: isPlaying
                ? HudTokens.goldBright
                : HudTokens.gold.withOpacity(0.45),
            width: isPlaying ? 2 : 1,
          ),
          boxShadow: isPlaying
              ? [
                  BoxShadow(
                    color: HudTokens.gold.withOpacity(0.35),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'No. ${_roman(index + 1)}',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                    color: HudTokens.gold,
                    letterSpacing: 0.15,
                  ),
                ),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: HudTokens.gold,
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isPlaying)
                    // Subtle radial breathing glow behind the play button.
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            HudTokens.gold.withOpacity(0.35),
                            HudTokens.gold.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: HudTokens.gold, width: 1.2),
                      color: HudTokens.nightBg,
                    ),
                    child: _PlayButton(
                      isPlaying: isPlaying,
                      isSetting: isSetting,
                      glow: HudTokens.gold,
                      size: 54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (isPlaying)
              Center(child: _MiniWave(color: HudTokens.gold))
            else
              const SizedBox(height: 16),
            const SizedBox(height: 10),
            Text(
              tone.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.01,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '— ${_typeLabel(tone.suggestedType).toLowerCase()} · ${tone.durationFormatted}',
              style: TextStyle(
                fontFamily: 'serif',
                fontStyle: FontStyle.italic,
                fontSize: 11,
                color: HudTokens.gold.withOpacity(0.75),
                letterSpacing: 0.05,
              ),
            ),
          ],
        ),
      ),
    );
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
}

// ── Play Button (reusable, prominent style like RingFlix) ───────────
class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final bool isSetting;
  final Color glow;
  final double size;

  const _PlayButton({
    required this.isPlaying,
    required this.isSetting,
    required this.glow,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    if (isSetting) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.22),
          child: CircularProgressIndicator(strokeWidth: 2.5, color: glow),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
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
        size: size * 0.55,
      ),
    );
  }
}

// ── Tone Grid Card (Ticket Stub) ────────────────────────────────────
class _ToneGridCard extends StatelessWidget {
  final RingtoneTone tone;
  final Color glow; // kept for API compat — ignored
  final List<Color> gradient; // kept for API compat — ignored
  final IconData icon;
  final bool isPlaying;
  final bool isSetting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ToneGridCard({
    required this.tone,
    required this.glow,
    required this.gradient,
    required this.icon,
    required this.isPlaying,
    required this.isSetting,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: TicketStubCard(
        admitLabel: isPlaying ? 'NOW' : 'TONE',
        title: tone.name,
        category: tone.durationFormatted.toUpperCase(),
        isHighlighted: isPlaying,
        onTap: onTap,
        overlayTopRight: WallpaperStatsBar(
          wallpaperId: 'tone_${tone.id}',
          glowColor: HudTokens.gold,
        ),
        child: Container(
          color: HudTokens.nightSurfaceHi,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Gold radial glow that pulses when playing.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      HudTokens.gold.withOpacity(isPlaying ? 0.4 : 0.15),
                      Colors.transparent,
                    ],
                    radius: 0.8,
                  ),
                ),
              ),
              // Center icon + play ring
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: HudTokens.gold, size: 26),
                    const SizedBox(height: 8),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HudTokens.nightBg.withOpacity(0.5),
                        border: Border.all(color: HudTokens.gold, width: 1),
                      ),
                      child: _PlayButton(
                        isPlaying: isPlaying,
                        isSetting: isSetting,
                        glow: HudTokens.gold,
                        size: 38,
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
                  child: Center(child: _MiniWave(color: HudTokens.gold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mini Playing Wave ───────────────────────────────────────────────
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
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
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
          final h = 4.0 + 10.0 * (0.5 + 0.5 * math.sin(phase * math.pi * 2));
          return Container(
            width: 2.5,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(color: widget.color.withOpacity(0.4), blurRadius: 3)
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ── Shimmer Loading ─────────────────────────────────────────────────
class _ShimmerLoading extends StatelessWidget {
  const _ShimmerLoading();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter chips shimmer
          Row(
            children: List.generate(
                3,
                (i) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Shimmer.fromColors(
                        baseColor: HudTokens.nightSurface,
                        highlightColor: HudTokens.nightSurfaceHi,
                        child: Container(
                          width: 90,
                          height: 36,
                          decoration: BoxDecoration(
                            color: HudTokens.nightSurface,
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    )),
          ),
          const SizedBox(height: 16),
          // Hero shimmer
          Shimmer.fromColors(
            baseColor: HudTokens.nightSurface,
            highlightColor: HudTokens.nightSurfaceHi,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: HudTokens.nightSurface,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Section shimmer
          Shimmer.fromColors(
            baseColor: HudTokens.nightSurface,
            highlightColor: HudTokens.nightSurfaceHi,
            child: Container(
              width: 160,
              height: 20,
              decoration: BoxDecoration(
                color: HudTokens.nightSurface,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Cards shimmer row
          SizedBox(
            height: 170,
            child: Row(
              children: List.generate(
                  3,
                  (i) => Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Shimmer.fromColors(
                          baseColor: HudTokens.nightSurface,
                          highlightColor: HudTokens.nightSurfaceHi,
                          child: Container(
                            width: 140,
                            height: 170,
                            decoration: BoxDecoration(
                              color: HudTokens.nightSurface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      )),
            ),
          ),
        ],
      ),
    );
  }
}
