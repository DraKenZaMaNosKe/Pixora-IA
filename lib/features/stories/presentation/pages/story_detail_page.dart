import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/credit_service.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/story_rotation_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
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
  final _pageController = PageController(viewportFraction: 0.85);

  Color get _glowColor => parseHexColor(widget.story.glowColor, fallback: Colors.deepPurple);

  @override
  void initState() {
    super.initState();
    WallpaperStatsService.instance.trackView('story_${widget.story.id}');
  }

  Future<void> _startStory() async {
    // Show alternating ad (awards credits), then start
    AdService.instance.showInterstitialAd(onAdDismissed: () {
      if (mounted) _doStartStory();
    });
  }

  Future<void> _doStartStory() async {
    setState(() {
      _isStarting = true;
      _downloadProgress = 0;
    });
    WallpaperStatsService.instance.trackDownload('story_${widget.story.id}');

    // Download all frames
    final paths = <String>[];
    for (var i = 0; i < widget.story.frames.length; i++) {
      final frame = widget.story.frames[i];
      setState(() => _downloadProgress = i + 1);

      final path = await DownloadService.instance.downloadWallpaper(frame.imageFile);
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to download frame ${i + 1}')),
          );
        }
        setState(() => _isStarting = false);
        return;
      }
      paths.add(path);
    }

    // Build captions with rotating languages: es → en → ja → es...
    final captions = <String>[];
    for (var i = 0; i < widget.story.frames.length; i++) {
      captions.add(widget.story.frames[i].captionForLang(i));
    }

    // Start rotation via platform channel
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Story started! Wallpaper changes every ${widget.story.intervalMinutes} min'
              : 'Failed to start story'),
        ),
      );
    }
    setState(() => _isStarting = false);
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          // Cover image as app bar
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.black,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.story.title,
                  style: const TextStyle(fontSize: 16)),
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
                          Colors.black.withOpacity(0.8),
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
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Stats row
                  Row(
                    children: [
                      _statChip(Icons.photo_library,
                          '${widget.story.frames.length} frames'),
                      const SizedBox(width: 12),
                      _statChip(Icons.timer,
                          'Every ${widget.story.intervalMinutes} min'),
                      const SizedBox(width: 12),
                      _statChip(Icons.schedule,
                          '~${(widget.story.frames.length * widget.story.intervalMinutes / 60).toStringAsFixed(1)}h total'),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Frames preview label
                  const Text('Frames',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                            borderRadius: BorderRadius.circular(12),
                            child: CachedWallpaperImage(
                                imageUrl: frame.fullImageUrl),
                          ),
                        ),
                        if (frame.captionEs.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            frame.captionEs,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
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
                            color: glow.withOpacity(0.7),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isFree ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isFree ? Colors.greenAccent.withOpacity(0.5) : Colors.orange.withOpacity(0.5)),
                        ),
                        child: Text(
                          isFree ? 'FREE!' : '+${CreditService.creditsPerAd} credits',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isFree ? Colors.greenAccent : Colors.orangeAccent),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.diamond, size: 12, color: Color(0xFF7C4DFF)),
                      const SizedBox(width: 3),
                      Text('$credits', style: const TextStyle(fontSize: 11, color: Color(0xFF7C4DFF))),
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
                    style:
                        const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive ? Colors.red.shade800 : glow,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _glowColor),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7), fontSize: 11)),
        ],
      ),
    );
  }
}
