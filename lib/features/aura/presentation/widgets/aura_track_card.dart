import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/hud_tokens.dart';
import '../../../../core/widgets/watch_card_pieces.dart';
import '../../data/models/aura_track.dart';

/// AURA frequency / nature track — Sacred Geometry Mandala (concept #02,
/// Eduardo 2026-05-16). Each track has:
/// - A unique color tied to its energy (Gamma=ruby · Alpha=ocean · Theta=
///   amethyst · Delta=indigo · Schumann=amber · Solfeggio=chakra colors).
/// - A rotating mandala pattern picked from the track's category/id
///   (Sri Yantra, Flower of Life, Metatron's Cube, Seed of Life, etc.).
/// - Cinzel inscription title.
/// - Watch Cartouche pill (admit label) and Activity Rings stats (bottom)
///   for consistency with the rest of the app.
class AuraTrackCard extends StatefulWidget {
  final AuraTrack track;
  final bool isPlaying;
  final VoidCallback onTap;

  const AuraTrackCard({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  State<AuraTrackCard> createState() => _AuraTrackCardState();
}

class _AuraTrackCardState extends State<AuraTrackCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    // Slow ritual rotation — 60s per full turn for tracks at rest, 24s when
    // playing (gentler than spinny but enough to feel alive).
    _rotation = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.isPlaying ? 24 : 60),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant AuraTrackCard old) {
    super.didUpdateWidget(old);
    if (old.isPlaying != widget.isPlaying) {
      _rotation.duration = Duration(seconds: widget.isPlaying ? 24 : 60);
      _rotation
        ..stop()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  String _brainwaveLabel(String id) {
    switch (id) {
      case 'brainwave_delta':
        return 'DELTA';
      case 'brainwave_theta':
        return 'THETA';
      case 'brainwave_schumann':
        return 'SCHUMANN';
      case 'brainwave_alpha':
        return 'ALPHA';
      case 'brainwave_gamma':
        return 'GAMMA';
      default:
        return id.replaceFirst('brainwave_', '').toUpperCase();
    }
  }

  /// Unique color per track type. Each frequency carries its own energy —
  /// gamma awakens (ruby), alpha calms (ocean), theta opens (amethyst),
  /// delta restores (indigo), schumann grounds (amber). Solfeggio frequencies
  /// follow the chakra rainbow (root→crown). Nature/noise tracks get their
  /// elemental color.
  Color get _auraColor {
    final id = widget.track.id;
    // Brainwaves
    if (id == 'brainwave_gamma') return const Color(0xFFE63946); // ruby
    if (id == 'brainwave_alpha') return const Color(0xFF00A8E8); // ocean
    if (id == 'brainwave_theta') return const Color(0xFF9B5DE5); // amethyst
    if (id == 'brainwave_delta') return const Color(0xFF3A0CA3); // indigo
    if (id == 'brainwave_schumann') return const Color(0xFFE76F51); // amber
    // Solfeggio — chakra colors
    final hz = widget.track.hz ?? 0;
    if (hz == 396) return const Color(0xFFC1272D); // root red
    if (hz == 417) return const Color(0xFFFF7F11); // sacral orange
    if (hz == 528) return const Color(0xFFFFD23F); // solar plexus gold (love)
    if (hz == 639) return const Color(0xFF52B788); // heart emerald (no mint!)
    if (hz == 741) return const Color(0xFF118AB2); // throat blue
    if (hz == 852) return const Color(0xFF6A4C93); // third-eye indigo
    if (hz == 963) return const Color(0xFFBF5AF2); // crown violet
    // Nature
    switch (widget.track.icon) {
      case 'rain':
        return const Color(0xFF4361EE);
      case 'storm':
      case 'lightning':
        return const Color(0xFF7B2CBF);
      case 'wave':
      case 'river':
      case 'waterfall':
        return const Color(0xFF00A8E8);
      case 'fire':
        return const Color(0xFFE76F51);
      case 'forest':
        return const Color(0xFF52B788);
      case 'wind':
        return const Color(0xFFB8C5D6);
      case 'moon':
        return const Color(0xFF6A4C93);
      case 'coffee':
        return const Color(0xFFB08968);
      case 'bowl':
        return const Color(0xFFFFD23F);
      case 'bell':
        return const Color(0xFFFFB4A2);
      case 'static':
        return const Color(0xFFE0AAFF);
      default:
        return const Color(0xFFFFD23F); // default warm gold (noise / unknown)
    }
  }

  /// Which mandala pattern to draw, based on the track type.
  _MandalaPattern get _pattern {
    final id = widget.track.id;
    if (id == 'brainwave_gamma') return _MandalaPattern.sriYantra;
    if (id == 'brainwave_alpha') return _MandalaPattern.flowerOfLife;
    if (id == 'brainwave_theta') return _MandalaPattern.metatronCube;
    if (id == 'brainwave_delta') return _MandalaPattern.vesicaPiscis;
    if (id == 'brainwave_schumann') return _MandalaPattern.seedOfLife;
    if (widget.track.category == AuraCategory.frequency) {
      // Solfeggio frequencies get a sun mandala (always)
      return _MandalaPattern.sunMandala;
    }
    if (widget.track.id.startsWith('noise_')) {
      return _MandalaPattern.ripple;
    }
    // Nature — eight-pointed star
    return _MandalaPattern.eightStar;
  }

  String _bottomLabel(bool isFreq, bool isBrainwave, bool isNoise) {
    if (isBrainwave) return 'binaural';
    if (isNoise) return 'ambient noise';
    if (isFreq && widget.track.hz != null) return 'solfeggio';
    return 'nature';
  }

  String _admitLabel(bool isFreq, bool isBrainwave, bool isNoise) {
    if (widget.isPlaying) return 'NOW PLAYING';
    if (isBrainwave) return 'BINAURAL';
    if (isNoise) return 'AMBIENT';
    if (isFreq) return 'FREQUENCY';
    return 'NATURE';
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    final isFreq = widget.track.category == AuraCategory.frequency;
    final isBrainwave = widget.track.id.startsWith('brainwave_');
    final isNoise = widget.track.id.startsWith('noise_');
    final color = _auraColor;

    final surfaceBg = isIos
        ? Colors.white
        : const Color(0xFF0F0F18); // slightly lifted from pure ink
    final borderColor = widget.isPlaying
        ? color.withValues(alpha: 0.65)
        : (isIos
            ? Colors.black.withValues(alpha: 0.06)
            : color.withValues(alpha: 0.18));
    final titleColor = isIos ? const Color(0xFF1C1C1E) : color;

    return GestureDetector(
      onTap: widget.onTap,
      child: AspectRatio(
        aspectRatio: 0.82,
        child: Container(
          decoration: BoxDecoration(
            color: surfaceBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: widget.isPlaying ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(
                    alpha: widget.isPlaying ? 0.25 : (isIos ? 0.08 : 0.18)),
                blurRadius: widget.isPlaying ? 22 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Radial color glow background
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.95,
                    colors: [
                      color.withValues(alpha: widget.isPlaying ? 0.18 : 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              // Rotating mandala behind the text
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _rotation,
                    builder: (_, __) {
                      return Transform.rotate(
                        angle: _rotation.value * 2 * math.pi,
                        child: CustomPaint(
                          painter: _MandalaPainter(
                            pattern: _pattern,
                            color: color,
                            opacity: isIos ? 0.20 : 0.32,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Top-left: admit label (Watch Cartouche pill)
              Positioned(
                top: 8,
                left: 8,
                child: WatchCartouchePill(
                  label: _admitLabel(isFreq, isBrainwave, isNoise),
                ),
              ),
              // Center text — Cinzel inscription
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 30, 10, 50),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isBrainwave
                            ? _brainwaveLabel(widget.track.id)
                            : isNoise
                                ? widget.track.id
                                    .replaceFirst('noise_', '')
                                    .toUpperCase()
                                : (isFreq && widget.track.hz != null)
                                    ? '${widget.track.hz}'
                                    : widget.track.displayName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cinzel(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                          letterSpacing: 1.4,
                          height: 1.0,
                          shadows: [
                            Shadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isFreq && widget.track.hz != null
                            ? 'Hz · ${_bottomLabel(isFreq, isBrainwave, isNoise)}'
                            : _bottomLabel(isFreq, isBrainwave, isNoise),
                        style: GoogleFonts.cormorantGaramond(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                          color: color,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Bottom-centered Activity Rings (social proof épico)
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Center(
                  child: ActivityRings(
                    wallpaperId: 'aura_${widget.track.id}',
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

// ═════════════════════════════════════════════════════════════════════
// Sacred geometry mandala painter
// ═════════════════════════════════════════════════════════════════════
enum _MandalaPattern {
  sriYantra,
  flowerOfLife,
  metatronCube,
  vesicaPiscis,
  seedOfLife,
  sunMandala,
  eightStar,
  ripple,
}

class _MandalaPainter extends CustomPainter {
  _MandalaPainter({
    required this.pattern,
    required this.color,
    required this.opacity,
  });
  final _MandalaPattern pattern;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) / 2 * 0.85;
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    switch (pattern) {
      case _MandalaPattern.flowerOfLife:
        _drawFlowerOfLife(canvas, center, maxR, paint);
        break;
      case _MandalaPattern.seedOfLife:
        _drawSeedOfLife(canvas, center, maxR, paint);
        break;
      case _MandalaPattern.metatronCube:
        _drawMetatron(canvas, center, maxR, paint);
        break;
      case _MandalaPattern.sriYantra:
        _drawSriYantra(canvas, center, maxR, paint);
        break;
      case _MandalaPattern.vesicaPiscis:
        _drawVesicaPiscis(canvas, center, maxR, paint);
        break;
      case _MandalaPattern.sunMandala:
        _drawSunMandala(canvas, center, maxR, paint);
        break;
      case _MandalaPattern.eightStar:
        _drawEightStar(canvas, center, maxR, paint);
        break;
      case _MandalaPattern.ripple:
        _drawRipple(canvas, center, maxR, paint);
        break;
    }
  }

  void _drawFlowerOfLife(Canvas c, Offset ctr, double r, Paint p) {
    final petalR = r * 0.35;
    c.drawCircle(ctr, petalR, p);
    for (var i = 0; i < 6; i++) {
      final a = (i * math.pi / 3);
      c.drawCircle(
          ctr.translate(petalR * math.cos(a), petalR * math.sin(a)), petalR, p);
    }
    // outer ring
    for (var i = 0; i < 12; i++) {
      final a = (i * math.pi / 6);
      c.drawCircle(
          ctr.translate(
              petalR * 1.732 * math.cos(a), petalR * 1.732 * math.sin(a)),
          petalR,
          p);
    }
    c.drawCircle(ctr, r, p);
  }

  void _drawSeedOfLife(Canvas c, Offset ctr, double r, Paint p) {
    final petalR = r * 0.40;
    c.drawCircle(ctr, petalR, p);
    for (var i = 0; i < 6; i++) {
      final a = (i * math.pi / 3);
      c.drawCircle(
          ctr.translate(petalR * math.cos(a), petalR * math.sin(a)), petalR, p);
    }
    c.drawCircle(ctr, r, p);
  }

  void _drawMetatron(Canvas c, Offset ctr, double r, Paint p) {
    final pts = <Offset>[];
    // 13 circles in Metatron's Cube arrangement
    pts.add(ctr);
    for (var i = 0; i < 6; i++) {
      final a = (i * math.pi / 3);
      pts.add(ctr.translate(r * 0.40 * math.cos(a), r * 0.40 * math.sin(a)));
    }
    for (var i = 0; i < 6; i++) {
      final a = (i * math.pi / 3) + math.pi / 6;
      pts.add(ctr.translate(r * 0.75 * math.cos(a), r * 0.75 * math.sin(a)));
    }
    for (final pt in pts) {
      c.drawCircle(pt, 2.5, p);
    }
    // Connect lines
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        c.drawLine(
            pts[i], pts[j], p..color = color.withValues(alpha: opacity * 0.45));
      }
    }
    p.color = color.withValues(alpha: opacity);
  }

  void _drawSriYantra(Canvas c, Offset ctr, double r, Paint p) {
    // Stylized: 9 interlocking triangles (4 up, 5 down)
    for (var i = 0; i < 9; i++) {
      final scale = 1.0 - (i * 0.08);
      final tri = Path();
      final pointingUp = i % 2 == 0;
      for (var j = 0; j < 3; j++) {
        final a =
            j * 2 * math.pi / 3 + (pointingUp ? -math.pi / 2 : math.pi / 2);
        final pt =
            ctr.translate(r * scale * math.cos(a), r * scale * math.sin(a));
        if (j == 0) {
          tri.moveTo(pt.dx, pt.dy);
        } else {
          tri.lineTo(pt.dx, pt.dy);
        }
      }
      tri.close();
      c.drawPath(tri, p);
    }
    c.drawCircle(ctr, r, p);
  }

  void _drawVesicaPiscis(Canvas c, Offset ctr, double r, Paint p) {
    final pr = r * 0.6;
    final offset = pr / 2;
    c.drawCircle(ctr.translate(-offset, 0), pr, p);
    c.drawCircle(ctr.translate(offset, 0), pr, p);
    c.drawCircle(ctr.translate(0, -offset), pr, p);
    c.drawCircle(ctr.translate(0, offset), pr, p);
    c.drawCircle(ctr, r, p);
  }

  void _drawSunMandala(Canvas c, Offset ctr, double r, Paint p) {
    // 12 rays + concentric circles
    c.drawCircle(ctr, r * 0.30, p);
    c.drawCircle(ctr, r * 0.55, p);
    c.drawCircle(ctr, r, p);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      c.drawLine(
        ctr.translate(r * 0.55 * math.cos(a), r * 0.55 * math.sin(a)),
        ctr.translate(r * math.cos(a), r * math.sin(a)),
        p,
      );
    }
    // Inner 6-petal flower
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      c.drawCircle(
          ctr.translate(r * 0.15 * math.cos(a), r * 0.15 * math.sin(a)),
          r * 0.15,
          p);
    }
  }

  void _drawEightStar(Canvas c, Offset ctr, double r, Paint p) {
    // Two overlapping squares rotated 45°
    final sq1 = Path();
    final sq2 = Path();
    for (var i = 0; i < 4; i++) {
      final a1 = i * math.pi / 2;
      final a2 = a1 + math.pi / 4;
      final pt1 = ctr.translate(r * math.cos(a1), r * math.sin(a1));
      final pt2 = ctr.translate(r * math.cos(a2), r * math.sin(a2));
      if (i == 0) {
        sq1.moveTo(pt1.dx, pt1.dy);
        sq2.moveTo(pt2.dx, pt2.dy);
      } else {
        sq1.lineTo(pt1.dx, pt1.dy);
        sq2.lineTo(pt2.dx, pt2.dy);
      }
    }
    sq1.close();
    sq2.close();
    c.drawPath(sq1, p);
    c.drawPath(sq2, p);
    c.drawCircle(ctr, r * 0.30, p);
  }

  void _drawRipple(Canvas c, Offset ctr, double r, Paint p) {
    for (var i = 1; i <= 6; i++) {
      c.drawCircle(ctr, r * (i / 6), p);
    }
  }

  @override
  bool shouldRepaint(covariant _MandalaPainter old) =>
      old.color != color || old.pattern != pattern || old.opacity != opacity;
}
