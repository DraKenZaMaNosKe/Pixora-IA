import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shimmer/shimmer.dart';
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
  final AudioPlayer _player = AudioPlayer();
  String? _playingId;
  String? _settingId;
  StreamSubscription? _playerSub;

  @override
  void dispose() {
    _playerSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ── Preview playback ─────────────────────────────────────────────
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

  // ── Set as ringtone/notification/alarm ────────────────────────────
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
              backgroundColor: const Color(0xFF7C4DFF),
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
            Text(tone.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
      leading: Icon(icon, color: const Color(0xFF7C4DFF)),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────
  Color _parseGlow(String hex) => parseHexColor(hex);

  List<Color> _toneGradient(RingtoneTone tone, Color fallback) {
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
    return [fallback, fallback.withOpacity(0.3)];
  }

  IconData _toneIcon(RingtoneTone tone) {
    final n = tone.name.toLowerCase();
    if (n.contains('mario') || n.contains('yoshi') || n.contains('coin') || n.contains('powerup') || n.contains('level')) return Icons.videogame_asset;
    if (n.contains('goku') || n.contains('saiyan') || n.contains('kamehameha') || n.contains('dragon') || n.contains('dbgt')) return Icons.flash_on;
    if (n.contains('zelda') || n.contains('navi') || n.contains('hyrule') || n.contains('fairy') || n.contains('rupee')) return Icons.shield;
    if (n.contains('homero') || n.contains('simpson') || n.contains('bob') || n.contains('esponja') || n.contains('sponge')) return Icons.tv;
    if (n.contains('death') || n.contains('note')) return Icons.menu_book;
    if (n.contains('shrek')) return Icons.forest;
    if (n.contains('phone') || n.contains('rotary') || n.contains('classic') || n.contains('nokia')) return Icons.phone_callback;
    if (n.contains('iphone') || n.contains('modern') || n.contains('digital') || n.contains('future')) return Icons.smartphone;
    if (n.contains('soft') || n.contains('gentle') || n.contains('ambient') || n.contains('chill')) return Icons.spa;
    if (n.contains('alarm') || n.contains('alert')) return Icons.alarm;
    if (n.contains('minecraft')) return Icons.landscape;
    if (n.contains('fnaf')) return Icons.nights_stay;
    if (n.contains('hadouken') || n.contains('street')) return Icons.sports_mma;
    if (n.contains('fall guys')) return Icons.emoji_events;
    if (n.contains('hazbin') || n.contains('alastor')) return Icons.local_fire_department;
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
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
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
        case _ToneFilter.ringtone: return t.suggestedType == 'ringtone';
        case _ToneFilter.notification: return t.suggestedType == 'notification';
        case _ToneFilter.alarm: return t.suggestedType == 'alarm';
        case _ToneFilter.all: return true;
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
            items: packs.take(5).map((pack) => HeroBannerItem(
              imageUrl: pack.previewUrl,
              title: pack.name,
              subtitle: '${pack.tones.length} tones \u00b7 ${pack.description}',
              badge: pack.category,
              accentColor: parseHexColor(pack.glowColor, fallback: const Color(0xFFE50914)),
            )).toList(),
            onTap: (i) => Navigator.push(context, MaterialPageRoute(
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
                color: selected ? const Color(0xFF7C4DFF) : const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? const Color(0xFF7C4DFF) : Colors.white12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16,
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
                      color: const Color(0xFF7C4DFF).withOpacity(0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      size: 18, color: const Color(0xFF7C4DFF).withOpacity(0.9)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Recommended Row (horizontal scroll) ───────────────────────────
  Widget _buildRecommendedRow(List<RingtoneTone> tones, List<RingtonePack> packs) {
    // Assign badges
    final badges = <String, String>{};
    if (tones.isNotEmpty) badges[tones[0].id] = 'POPULAR';
    if (tones.length > 1) badges[tones[1].id] = 'NEW';
    if (tones.length > 3) badges[tones[3].id] = 'TOP';

    return SizedBox(
      height: 170,
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
          childAspectRatio: 0.82,
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

// ── Default preview image helper ────────────────────────────────────
const _defaultPreviewAsset = 'assets/tone_preview_default.webp';

Widget _toneBackground(RingtoneTone tone, List<Color> gradient, IconData icon) {
  final hasImage = tone.previewImageUrl.isNotEmpty;
  if (hasImage) {
    return CachedNetworkImage(
      imageUrl: tone.previewImageUrl,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => _assetPreview(gradient, icon),
    );
  }
  return _assetPreview(gradient, icon);
}

Widget _assetPreview(List<Color> gradient, IconData icon) {
  return Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(_defaultPreviewAsset, fit: BoxFit.cover),
      // Color tint overlay to differentiate each tone
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              gradient[0].withOpacity(0.45),
              gradient[1].withOpacity(0.35),
            ],
          ),
        ),
      ),
    ],
  );
}

// ── Recommended Card ────────────────────────────────────────────────
class _RecommendedCard extends StatelessWidget {
  final RingtoneTone tone;
  final Color glow;
  final List<Color> gradient;
  final IconData icon;
  final String? badge;
  final bool isPlaying;
  final bool isSetting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: isPlaying
              ? Border.all(color: glow, width: 2)
              : Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: isPlaying
              ? [BoxShadow(color: glow.withOpacity(0.4), blurRadius: 16)]
              : [BoxShadow(color: glow.withOpacity(0.08), blurRadius: 8)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background image
              _toneBackground(tone, gradient, icon),

              // Dark overlay for readability
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.1),
                      Colors.black.withOpacity(0.75),
                    ],
                  ),
                ),
              ),

              // Badge
              if (badge != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badge == 'POPULAR'
                          ? const Color(0xFFFF6B35)
                          : badge == 'NEW'
                              ? const Color(0xFF00E676)
                              : const Color(0xFF7C4DFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

              // Duration badge top-right
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tone.durationFormatted,
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ),
              ),

              // ── Play/Stop Button (prominent, like RingFlix) ──
              Center(
                child: _PlayButton(
                  isPlaying: isPlaying,
                  isSetting: isSetting,
                  glow: glow,
                  size: 48,
                ),
              ),

              // Playing wave
              if (isPlaying)
                Positioned(
                  bottom: 44,
                  left: 0,
                  right: 0,
                  child: Center(child: _MiniWave(color: glow)),
                ),

              // Stats
              Positioned(
                bottom: 42,
                left: 6,
                child: WallpaperStatsBar(
                  wallpaperId: 'tone_${tone.id}',
                  glowColor: glow,
                ),
              ),

              // Bottom info
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(_typeIconSmall(tone.suggestedType), size: 10, color: glow),
                          const SizedBox(width: 4),
                          Text(
                            _typeLabel(tone.suggestedType),
                            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5)),
                          ),
                        ],
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

  IconData _typeIconSmall(String type) {
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
            ? [BoxShadow(color: glow.withOpacity(0.6), blurRadius: 16, spreadRadius: 2)]
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

// ── Tone Grid Card ──────────────────────────────────────────────────
class _ToneGridCard extends StatelessWidget {
  final RingtoneTone tone;
  final Color glow;
  final List<Color> gradient;
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
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: isPlaying
              ? Border.all(color: glow, width: 2)
              : Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: isPlaying
              ? [BoxShadow(color: glow.withOpacity(0.35), blurRadius: 14)]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background with default preview image
              _toneBackground(tone, gradient, icon),

              // Dark gradient overlay
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

              // Play/stop button (prominent)
              Center(
                child: _PlayButton(
                  isPlaying: isPlaying,
                  isSetting: isSetting,
                  glow: glow,
                  size: 40,
                ),
              ),

              // Playing wave
              if (isPlaying)
                Positioned(
                  bottom: 32,
                  left: 0, right: 0,
                  child: Center(child: _MiniWave(color: glow)),
                ),

              // Stats
              Positioned(
                top: 4,
                right: 4,
                child: WallpaperStatsBar(
                  wallpaperId: 'tone_${tone.id}',
                  glowColor: glow,
                ),
              ),

              // Name + duration
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Text(
                        tone.name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tone.durationFormatted,
                        style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.5)),
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
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
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
              boxShadow: [BoxShadow(color: widget.color.withOpacity(0.4), blurRadius: 3)],
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
            children: List.generate(3, (i) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Shimmer.fromColors(
                baseColor: const Color(0xFF1A1A2E),
                highlightColor: const Color(0xFF2A2A3E),
                child: Container(
                  width: 90, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            )),
          ),
          const SizedBox(height: 16),
          // Hero shimmer
          Shimmer.fromColors(
            baseColor: const Color(0xFF1A1A2E),
            highlightColor: const Color(0xFF2A2A3E),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Section shimmer
          Shimmer.fromColors(
            baseColor: const Color(0xFF1A1A2E),
            highlightColor: const Color(0xFF2A2A3E),
            child: Container(
              width: 160, height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Cards shimmer row
          SizedBox(
            height: 170,
            child: Row(
              children: List.generate(3, (i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Shimmer.fromColors(
                  baseColor: const Color(0xFF1A1A2E),
                  highlightColor: const Color(0xFF2A2A3E),
                  child: Container(
                    width: 140, height: 170,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
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
