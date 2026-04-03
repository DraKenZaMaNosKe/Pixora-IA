import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/quality_service.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../../../widgets/touch_glow_effect.dart';
import '../../../favorites/providers/favorites_provider.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../data/models/wallpaper.dart';

class WallpaperPreviewPage extends ConsumerStatefulWidget {
  const WallpaperPreviewPage({required this.wallpaper, super.key});

  final Wallpaper wallpaper;

  @override
  ConsumerState<WallpaperPreviewPage> createState() =>
      _WallpaperPreviewPageState();
}

class _WallpaperPreviewPageState extends ConsumerState<WallpaperPreviewPage> {
  bool _isApplying = false;
  double _downloadProgress = 0.0;
  String _loadingStatus = '';

  @override
  void initState() {
    super.initState();
    // Track view when user opens wallpaper
    WallpaperStatsService.instance.trackView(widget.wallpaper.id);
  }

  /// Get the file to download based on quality setting.
  String get _downloadFile {
    final quality = ref.read(imageQualityProvider);
    if (quality == ImageQuality.lq) return widget.wallpaper.previewFile;
    return widget.wallpaper.imageFile; // HD and Auto use full image
  }

  Color _parseGlowColor() => parseHexColor(widget.wallpaper.glowColor, fallback: Colors.white);

  void _setLoading(String status, {double progress = 0.0}) {
    if (mounted) setState(() { _loadingStatus = status; _downloadProgress = progress; });
  }

  Future<void> _applyWallpaper(int target) async {
    setState(() { _isApplying = true; _downloadProgress = 0.0; _loadingStatus = 'Downloading...'; });
    WallpaperStatsService.instance.trackDownload(widget.wallpaper.id);

    String? errorMsg;
    final path = await DownloadService.instance.downloadWallpaper(
      _downloadFile,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
      onError: (msg) => errorMsg = msg,
    );

    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg ?? 'Download failed'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isApplying = false);
      return;
    }

    _setLoading('Applying wallpaper...', progress: 1.0);

    final success = await WallpaperService.instance.setWallpaper(path, target);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Wallpaper applied!' : 'Failed to apply wallpaper'),
          backgroundColor: success ? Colors.green.shade700 : Colors.red,
        ),
      );
    }
    setState(() => _isApplying = false);
  }

  Future<void> _saveToGallery() async {
    setState(() { _isApplying = true; _downloadProgress = 0.0; _loadingStatus = 'Downloading...'; });
    WallpaperStatsService.instance.trackDownload(widget.wallpaper.id);

    String? errorMsg;
    final path = await DownloadService.instance.downloadWallpaper(
      _downloadFile,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
      onError: (msg) => errorMsg = msg,
    );

    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg ?? 'Download failed'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isApplying = false);
      return;
    }

    // Verify file on disk
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found after download'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isApplying = false);
      return;
    }

    _setLoading('Saving to gallery...', progress: 1.0);

    final success = await WallpaperService.instance.saveToGallery(path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Saved to Photos!' : 'Failed to save to gallery'),
          backgroundColor: success ? Colors.green.shade700 : Colors.red,
        ),
      );
    }
    setState(() => _isApplying = false);
  }

  Future<void> _applyLiveWallpaper() async {
    setState(() { _isApplying = true; _downloadProgress = 0.0; _loadingStatus = 'Preparing...'; });
    WallpaperStatsService.instance.trackDownload(widget.wallpaper.id);

    // Request microphone permission for equalizer visualization
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission needed for equalizer effect'),
        ),
      );
    }

    _setLoading('Downloading...');

    String? errorMsg;
    final path = await DownloadService.instance.downloadWallpaper(
      _downloadFile,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
      onError: (msg) => errorMsg = msg,
    );

    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg ?? 'Download failed'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isApplying = false);
      return;
    }

    _setLoading('Setting live wallpaper...', progress: 1.0);

    await WallpaperService.instance.setLiveWallpaper(
      path,
      widget.wallpaper.glowColor,
    );

    setState(() => _isApplying = false);
  }

  void _showApplyDialog() {
    if (Platform.isIOS) {
      _saveToGallery();
      return;
    }

    // Show interstitial ad, then show the apply options
    AdService.instance.showInterstitialAd(
      onAdDismissed: () {
        if (!mounted) return;
        _showApplyOptions();
      },
    );
  }

  void _showApplyOptions() {
    final isFree = AdService.instance.isNextActionFree;
    final glowColor = _parseGlowColor();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Set wallpaper as',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                // FREE! / Ad badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isFree
                        ? Colors.green.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isFree
                          ? Colors.greenAccent.withOpacity(0.5)
                          : Colors.orange.withOpacity(0.5),
                    ),
                  ),
                  child: Text(
                    isFree ? 'FREE!' : 'Ad next',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isFree ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                ),
              ],
            ),
            if (isFree) ...[
              const SizedBox(height: 6),
              Text(
                'Next wallpaper is ad-free!',
                style: TextStyle(fontSize: 12, color: Colors.greenAccent.withOpacity(0.7)),
              ),
            ],
            const SizedBox(height: 20),
            _buildOption(Icons.home, 'Home Screen', () {
              Navigator.pop(context);
              _applyWallpaper(0);
            }),
            _buildOption(Icons.lock, 'Lock Screen', () {
              Navigator.pop(context);
              _applyWallpaper(1);
            }),
            _buildOption(Icons.phone_android, 'Both', () {
              Navigator.pop(context);
              _applyWallpaper(2);
            }),
            const Divider(color: Colors.white12),
            _buildOption(Icons.auto_awesome, 'Live Wallpaper (Touch Effect)', () {
              Navigator.pop(context);
              _applyLiveWallpaper();
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFav = ref.watch(favoritesProvider).contains(widget.wallpaper.id);
    final glowColor = _parseGlowColor();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fullscreen image with touch glow (ignores touch when loading)
          IgnorePointer(
            ignoring: _isApplying,
            child: TouchGlowEffect(
              glowColor: glowColor,
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 3.0,
                child: CachedWallpaperImage(
                  imageUrl: widget.wallpaper.fullImageUrl,
                ),
              ),
            ),
          ),

          // Loading overlay
          LoadingOverlay(
            visible: _isApplying,
            progress: _downloadProgress > 0 ? _downloadProgress : null,
            status: _loadingStatus,
            accentColor: glowColor,
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.black54),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => ref
                          .read(favoritesProvider.notifier)
                          .toggle(widget.wallpaper.id),
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav ? Colors.redAccent : Colors.white,
                      ),
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom info & apply button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.wallpaper.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.wallpaper.category} · ${widget.wallpaper.imageSizeFormatted}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                      if (widget.wallpaper.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.wallpaper.description,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                                onPressed: _isApplying ? null : _showApplyDialog,
                                icon: Icon(
                                  Platform.isIOS
                                      ? Icons.save_alt
                                      : Icons.wallpaper,
                                ),
                                label: Text(
                                  Platform.isIOS
                                      ? 'Save to Photos'
                                      : 'Set Wallpaper',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: glowColor,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
