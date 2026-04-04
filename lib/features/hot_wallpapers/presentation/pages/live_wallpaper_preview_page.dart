import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/credit_service.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../data/models/live_wallpaper.dart';

class LiveWallpaperPreviewPage extends StatefulWidget {
  final LiveWallpaper wallpaper;
  const LiveWallpaperPreviewPage({super.key, required this.wallpaper});

  @override
  State<LiveWallpaperPreviewPage> createState() =>
      _LiveWallpaperPreviewPageState();
}

class _LiveWallpaperPreviewPageState extends State<LiveWallpaperPreviewPage> {
  VideoPlayerController? _videoController;
  bool _isVideoReady = false;
  bool _isApplying = false;
  double _downloadProgress = 0.0;
  String _loadingStatus = '';
  bool _showControls = true;
  bool _interactiveMode = false; // false = Auto Play, true = Touch scrub
  late Future<bool> _isDownloadedFuture;
  // Token to cancel stale auto-hide callbacks
  int _controlsToken = 0;

  Color get _glowColor => parseHexColor(widget.wallpaper.glowColor, fallback: const Color(0xFFFF4500));

  @override
  void initState() {
    super.initState();
    _isDownloadedFuture = _isDownloaded();
    WallpaperStatsService.instance.trackView('live_${widget.wallpaper.id}');
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.wallpaper.videoUrl),
      );
      await _videoController!.initialize();
      _videoController!.setLooping(true);
      _videoController!.setVolume(0); // Mute for wallpaper preview
      if (mounted) {
        setState(() => _isVideoReady = true);
        _videoController!.play();
        _scheduleAutoHide();
      }
    } catch (e) {
      // Dispose controller on init failure to prevent leak
      _videoController?.dispose();
      _videoController = null;
      debugPrint('[Pixora] Video init failed: $e');
    }
  }

  void _scheduleAutoHide() {
    final token = ++_controlsToken;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _controlsToken == token) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _controlsToken++; // Invalidate any pending auto-hide
    _videoController?.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleAutoHide();
    }
  }

  Future<void> _applyLiveWallpaper() async {
    // Show alternating ad (awards credits), then proceed
    AdService.instance.showInterstitialAd(onAdDismissed: () {
      if (mounted) _doApplyLiveWallpaper();
    });
  }

  Future<void> _doApplyLiveWallpaper() async {
    // Release preview video player to free codec for the native wallpaper engine
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
    setState(() {
      _isVideoReady = false;
      _isApplying = true;
      _downloadProgress = 0.0;
      _loadingStatus = 'Downloading video...';
    });
    WallpaperStatsService.instance
        .trackDownload('live_${widget.wallpaper.id}');

    final dir = await getApplicationDocumentsDirectory();
    final localFile =
        File('${dir.path}/live_wallpapers/${widget.wallpaper.videoFile}');

    // Download with retry, timeout, connectivity check, and validation
    final path = await DownloadService.instance.downloadFile(
      widget.wallpaper.videoUrl,
      localFile,
      retries: 3,
      timeoutSeconds: 120,
      minBytes: 1000,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
      onError: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
      },
    );

    if (path == null) {
      if (mounted) setState(() => _isApplying = false);
      return;
    }

    if (mounted) setState(() => _loadingStatus = 'Setting live wallpaper...');

    await WallpaperService.instance.setLiveWallpaper(
      path,
      widget.wallpaper.glowColor,
      interactive: _interactiveMode,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Live wallpaper set!'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      // Go back to home — frees all preview resources
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<bool> _isDownloaded() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/live_wallpapers/${widget.wallpaper.videoFile}');
    return file.exists();
  }

  Future<void> _deleteFromDevice() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/live_wallpapers/${widget.wallpaper.videoFile}');
    if (await file.exists()) {
      await file.delete();
      if (mounted) {
        setState(() {
          _isDownloadedFuture = _isDownloaded();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video deleted from device'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wallpaper;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video or preview image
            if (_isVideoReady && _videoController != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
              )
            else
              CachedNetworkImage(
                imageUrl: w.previewUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Container(color: const Color(0xFF0A0A0F)),
              ),

            // Loading indicator while video loads
            if (!_isVideoReady)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: _glowColor),
                    const SizedBox(height: 12),
                    Text(
                      'Loading preview...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

            // Loading overlay
            LoadingOverlay(
              visible: _isApplying,
              progress: _downloadProgress > 0 ? _downloadProgress : null,
              status: _loadingStatus,
              accentColor: _glowColor,
            ),

            // Controls overlay (animated fade)
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.5),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.8),
                    ],
                    stops: const [0.0, 0.2, 0.6, 1.0],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      // Top bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Text(
                                w.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                w.typeBadge,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Bottom info + button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            Text(
                              w.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.7),
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            // Tags
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: w.tags
                                  .take(5)
                                  .map((tag) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _glowColor.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color:
                                                  _glowColor.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          tag,
                                          style: TextStyle(
                                              fontSize: 10, color: _glowColor),
                                        ),
                                      ))
                                  .toList(),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${(w.videoSize / 1024 / 1024).toStringAsFixed(1)} MB • 6s loop',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                            const SizedBox(height: 14),
                            // Mode toggle: Auto Play / Touch
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _interactiveMode = false),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: !_interactiveMode
                                              ? _glowColor.withOpacity(0.3)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          border: !_interactiveMode
                                              ? Border.all(color: _glowColor.withOpacity(0.5))
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.play_circle_outline, size: 16,
                                              color: !_interactiveMode ? Colors.white : Colors.white38),
                                            const SizedBox(width: 6),
                                            Text('Auto Play',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                                                color: !_interactiveMode ? Colors.white : Colors.white38)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _interactiveMode = true),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: _interactiveMode
                                              ? _glowColor.withOpacity(0.3)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          border: _interactiveMode
                                              ? Border.all(color: _glowColor.withOpacity(0.5))
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.touch_app, size: 16,
                                              color: _interactiveMode ? Colors.white : Colors.white38),
                                            const SizedBox(width: 6),
                                            Text('Touch',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                                                color: _interactiveMode ? Colors.white : Colors.white38)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Apply button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed:
                                    _isApplying ? null : _applyLiveWallpaper,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _glowColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _isApplying
                                    ? Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              value: _downloadProgress > 0
                                                  ? _downloadProgress
                                                  : null,
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            _downloadProgress > 0
                                                ? 'Downloading ${(_downloadProgress * 100).toInt()}%'
                                                : 'Preparing...',
                                          ),
                                        ],
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.download, size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            'Set as Live Wallpaper',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            // Ad status + credits
                            Builder(builder: (_) {
                              final isFree = AdService.instance.isNextActionFree;
                              final credits = CreditService.instance.balance;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 4),
                                child: Row(
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
                                    Icon(Icons.diamond, size: 12, color: const Color(0xFF7C4DFF)),
                                    const SizedBox(width: 3),
                                    Text('$credits', style: const TextStyle(fontSize: 11, color: Color(0xFF7C4DFF))),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 6),
                            // Delete from device button
                            FutureBuilder<bool>(
                              future: _isDownloadedFuture,
                              builder: (ctx, snap) {
                                if (snap.data != true) return const SizedBox.shrink();
                                return SizedBox(
                                  width: double.infinity,
                                  height: 40,
                                  child: TextButton.icon(
                                    onPressed: _deleteFromDevice,
                                    icon: Icon(Icons.delete_outline,
                                        size: 18, color: Colors.red.shade300),
                                    label: Text(
                                      'Delete from device',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.red.shade300,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
