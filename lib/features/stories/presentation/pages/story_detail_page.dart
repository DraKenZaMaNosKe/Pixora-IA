import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/content/content_manager.dart';
import '../../../../core/content/content_types.dart';
import '../../../../core/content/content_url_resolver.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/credit_service.dart';
import '../../../../core/services/story_rotation_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../data/models/story.dart';
import '../../providers/story_providers.dart';

/// Story Detail — Marvel Splash Page aesthetic.
///
/// Picked 2026-05-16 by Eduardo to match the comic-book panel identity of
/// the story LIST cards (brass borders, action labels, burst stamps).
/// Always-dark cinematic bg; full-bleed cover at top; "CAP. N" red burst
/// stamp; black diagonal banner with the title in Bowlby One; yellow
/// narrator caption box for the description; 3 white stat cards; 2×N
/// brass-bordered panels grid for the frames; red Bangers CTA at the
/// bottom. Generic — works for any story regardless of genre.
class StoryDetailPage extends ConsumerStatefulWidget {
  const StoryDetailPage({required this.story, super.key});
  final Story story;

  @override
  ConsumerState<StoryDetailPage> createState() => _StoryDetailPageState();
}

class _StoryDetailPageState extends ConsumerState<StoryDetailPage>
    with TickerProviderStateMixin {
  static const _bg = Color(0xFF0A0A0A);
  static const _brass = Color(0xFFD4AF37);
  static const _burstRed = Color(0xFFDC2626);
  static const _burstYellow = Color(0xFFFCD34D);
  static const _panelBg = Color(0xFF1A1212);
  static const _captionBg = Color(0xFFFCD34D);
  static const _captionInk = Color(0xFF1A0F00);

  bool _isStarting = false;
  int _downloadProgress = 0;
  double _downloadFraction = 0.0;
  String _loadingStatus = '';
  LoadingPhase _loadingPhase = LoadingPhase.downloading;

  late final AnimationController _wobbleCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _wobbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    WallpaperStatsService.instance.trackView('story_${widget.story.id}');
  }

  @override
  void dispose() {
    _wobbleCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _startStory() async {
    AdService.instance.showInterstitialAd(
      placement: 'story_apply',
      onAdDismissed: () {
        if (mounted) _doStartStory();
      },
    );
  }

  Future<void> _doStartStory() async {
    final total = widget.story.frames.length;
    setState(() {
      _isStarting = true;
      _downloadProgress = 0;
      _downloadFraction = 0.0;
      _loadingStatus = 'Downloading frame 1/$total...';
      _loadingPhase = LoadingPhase.downloading;
    });
    WallpaperStatsService.instance.trackDownload('story_${widget.story.id}');

    final paths = <String>[];
    for (var i = 0; i < total; i++) {
      final frame = widget.story.frames[i];
      if (mounted) {
        setState(() {
          _downloadProgress = i + 1;
          _downloadFraction = (i + 1) / total;
          _loadingStatus = 'Downloading frame ${i + 1}/$total...';
        });
      }
      final item = ContentItem(
        id: '${widget.story.id}_frame_$i',
        type: ContentType.staticWallpaper,
        remoteFile: frame.imageFile,
        bucket: ContentUrlResolver.wallpaperImagesBucket,
      );
      final path = await ContentManager.instance.download(item);
      if (path == null) {
        if (mounted) {
          setState(() {
            _loadingPhase = LoadingPhase.error;
            _loadingStatus = 'Failed to download frame ${i + 1}';
          });
          await Future.delayed(const Duration(milliseconds: 1500));
          setState(() => _isStarting = false);
        }
        return;
      }
      paths.add(path);
    }

    if (mounted) {
      setState(() {
        _loadingPhase = LoadingPhase.installing;
        _loadingStatus = 'Activating story rotation...';
        _downloadFraction = 0.0;
      });
    }
    final captions = <String>[];
    for (var i = 0; i < total; i++) {
      captions.add(widget.story.frames[i].captionForLang(i));
    }
    final success = await StoryRotationService.instance.startStory(
      storyId: widget.story.id,
      imagePaths: paths,
      captions: captions,
      glowColor: widget.story.glowColor,
      intervalMinutes: widget.story.intervalMinutes,
    );
    if (success) {
      WallpaperStatsService.instance.trackInstall('story_${widget.story.id}');
    }
    if (mounted) {
      ref.read(activeStoryIdProvider.notifier).state =
          success ? widget.story.id : null;
      setState(() {
        _loadingPhase = success ? LoadingPhase.done : LoadingPhase.error;
        _loadingStatus = success ? 'Story started!' : 'Failed to start story';
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      setState(() => _isStarting = false);
    }
  }

  Future<void> _stopStory() async {
    await StoryRotationService.instance.stopStory();
    ref.read(activeStoryIdProvider.notifier).state = null;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Story stopped')),
      );
    }
  }

  // Pulls "Cap. N" from the story title if present, else falls back to "ED".
  String get _chapterLabel {
    final match = RegExp(r'Cap\.?\s*(\d+)', caseSensitive: false)
        .firstMatch(widget.story.title);
    if (match != null) return 'CAP. ${match.group(1)!.padLeft(2, '0')}';
    return 'EDITION';
  }

  // Strips "- Cap. N" from the title for cleaner display in the banner.
  String get _titleClean =>
      widget.story.title.replaceAll(RegExp(r'\s*-?\s*Cap\.?\s*\d+'), '').trim();

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final isActive = ref.watch(activeStoryIdProvider) == story.id;
    final totalHours = (story.frames.length * story.intervalMinutes / 60);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _heroSplash()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (story.description.isNotEmpty) _narratorCaption(),
                    const SizedBox(height: 16),
                    _statsRow(totalHours),
                    const SizedBox(height: 22),
                    _panelsHeader(),
                    const SizedBox(height: 12),
                    _panelsGrid(),
                    const SizedBox(height: 120),
                  ]),
                ),
              ),
            ],
          ),
          // Bottom CTA pinned
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottomCta(isActive),
          ),
          LoadingOverlay(
            visible: _isStarting,
            progress: _downloadFraction > 0 ? _downloadFraction : null,
            status: _loadingStatus,
            accentColor: _burstRed,
            phase: _loadingPhase,
          ),
        ],
      ),
    );
  }

  // ── Hero splash — full-bleed cover + burst stamp + diagonal title ──
  Widget _heroSplash() {
    return SizedBox(
      height: 340,
      child: Stack(
        children: [
          // Cover image
          Positioned.fill(
            child: CachedWallpaperImage(imageUrl: widget.story.coverImageUrl),
          ),
          // Dark gradient bottom-to-top so the banner reads
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.55),
                    _bg,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // CAP. N red burst stamp top-left, wobbling
          Positioned(
            top: 56,
            left: 18,
            child: AnimatedBuilder(
              animation: _wobbleCtrl,
              builder: (_, child) {
                final t = (_wobbleCtrl.value - 0.5) * 0.08; // ±0.04 rad
                return Transform.rotate(angle: t, child: child);
              },
              child: _burstStamp(_chapterLabel),
            ),
          ),
          // Close (X) top-right
          Positioned(
            top: 50,
            right: 14,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 22),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          // Diagonal black banner with title (Bowlby One)
          Positioned(
            left: 0,
            right: 0,
            bottom: 30,
            child: Transform.rotate(
              angle: -0.035,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                color: Colors.black,
                child: Text(
                  _titleClean.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bowlbyOne(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1.05,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
          // "Una historia en N partes" yellow caption below banner
          Positioned(
            left: 22,
            bottom: 6,
            child: Text(
              'UNA HISTORIA EN ${widget.story.frames.length} PARTES',
              style: GoogleFonts.jetBrainsMono(
                color: _burstYellow,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _burstStamp(String label) {
    return CustomPaint(
      painter: _StarBurstPainter(fill: _burstRed),
      child: SizedBox(
        width: 76,
        height: 76,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.bangers(
                color: Colors.white,
                fontSize: 16,
                height: 1.05,
                letterSpacing: 1.2,
                shadows: const [
                  Shadow(color: Color(0xFF7A0F0F), offset: Offset(1, 1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Narrator caption — yellow box with black border, italic serif body ──
  Widget _narratorCaption() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _captionBg,
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            offset: const Offset(3, 3),
          ),
        ],
      ),
      child: Text(
        widget.story.description,
        style: GoogleFonts.cormorantGaramond(
          color: _captionInk,
          fontSize: 15,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }

  // ── 3 stat cards — white boxes with mono labels ───────────────────
  Widget _statsRow(double totalHours) {
    return Row(
      children: [
        Expanded(child: _statCard('${widget.story.frames.length}', 'FRAMES')),
        const SizedBox(width: 8),
        Expanded(
            child: _statCard('${widget.story.intervalMinutes}M', 'INTERVALO')),
        const SizedBox(width: 8),
        Expanded(
            child: _statCard('${totalHours.toStringAsFixed(1)}H', 'TOTAL')),
      ],
    );
  }

  Widget _statCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.bangers(
                color: Colors.black,
                fontSize: 24,
                letterSpacing: 0.5,
                height: 1.0,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.jetBrainsMono(
                color: Colors.black87,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
              )),
        ],
      ),
    );
  }

  // ── Panels header (red bold) ──────────────────────────────────────
  Widget _panelsHeader() {
    return Row(
      children: [
        Container(width: 14, height: 14, color: _burstRed),
        const SizedBox(width: 8),
        Text('PANELS',
            style: GoogleFonts.bangers(
              color: Colors.white,
              fontSize: 22,
              letterSpacing: 1.2,
            )),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 2,
            color: _brass.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  // ── 2-col grid of frames with brass borders + chapter stamps ──────
  Widget _panelsGrid() {
    final frames = widget.story.frames;
    final isFree = AdService.instance.isNextActionFree;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: frames.length,
      itemBuilder: (ctx, i) {
        final frame = frames[i];
        final stampLabel = 'CAP-${(i + 1).toString().padLeft(2, '0')}';
        // FREE! sticker only on the second panel — like the mockup
        final showFreeSticker = isFree && i == 1;
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: _panelBg,
                border: Border.all(color: _brass, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    offset: const Offset(3, 3),
                  ),
                ],
              ),
              child: ClipRect(
                child: CachedWallpaperImage(imageUrl: frame.fullImageUrl),
              ),
            ),
            // CAP-N stamp top-right
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _burstRed,
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: Text(
                  stampLabel,
                  style: GoogleFonts.bangers(
                    color: Colors.white,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            if (showFreeSticker)
              Positioned(
                bottom: 8,
                right: 8,
                child: Transform.rotate(
                  angle: -0.14,
                  child: CustomPaint(
                    painter: _StarBurstPainter(fill: _burstYellow),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Center(
                        child: Text('FREE!',
                            style: GoogleFonts.bangers(
                              color: Colors.black,
                              fontSize: 14,
                              letterSpacing: 1,
                            )),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Bottom CTA — red Bangers comic button with credits chip ───────
  Widget _bottomCta(bool isActive) {
    final isFree = AdService.instance.isNextActionFree;
    final credits = CreditService.instance.balance;
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(
          top: BorderSide(color: _brass, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isActive && !_isStarting) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isFree ? _burstYellow : _burstRed,
                      border: Border.all(color: Colors.black, width: 1.2),
                    ),
                    child: Text(
                      isFree
                          ? 'FREE!'
                          : '+${CreditService.creditsPerAd} CREDITS',
                      style: GoogleFonts.bangers(
                        color: isFree ? Colors.black : Colors.white,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.diamond, size: 13, color: _brass),
                  const SizedBox(width: 4),
                  Text('$credits',
                      style: GoogleFonts.jetBrainsMono(
                        color: _brass,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
              const SizedBox(height: 10),
            ],
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) {
                final scale = isActive || _isStarting
                    ? 1.0
                    : 1.0 + (_pulseCtrl.value * 0.025);
                return Transform.scale(
                  scale: scale,
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isStarting
                          ? null
                          : isActive
                              ? _stopStory
                              : _startStory,
                      icon: _isStarting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              isActive ? Icons.stop : Icons.play_arrow_rounded,
                              size: 28,
                            ),
                      label: Text(
                        _isStarting
                            ? 'DOWNLOADING $_downloadProgress/${widget.story.frames.length}'
                            : isActive
                                ? 'STOP STORY'
                                : 'START STORY',
                        style: GoogleFonts.bangers(
                          fontSize: 20,
                          letterSpacing: 1.8,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isActive ? Colors.black : _burstRed,
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.black, width: 1.5),
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero),
                        elevation: 0,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Star-burst polygon — used for stamps and stickers (Marvel/comic style).
class _StarBurstPainter extends CustomPainter {
  final Color fill;
  _StarBurstPainter({required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rOuter = size.width / 2;
    final rInner = rOuter * 0.68;
    const points = 10;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? rOuter : rInner;
      final angle = (i / (points * 2)) * 2 * math.pi - math.pi / 2;
      final x = c.dx + r * math.cos(angle);
      final y = c.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    // Black border for the comic punch
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(covariant _StarBurstPainter old) => old.fill != fill;
}
