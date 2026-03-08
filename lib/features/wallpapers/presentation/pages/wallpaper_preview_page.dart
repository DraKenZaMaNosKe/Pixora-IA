import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../../favorites/providers/favorites_provider.dart';
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

  Color _parseGlowColor() {
    try {
      final hex = widget.wallpaper.glowColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }

  Future<void> _applyWallpaper(int target) async {
    setState(() => _isApplying = true);

    final path =
        await DownloadService.instance.downloadWallpaper(widget.wallpaper.imageFile);

    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed')),
        );
      }
      setState(() => _isApplying = false);
      return;
    }

    final success = await WallpaperService.instance.setWallpaper(path, target);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Wallpaper applied!' : 'Failed to apply'),
        ),
      );
    }
    setState(() => _isApplying = false);
  }

  Future<void> _saveToGallery() async {
    setState(() => _isApplying = true);

    final path =
        await DownloadService.instance.downloadWallpaper(widget.wallpaper.imageFile);

    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed')),
        );
      }
      setState(() => _isApplying = false);
      return;
    }

    final success = await WallpaperService.instance.saveToGallery(path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Saved to gallery!'
              : 'Saved! Set it from Settings > Wallpaper'),
        ),
      );
    }
    setState(() => _isApplying = false);
  }

  void _showApplyDialog() {
    if (Platform.isIOS) {
      _saveToGallery();
      return;
    }

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
            const Text(
              'Set wallpaper as',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
          // Fullscreen image
          InteractiveViewer(
            minScale: 1.0,
            maxScale: 3.0,
            child: CachedWallpaperImage(
              imageUrl: widget.wallpaper.fullImageUrl,
            ),
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
                          icon: _isApplying
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Icon(
                                  Platform.isIOS
                                      ? Icons.save_alt
                                      : Icons.wallpaper,
                                ),
                          label: Text(
                            _isApplying
                                ? 'Applying...'
                                : Platform.isIOS
                                    ? 'Save to Photos'
                                    : 'Set Wallpaper',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: glowColor,
                            foregroundColor: Colors.black,
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
