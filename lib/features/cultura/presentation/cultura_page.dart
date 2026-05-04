import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/hud_tokens.dart';
import '../../wallpapers/data/models/wallpaper.dart';
import '../../wallpapers/presentation/pages/wallpaper_preview_page.dart';
import '../../../widgets/cached_wallpaper_image.dart';
import '../providers/cultura_provider.dart';

/// "Cultura" section — editorial codex layout listing wallpapers with rich
/// mythological / historical content. Picked design 01 ("Códice Editorial")
/// from cultura_section_concepts.html. Each entry is a manuscript-style
/// page: thumbnail + chapter + title + drop-cap lead + tag chips.
///
/// Initially curated to a single wallpaper (Mictlantecuhtli). New mythological
/// wallpapers get added by editing _curatedCulturaIds in the provider.
class CulturaPage extends ConsumerWidget {
  const CulturaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = context.hud;
    final async = ref.watch(culturaWallpapersProvider);
    return Container(
      color: h.bg,
      child: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: h.accent, strokeWidth: 2),
          ),
          error: (e, _) => Center(
            child: Text('No se pudo cargar Cultura',
                style: TextStyle(color: h.textDim)),
          ),
          data: (items) =>
              items.isEmpty ? _Empty(h: h) : _CodexList(items: items, h: h),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.h});
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, size: 56, color: h.textDim),
          const SizedBox(height: 18),
          Text(
            'Códex Pixora',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 24,
              color: h.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Próximamente — wallpapers con historia, mitología y datos curiosos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: h.textDim, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Códice Editorial — vertical list, manuscript page per wallpaper.
class _CodexList extends StatelessWidget {
  const _CodexList({required this.items, required this.h});
  final List<Wallpaper> items;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    final accent = h.accent;
    final iosLight = h.isIosStyle;
    final dim = h.textDim;
    final dashColor =
        iosLight ? const Color(0xFFC0B09A) : const Color(0xFF2A2210);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 30),
      itemCount: items.length + 1, // header + entries
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return _Header(h: h, accent: accent, dashColor: dashColor);
        }
        final w = items[i - 1];
        return _CodexItem(
          wallpaper: w,
          h: h,
          accent: accent,
          dimColor: dim,
          dashColor: dashColor,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WallpaperPreviewPage(wallpaper: w),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.h, required this.accent, required this.dashColor});
  final HudTheme h;
  final Color accent;
  final Color dashColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 36, 26, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '— CÓDEX PIXORA —',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 10,
              letterSpacing: 3.5,
              color: accent,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Cultura',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 38,
              fontWeight: FontWeight.w400,
              height: 1,
              color: h.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Mitología, historia y ciencia ilustrada en wallpapers vivos.',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 13,
              color: h.textDim,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: dashColor),
        ],
      ),
    );
  }
}

class _CodexItem extends StatelessWidget {
  const _CodexItem({
    required this.wallpaper,
    required this.h,
    required this.accent,
    required this.dimColor,
    required this.dashColor,
    required this.onTap,
  });
  final Wallpaper wallpaper;
  final HudTheme h;
  final Color accent;
  final Color dimColor;
  final Color dashColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = wallpaper.cultural;
    if (c == null) return const SizedBox.shrink();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail (manuscript-paper style: small, slight shadow)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    width: 84,
                    height: 130,
                    child: CachedWallpaperImage(
                      imageUrl: wallpaper.previewUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((c.chapter ?? '').isNotEmpty)
                        Text(
                          '— ${c.chapter} —',
                          style: TextStyle(
                            fontFamily: 'Fraunces',
                            fontStyle: FontStyle.italic,
                            fontSize: 11,
                            letterSpacing: 2.0,
                            color: accent,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _shortName(wallpaper.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: 22,
                          fontWeight: FontWeight.w400,
                          height: 1.05,
                          color: h.text,
                        ),
                      ),
                      if ((c.subtitle ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            c.subtitle!,
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                              color: accent,
                            ),
                          ),
                        ),
                      if ((c.lead ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            c.lead!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: 12.5,
                              height: 1.45,
                              color: h.text.withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                      if (c.facts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: c.facts.take(3).map((f) {
                              return Text(
                                f.value.toUpperCase(),
                                style: TextStyle(
                                  fontFamily: 'JetBrainsMono',
                                  fontSize: 9,
                                  letterSpacing: 1.5,
                                  color: dimColor,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 1,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: dashColor,
                    width: 0.5,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortName(String full) {
    if (full.contains(' · ')) return full.split(' · ').first;
    return full;
  }
}
