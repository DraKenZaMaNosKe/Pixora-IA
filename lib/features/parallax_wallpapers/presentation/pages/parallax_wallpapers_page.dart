import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../wallpapers/data/models/wallpaper.dart';
import '../../../wallpapers/presentation/pages/wallpaper_preview_page.dart';
import '../../providers/parallax_wallpaper_providers.dart';

/// "3D" tab — magazine editorial layout for parallax wallpapers.
///
/// One hero card on top, then a 2-column grid below, followed by a small
/// editorial quote panel. Reuses WallpaperPreviewPage for tap → apply
/// (which auto-resolves to canvas_scene parallax via StaticWallpaperInstaller).
class ParallaxWallpapersPage extends ConsumerWidget {
  const ParallaxWallpapersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = context.hud;
    final asyncList = ref.watch(parallaxWallpapersProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(parallaxWallpapersProvider),
      child: asyncList.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: h.accent),
        ),
        error: (e, _) => _EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'No pudimos cargar',
          subtitle: 'Revisa tu conexión y desliza para reintentar',
        ),
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyState(
              icon: Icons.threed_rotation_rounded,
              title: 'Pronto · piezas 3D curadas',
              subtitle:
                  'Estamos preparando wallpapers con parallax y profundidad.\nDesliza para reintentar.',
            );
          }
          final hero = items.first;
          final rest = items.skip(1).toList();
          return _MagazineLayout(hero: hero, rest: rest);
        },
      ),
    );
  }
}

class _MagazineLayout extends StatelessWidget {
  const _MagazineLayout({required this.hero, required this.rest});
  final Wallpaper hero;
  final List<Wallpaper> rest;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        // Editorial header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _Chip(label: '3D · TILT', color: h.accent),
                  const SizedBox(width: 8),
                  Text(
                    '${(rest.length + 1).toString().padLeft(2, '0')} piezas curadas',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 1.6,
                      color: h.textDim,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(
                  'Profundidad\ncurada.',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w300,
                    fontSize: 42,
                    height: 0.96,
                    letterSpacing: -1.2,
                    color: h.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'el equipo de Pixora elige · semanal',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: h.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Hero card
        SliverToBoxAdapter(
          child: _HeroCard(wallpaper: hero),
        ),

        // Editorial quote panel
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: h.accent, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '«La profundidad cobra vida cuando inclinas el teléfono.»',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                      height: 1.4,
                      color: h.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '— pixora editorial',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 9,
                      letterSpacing: 1.4,
                      color: h.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Section header
        if (rest.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
              child: Row(
                children: [
                  Container(width: 18, height: 1, color: h.accent),
                  const SizedBox(width: 10),
                  Text(
                    'MÁS · 3D',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 2.6,
                      color: h.text,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${rest.length.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 1.6,
                      color: h.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 2-column grid
        if (rest.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _GridCard(wallpaper: rest[i]),
                childCount: rest.length,
              ),
            ),
          ),

        // Bottom nav safe-space
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.wallpaper});
  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WallpaperPreviewPage(wallpaper: wallpaper),
          ),
        ),
        child: AspectRatio(
          aspectRatio: 0.78,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  wallpaper.previewUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, __, ___) => Container(color: h.surfaceHi),
                ),
                // Gradient overlay
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withOpacity(0.85),
                        ],
                        stops: const [0, 0.5, 1],
                      ),
                    ),
                  ),
                ),
                // Top-left badge
                Positioned(
                  top: 12,
                  left: 12,
                  child: _Chip(label: '★ EDITOR\'S PICK', color: h.goldBright),
                ),
                // Bottom info
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wallpaper.name,
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                          fontSize: 26,
                          height: 1.0,
                          color: h.goldBright,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        wallpaper.description.isEmpty
                            ? 'Parallax 3D · giroscopio'
                            : wallpaper.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 10,
                          letterSpacing: 0.4,
                          height: 1.4,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: h.accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '▸ APLICAR',
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.2,
                            color: Colors.black.withOpacity(0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  const _GridCard({required this.wallpaper});
  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WallpaperPreviewPage(wallpaper: wallpaper),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    wallpaper.previewUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                    errorBuilder: (_, __, ___) => Container(color: h.surfaceHi),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _Chip(label: '3D', color: h.accent, dense: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            wallpaper.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 13,
              color: h.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.dense = false});
  final String label;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 7 : 10, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withOpacity(0.45),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: dense ? 8 : 9,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.6,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Icon(icon, color: h.textDim, size: 48),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontStyle: FontStyle.italic,
            fontSize: 22,
            height: 1.1,
            color: h.text,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 11,
            height: 1.5,
            letterSpacing: 0.6,
            color: h.textDim,
          ),
        ),
      ],
    );
  }
}
