import 'package:flutter/material.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
import '../../data/models/aura_track.dart';

class AuraTrackCard extends StatelessWidget {
  final AuraTrack track;
  final bool isPlaying;
  final VoidCallback onTap;

  const AuraTrackCard({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.onTap,
  });

  Color get _accent {
    if (track.colorHex != null) {
      return parseHexColor(track.colorHex!, fallback: const Color(0xFF7C4DFF));
    }
    return const Color(0xFF7C4DFF);
  }

  IconData get _natureIcon {
    switch (track.icon) {
      case 'rain':       return Icons.grain;
      case 'storm':      return Icons.thunderstorm;
      case 'wave':       return Icons.waves;
      case 'river':      return Icons.water;
      case 'waterfall':  return Icons.water_drop;
      case 'fire':       return Icons.local_fire_department;
      case 'forest':     return Icons.forest;
      case 'wind':       return Icons.air;
      case 'lightning':  return Icons.flash_on;
      case 'moon':       return Icons.nightlight_round;
      case 'coffee':     return Icons.local_cafe;
      case 'static':     return Icons.graphic_eq;
      case 'bowl':       return Icons.spa;
      case 'bell':       return Icons.notifications_none;
      default:           return Icons.music_note;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFreq = track.category == AuraCategory.frequency;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _accent.withOpacity(0.45),
              _accent.withOpacity(0.10),
            ],
          ),
          border: Border.all(
            color: isPlaying ? _accent : Colors.white.withOpacity(0.08),
            width: isPlaying ? 2 : 1,
          ),
          boxShadow: isPlaying
              ? [BoxShadow(color: _accent.withOpacity(0.5), blurRadius: 18, spreadRadius: 1)]
              : [BoxShadow(color: _accent.withOpacity(0.12), blurRadius: 8)],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 8, right: 8,
              child: WallpaperStatsBar(
                wallpaperId: 'aura_${track.id}',
                glowColor: _accent,
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFreq ? Icons.graphic_eq : _natureIcon,
                    size: 38,
                    color: Colors.white.withOpacity(0.95),
                  ),
                  if (isFreq) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${track.hz} Hz',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 10, right: 10, bottom: 10,
              child: Text(
                track.displayName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isPlaying)
              Positioned(
                top: 8, left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow, size: 11, color: Colors.white),
                      SizedBox(width: 2),
                      Text('NOW',
                        style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
