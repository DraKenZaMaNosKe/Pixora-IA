import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
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
  bool _showControls = true;

  Color get _glowColor {
    try {
      final hex = widget.wallpaper.glowColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFFFF4500);
    }
  }

  @override
  void initState() {
    super.initState();
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
        // Auto-hide controls after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showControls = false);
        });
      }
    } catch (e) {
      debugPrint('[Pixora] Video init failed: $e');
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  Future<void> _applyLiveWallpaper() async {
    setState(() {
      _isApplying = true;
      _downloadProgress = 0.0;
    });
    WallpaperStatsService.instance
        .trackDownload('live_${widget.wallpaper.id}');

    final dir = await getApplicationDocumentsDirectory();
    final localFile =
        File('${dir.path}/live_wallpapers/${widget.wallpaper.videoFile}');
    await localFile.parent.create(recursive: true);

    // Always check if file exists and is valid — re-download if needed
    bool needsDownload = true;
    if (await localFile.exists()) {
      final size = await localFile.length();
      if (size > 1000) {
        needsDownload = false; // File exists and is not empty/corrupt
        debugPrint('[Pixora] Video cache hit: ${localFile.path} (${size}B)');
      } else {
        await localFile.delete(); // Delete corrupt file
        debugPrint('[Pixora] Deleted corrupt video: ${localFile.path}');
      }
    }

    if (needsDownload) {
      debugPrint('[Pixora] Downloading video: ${widget.wallpaper.videoUrl}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Downloading video...'),
            backgroundColor: _glowColor,
            duration: const Duration(seconds: 1),
          ),
        );
      }
      try {
        final request =
            http.Request('GET', Uri.parse(widget.wallpaper.videoUrl));
        final response = await http.Client().send(request);
        final totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;
        final sink = localFile.openWrite();
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0 && mounted) {
            setState(() => _downloadProgress = receivedBytes / totalBytes);
          }
        }
        await sink.close();
        debugPrint('[Pixora] Download complete: ${await localFile.length()}B');
      } catch (e) {
        debugPrint('[Pixora] Live wallpaper download failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Download failed. Check your connection.'),
                backgroundColor: Colors.red),
          );
        }
        setState(() => _isApplying = false);
        return;
      }
    }

    // Final validation
    if (!await localFile.exists() || await localFile.length() < 1000) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Video file is invalid. Try again.'),
              backgroundColor: Colors.red),
        );
      }
      setState(() => _isApplying = false);
      return;
    }

    debugPrint('[Pixora] Setting live wallpaper: ${localFile.path}');
    await WallpaperService.instance.setLiveWallpaper(
      localFile.path,
      widget.wallpaper.glowColor,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Live wallpaper set!'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
    setState(() => _isApplying = false);
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
        setState(() {});
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
                            const SizedBox(height: 10),
                            // Delete from device button
                            FutureBuilder<bool>(
                              future: _isDownloaded(),
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
