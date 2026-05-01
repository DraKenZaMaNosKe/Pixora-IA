import 'package:flutter/material.dart';
import '../../../../core/design/hud_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class StoryDetailPage extends ConsumerStatefulWidget {
  const StoryDetailPage({required this.story, super.key});
  final Story story;

  @override
  ConsumerState<StoryDetailPage> createState() => _StoryDetailPageState();
}

class _StoryDetailPageState extends ConsumerState<StoryDetailPage> {
  bool _isStarting = false;
  int _downloadProgress = 0;
  double _downloadFraction = 0.0;
  String _loadingStatus = '';
  LoadingPhase _loadingPhase = LoadingPhase.downloading;
  final _pageController = PageController(viewportFraction: 0.85);

  Color get _glowColor =>
      context.hud.accent; // Was: parseHexColor(glowColor, fallback: deepPurple)

  @override
  void initState() {
    super.initState();
    WallpaperStatsService.instance.trackView('story_${widget.story.id}');
  }

  Future<void> _startStory() async {
    // Show alternating ad (awards credits), then start
    AdService.instance.showInterstitialAd(placement: 'story_apply', onAdDismissed: () {
      if (mounted) _doStartStory();
    });
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

    // Download all frames
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

    // Build captions
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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = ref.watch(activeStoryIdProvider) == widget.story.id;
    final glow = _glowColor;
    final h = context.hud;
    final isIos = h.isIosStyle;

    return Scaffold(
      backgroundColor: h.bg,
      body: Stack(children: [
        CustomScrollView(
          slivers: [
            // Cover image as app bar
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              backgroundColor: h.bg,
              foregroundColor: isIos ? h.text : Colors.white,
              iconTheme: IconThemeData(color: isIos ? h.text : Colors.white),
              flexibleSpace: FlexibleSpaceBar(
                title: Text(widget.story.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isIos ? h.text : Colors.white,
                    )),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedWallpaperImage(imageUrl: widget.story.coverImageUrl),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            h.bg.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Story info
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description
                    if (widget.story.description.isNotEmpty)
                      Text(
                        widget.story.description,
                        style: TextStyle(
                          color: h.textDim,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Stats row — Wrap so chips reflow instead of overflowing
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statChip(Icons.photo_library,
                            '${widget.story.frames.length} frames'),
                        _statChip(Icons.timer,
                            'Every ${widget.story.intervalMinutes} min'),
                        _statChip(Icons.schedule,
                            '~${(widget.story.frames.length * widget.story.intervalMinutes / 60).toStringAsFixed(1)}h total'),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Frames preview label
                    Text('Frames',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: h.text)),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // Frames horizontal pager
            SliverToBoxAdapter(
              child: SizedBox(
                height: 400,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.story.frames.length,
                  itemBuilder: (context, index) {
                    final frame = widget.story.frames[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(isIos ? 16 : 12),
                              child: Container(
                                decoration: isIos
                                    ? BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withValues(alpha: 0.08),
                                            blurRadius: 14,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      )
                                    : null,
                                child: CachedWallpaperImage(
                                    imageUrl: frame.fullImageUrl),
                              ),
                            ),
                          ),
                          if (frame.captionEs.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              frame.captionEs,
                              style: TextStyle(
                                color: h.textDim,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            '${index + 1} / ${widget.story.frames.length}',
                            style: TextStyle(
                              color: glow,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // Bottom spacing
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
        LoadingOverlay(
          visible: _isStarting,
          progress: _downloadFraction > 0 ? _downloadFraction : null,
          status: _loadingStatus,
          accentColor: glow,
          phase: _loadingPhase,
        ),
      ]),

      // Start/Stop button + ad badge
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isActive && !_isStarting) ...[
                Builder(builder: (_) {
                  final isFree = AdService.instance.isNextActionFree;
                  final credits = CreditService.instance.balance;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isFree
                              ? context.hud.accent.withValues(alpha: 0.2)
                              : context.hud.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: isFree
                                  ? context.hud.accent.withValues(alpha: 0.5)
                                  : context.hud.accent.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          isFree
                              ? 'FREE!'
                              : '+${CreditService.creditsPerAd} credits',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isFree
                                  ? context.hud.accent
                                  : context.hud.accent),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.diamond, size: 12, color: context.hud.accent),
                      const SizedBox(width: 3),
                      Text('$credits',
                          style: TextStyle(
                              fontSize: 11, color: context.hud.accent)),
                    ],
                  );
                }),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isStarting
                      ? null
                      : isActive
                          ? _stopStory
                          : _startStory,
                  icon: _isStarting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: glow),
                        )
                      : Icon(isActive ? Icons.stop : Icons.play_arrow),
                  label: Text(
                    _isStarting
                        ? 'Downloading frame $_downloadProgress/${widget.story.frames.length}...'
                        : isActive
                            ? 'Stop Story'
                            : 'Start Story',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive
                        ? (isIos ? const Color(0xFFFF3B30) : HudTokens.goldDeep)
                        : glow,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isIos ? 12 : 10, vertical: isIos ? 7 : 6),
      decoration: BoxDecoration(
        color: isIos ? h.surface : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: isIos ? Border.all(color: h.divider, width: 0.5) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _glowColor),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: isIos ? h.text : Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: isIos ? FontWeight.w500 : FontWeight.normal)),
        ],
      ),
    );
  }
}
