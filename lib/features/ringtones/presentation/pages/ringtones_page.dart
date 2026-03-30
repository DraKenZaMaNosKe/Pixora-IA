import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/ringtone_providers.dart';
import '../../data/models/ringtone_pack.dart';
import 'ringtone_pack_page.dart';

class RingtonesPage extends ConsumerWidget {
  const RingtonesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(ringtonePacksProvider);

    return packsAsync.when(
      loading: () => const _ShimmerLoading(),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            const Text('Failed to load ringtones', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(ringtonePacksProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (packs) {
        if (packs.isEmpty) {
          return const Center(
            child: Text('No ringtone packs available yet',
                style: TextStyle(color: Colors.white54)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: packs.length,
          itemBuilder: (context, index) => _AnimatedPackCard(
            pack: packs[index],
            index: index,
          ),
        );
      },
    );
  }
}

/// Shimmer loading placeholder while packs are loading
class _ShimmerLoading extends StatelessWidget {
  const _ShimmerLoading();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, index) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Shimmer.fromColors(
          baseColor: const Color(0xFF1A1A2E),
          highlightColor: const Color(0xFF2A2A3E),
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedPackCard extends StatefulWidget {
  final RingtonePack pack;
  final int index;
  const _AnimatedPackCard({required this.pack, required this.index});

  @override
  State<_AnimatedPackCard> createState() => _AnimatedPackCardState();
}

class _AnimatedPackCardState extends State<_AnimatedPackCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(Duration(milliseconds: 100 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _glowColor {
    try {
      final hex = widget.pack.glowColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.deepPurple;
    }
  }

  IconData get _categoryIcon {
    switch (widget.pack.category) {
      case 'GAMING': return Icons.videogame_asset;
      case 'ANIME_TV': return Icons.tv;
      case 'RETRO_CLASSIC': return Icons.phone_callback;
      case 'MODERN_FUTURISTIC': return Icons.smartphone;
      case 'CHILL_AMBIENT': return Icons.spa;
      default: return Icons.music_note;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final slide = Curves.easeOutCubic.transform(_controller.value);
        final fade = Curves.easeOut.transform(_controller.value);
        final scale = 0.9 + 0.1 * Curves.easeOutBack.transform(_controller.value);

        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, 40 * (1 - slide)),
            child: Transform.scale(
              scale: scale,
              child: _buildCard(context),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context) {
    final hasImage = widget.pack.previewImage.isNotEmpty;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RingtonePackPage(pack: widget.pack)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _glowColor.withOpacity(0.15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Background — full bleed
              Positioned.fill(
                child: hasImage
                    ? CachedNetworkImage(
                        imageUrl: widget.pack.previewUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _packGradient(),
                      )
                    : _packGradient(),
              ),

              // Dark overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withOpacity(0.85),
                        Colors.black.withOpacity(0.3),
                      ],
                    ),
                  ),
                ),
              ),

              // Content — intrinsic height
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _glowColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _glowColor.withOpacity(0.4)),
                      ),
                      child: Icon(_categoryIcon, color: _glowColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.pack.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.pack.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.6),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _glowColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${widget.pack.tones.length} sounds',
                              style: TextStyle(fontSize: 10, color: _glowColor, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: _glowColor.withOpacity(0.6), size: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _packGradient() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_glowColor.withOpacity(0.4), const Color(0xFF0A0A0F)],
        ),
      ),
    );
  }
}
