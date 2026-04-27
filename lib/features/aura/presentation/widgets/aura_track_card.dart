import 'package:flutter/material.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/widgets/ticket_stub_card.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
import '../../data/models/aura_track.dart';

/// AURA frequency / nature track rendered as a Ticket Stub.
/// Keeps the icon + Hz / nature glyph as the "art" inside the image panel.
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

  IconData get _natureIcon {
    switch (track.icon) {
      case 'rain':
        return Icons.grain;
      case 'storm':
        return Icons.thunderstorm;
      case 'wave':
        return Icons.waves;
      case 'river':
        return Icons.water;
      case 'waterfall':
        return Icons.water_drop;
      case 'fire':
        return Icons.local_fire_department;
      case 'forest':
        return Icons.forest;
      case 'wind':
        return Icons.air;
      case 'lightning':
        return Icons.flash_on;
      case 'moon':
        return Icons.nightlight_round;
      case 'coffee':
        return Icons.local_cafe;
      case 'static':
        return Icons.graphic_eq;
      case 'bowl':
        return Icons.spa;
      case 'bell':
        return Icons.notifications_none;
      default:
        return Icons.music_note;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFreq = track.category == AuraCategory.frequency;
    final admitLabel = isPlaying
        ? 'NOW PLAYING'
        : isFreq
            ? 'FREQUENCY'
            : 'NATURE';

    return TicketStubCard(
      admitLabel: admitLabel,
      title: track.displayName,
      category: isFreq ? '${track.hz} HZ · SOLFEGGIO' : 'AMBIENT · NATURE',
      isHighlighted: isPlaying,
      onTap: onTap,
      overlayTopRight: WallpaperStatsBar(
        wallpaperId: 'aura_${track.id}',
        glowColor: context.hud.accent,
      ),
      child: Container(
        color: context.hud.surfaceHi,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Ambient radial gold glow behind the icon.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    context.hud.accent.withOpacity(isPlaying ? 0.4 : 0.18),
                    Colors.transparent,
                  ],
                  radius: 0.75,
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFreq ? Icons.graphic_eq : _natureIcon,
                    size: 44,
                    color: context.hud.accent,
                  ),
                  if (isFreq) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${track.hz}',
                      style: HudTokens.display(
                        size: 28,
                        weight: FontWeight.w900,
                        color: context.hud.text,
                        letterSpacing: -0.02,
                      ),
                    ),
                    Text(
                      'Hz',
                      style: HudTokens.serif(
                        size: 13,
                        color: context.hud.accent,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
