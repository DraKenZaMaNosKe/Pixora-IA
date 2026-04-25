import 'dart:io';
import '../../../../core/design/hud_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/content/content_manager.dart';
import '../../../../core/content/content_types.dart';
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
  bool _isApplying = false;
  double _downloadProgress = 0.0;
  String _loadingStatus = '';
  LoadingPhase _loadingPhase = LoadingPhase.downloading;
  bool _showControls = true;
  bool _interactiveMode = false; // false = Auto Play, true = Touch scrub
  late Future<bool> _isDownloadedFuture;
  int _controlsToken = 0;

  Color get _glowColor => HudTokens.gold;

  @override
  void initState() {
    super.initState();
    // Force Explore mode for explore-only videos
    if (widget.wallpaper.exploreOnly) _interactiveMode = true;
    _isDownloadedFuture = _isDownloaded();
    WallpaperStatsService.instance.trackView('live_${widget.wallpaper.id}');
    _scheduleAutoHide();
  }

  void _scheduleAutoHide() {
    final token = ++_controlsToken;
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _controlsToken == token) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _controlsToken++;
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
    setState(() {
      _isApplying = true;
      _downloadProgress = 0.0;
      _loadingStatus = 'Checking system...';
      _loadingPhase = LoadingPhase.downloading;
    });

    // Small delay to ensure previous wallpaper service releases codec
    if (!_interactiveMode) {
      if (mounted) setState(() => _loadingStatus = 'Preparing player...');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (mounted) {
      setState(() {
        _loadingStatus = 'Downloading...';
        _loadingPhase = LoadingPhase.downloading;
      });
    }
    WallpaperStatsService.instance.trackDownload('live_${widget.wallpaper.id}');

    final dir = await getApplicationDocumentsDirectory();
    final w = widget.wallpaper;

    // Explore mode with pre-extracted frames: download images from Supabase
    if (_interactiveMode && w.hasRemoteFrames) {
      if (mounted) {
        setState(() {
          _loadingStatus = 'Downloading scene frames...';
          _loadingPhase = LoadingPhase.downloading;
        });
      }
      final framesDir = Directory('${dir.path}/explore_frames/${w.id}');
      await framesDir.create(recursive: true);

      // Check if already cached
      final existing =
          framesDir.listSync().where((f) => f.path.endsWith('.jpg')).length;
      if (existing < w.frameCount) {
        // Download all frames
        for (var i = 0; i < w.frameCount; i++) {
          final frameFile = File(
              '${framesDir.path}/frame_${(i + 1).toString().padLeft(4, '0')}.jpg');
          if (await frameFile.exists() && await frameFile.length() > 100)
            continue;
          await DownloadService.instance.downloadFile(
            w.frameUrl(i),
            frameFile,
            retries: 2,
            timeoutSeconds: 30,
            minBytes: 100,
          );
          if (mounted) {
            setState(() => _downloadProgress = (i + 1) / w.frameCount);
          }
        }
      }

      // Set wallpaper with frames path
      if (mounted) {
        setState(() {
          _loadingPhase = LoadingPhase.installing;
          _loadingStatus = 'Applying explore wallpaper...';
        });
      }
      await WallpaperService.instance.setLiveWallpaper(
        framesDir.path,
        w.glowColor,
        interactive: true,
      );

      if (mounted) {
        setState(() {
          _loadingPhase = LoadingPhase.done;
          _loadingStatus = 'Explore wallpaper set!';
        });
        await Future.delayed(const Duration(milliseconds: 1200));
        setState(() => _isApplying = false);
      }
      return;
    }

    // Auto Play mode: download video via ContentManager
    final success = await ContentManager.instance.downloadAndInstall(
      item: w.toContentItem(explore: _interactiveMode),
      target: InstallTarget.liveWallpaper,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
      onPhase: (phase) {
        if (!mounted) return;
        setState(() {
          switch (phase) {
            case 'downloading':
              _loadingPhase = LoadingPhase.downloading;
              _loadingStatus = 'Downloading video...';
            case 'sprites':
              _loadingPhase = LoadingPhase.sprites;
              _loadingStatus = 'Downloading animated effects...';
              _downloadProgress = 0.0;
            case 'installing':
              _loadingPhase = LoadingPhase.installing;
              _loadingStatus = 'Applying live wallpaper...';
            case 'done':
              _loadingPhase = LoadingPhase.done;
              _loadingStatus = 'Live wallpaper applied!';
          }
        });
      },
      onError: (msg) {
        if (mounted) {
          setState(() {
            _loadingPhase = LoadingPhase.error;
            _loadingStatus = msg;
          });
        }
      },
    );

    if (!success) {
      if (mounted) {
        if (_loadingPhase != LoadingPhase.error) {
          setState(() {
            _loadingPhase = LoadingPhase.error;
            _loadingStatus = 'Failed to set live wallpaper';
          });
          await Future.delayed(const Duration(milliseconds: 1500));
        }
        setState(() => _isApplying = false);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loadingPhase = LoadingPhase.done;
        _loadingStatus = _interactiveMode
            ? 'Explore wallpaper set!'
            : 'Live wallpaper applied!';
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      setState(() => _isApplying = false);
    }
  }

  Future<bool> _isDownloaded() async {
    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/live_wallpapers/${widget.wallpaper.videoFile}');
    return file.exists();
  }

  Future<void> _deleteFromDevice() async {
    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/live_wallpapers/${widget.wallpaper.videoFile}');
    if (await file.exists()) {
      await file.delete();
      if (mounted) {
        setState(() {
          _isDownloadedFuture = _isDownloaded();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video deleted from device'),
            backgroundColor: HudTokens.gold,
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
            // Preview image (static — no video codec used)
            CachedNetworkImage(
              imageUrl: w.previewUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  Container(color: const Color(0xFF0A0A0F)),
            ),

            // Loading overlay
            LoadingOverlay(
              visible: _isApplying,
              progress: _downloadProgress > 0 ? _downloadProgress : null,
              status: _loadingStatus,
              accentColor: _glowColor,
              phase: _loadingPhase,
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
                                color: HudTokens.goldDeep,
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
                            // Mode toggle: Auto Play / Explore (hidden for explore-only)
                            if (!widget.wallpaper.exploreOnly)
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
                                        onTap: () => setState(
                                            () => _interactiveMode = false),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          decoration: BoxDecoration(
                                            color: !_interactiveMode
                                                ? _glowColor.withOpacity(0.3)
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: !_interactiveMode
                                                ? Border.all(
                                                    color: _glowColor
                                                        .withOpacity(0.5))
                                                : null,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.play_circle_outline,
                                                  size: 16,
                                                  color: !_interactiveMode
                                                      ? Colors.white
                                                      : Colors.white38),
                                              const SizedBox(width: 6),
                                              Text('Auto Play',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: !_interactiveMode
                                                          ? Colors.white
                                                          : Colors.white38)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(
                                            () => _interactiveMode = true),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _interactiveMode
                                                ? _glowColor.withOpacity(0.3)
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: _interactiveMode
                                                ? Border.all(
                                                    color: _glowColor
                                                        .withOpacity(0.5))
                                                : null,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.explore,
                                                  size: 16,
                                                  color: _interactiveMode
                                                      ? Colors.white
                                                      : Colors.white38),
                                              const SizedBox(width: 6),
                                              Text('Explore',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: _interactiveMode
                                                          ? Colors.white
                                                          : Colors.white38)),
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
                              final isFree =
                                  AdService.instance.isNextActionFree;
                              final credits = CreditService.instance.balance;
                              return Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isFree
                                            ? HudTokens.gold.withOpacity(0.2)
                                            : HudTokens.gold.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: isFree
                                                ? HudTokens.gold
                                                    .withOpacity(0.5)
                                                : HudTokens.gold
                                                    .withOpacity(0.5)),
                                      ),
                                      child: Text(
                                        isFree
                                            ? 'FREE!'
                                            : '+${CreditService.creditsPerAd} credits',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isFree
                                                ? HudTokens.gold
                                                : HudTokens.gold),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.diamond,
                                        size: 12, color: HudTokens.gold),
                                    const SizedBox(width: 3),
                                    Text('$credits',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: HudTokens.gold)),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 6),
                            // Delete from device button
                            FutureBuilder<bool>(
                              future: _isDownloadedFuture,
                              builder: (ctx, snap) {
                                if (snap.data != true)
                                  return const SizedBox.shrink();
                                return SizedBox(
                                  width: double.infinity,
                                  height: 40,
                                  child: TextButton.icon(
                                    onPressed: _deleteFromDevice,
                                    icon: Icon(Icons.delete_outline,
                                        size: 18, color: HudTokens.goldDeep),
                                    label: Text(
                                      'Delete from device',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: HudTokens.goldDeep,
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
