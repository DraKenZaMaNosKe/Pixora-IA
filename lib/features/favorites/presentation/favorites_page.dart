import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/catalog_service.dart';
import '../../wallpapers/data/models/wallpaper.dart';
import '../../wallpapers/presentation/pages/wallpaper_preview_page.dart';
import '../providers/favorites_provider.dart';

/// FAVORITES tab — Cabinet of Curiosities (concept #05, picked by Eduardo
/// 2026-05-16). Victorian wunderkammer aesthetic: warm wood-grain bg with
/// amber spotlights, items grouped by category as wooden shelves divided
/// by thin gold lines, each card has a small museum-specimen tag hanging
/// from the bottom in Cormorant italic + collected date in Roman numerals.
/// Cards pulse very subtly like candlelight (opacity 0.93 ↔ 1.0 over 6s).
class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  // Warm cabinet palette — always dark, always cozy
  static const _bg = Color(0xFF2A1A12);
  static const _bgDeep = Color(0xFF18100A);
  static const _shelf = Color(0xFF3B2A1F);
  static const _brass = Color(0xFFD4AF37);
  static const _brassBright = Color(0xFFF5D676);
  static const _brassDim = Color(0xFF8B7228);
  static const _parchment = Color(0xFFE8DCC0);
  static const _parchmentDim = Color(0xFFB8AC92);
  static const _tag = Color(0xFFF0E4C8);
  static const _ink = Color(0xFF3A2418);

  @override
  Widget build(BuildContext context) {
    final favoriteIds = ref.watch(favoritesProvider);
    final allWallpapers = CatalogService.instance.wallpapers;
    final favorites =
        allWallpapers.where((w) => favoriteIds.contains(w.id)).toList();

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.7),
          radius: 1.4,
          colors: [Color(0xFF3B2418), _bg, _bgDeep],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: favorites.isEmpty ? _emptyState() : _cabinet(favorites),
    );
  }

  // ── Empty state — single tag with brass ─────────────────────────────
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_border,
              color: _brass.withValues(alpha: 0.6), size: 52),
          const SizedBox(height: 18),
          Text(
            'GABINETE VACÍO',
            style: GoogleFonts.cinzel(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _brass,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'toca el corazón en cualquier pieza para empezar tu colección',
              textAlign: TextAlign.center,
              style: GoogleFonts.cormorantGaramond(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: _parchmentDim,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Cabinet view: header + shelves grouped by category ─────────────
  Widget _cabinet(List<Wallpaper> favorites) {
    final grouped = <String, List<Wallpaper>>{};
    for (final w in favorites) {
      final key = (w.category.isEmpty ? 'OTROS' : w.category).toUpperCase();
      grouped.putIfAbsent(key, () => []).add(w);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _cabinetHeader(favorites.length)),
        for (final key in sortedKeys) ...[
          SliverToBoxAdapter(
            child: _shelfHeader(key, grouped[key]!.length),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 28,
                crossAxisSpacing: 14,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _flickerCard(grouped[key]![i]),
                childCount: grouped[key]!.length,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _shelfDivider()),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ── Cabinet title at the top ────────────────────────────────────────
  Widget _cabinetHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '// CABINET · WUNDERKAMMER',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: _brass,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tu colección.',
            style: GoogleFonts.fraunces(
              fontSize: 26,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              color: _parchment,
              letterSpacing: -0.3,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count ${count == 1 ? "pieza catalogada" : "piezas catalogadas"} · MMXXVI',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: _parchmentDim,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _brass.withValues(alpha: 0.6),
                  _brass.withValues(alpha: 0.0),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _brass.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Per-section "shelf" header (e.g. "ANIME · 4 PIEZAS") ───────────
  Widget _shelfHeader(String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
      child: Row(
        children: [
          Container(width: 16, height: 1, color: _brass),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.cinzel(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _brassBright,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '· $count ${count == 1 ? "pieza" : "piezas"}',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: _parchmentDim,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 0.6,
              color: _brass.withValues(alpha: 0.25),
            ),
          ),
        ],
      ),
    );
  }

  // ── Thin gold line dividing shelves ────────────────────────────────
  Widget _shelfDivider() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 0),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              _brass.withValues(alpha: 0.35),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  // ── Single specimen card with hanging tag ──────────────────────────
  // Was wrapped in candle-flicker AnimatedBuilder (±0.07 opacity over 6s)
  // — perf review C-2 (2026-05-16) flagged it: at 20+ favoritos the cost
  // far outweighs the barely-visible effect. Removed in favor of static
  // warm spotlight shadow.
  Widget _flickerCard(Wallpaper w) {
    return _staticSpecimenCard(w);
  }

  Widget _staticSpecimenCard(Wallpaper w) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WallpaperPreviewPage(wallpaper: w),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Specimen image with brass border + ambient warm glow
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _shelf,
                border: Border.all(color: _brass, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: _brassBright.withValues(alpha: 0.18),
                    blurRadius: 14,
                    spreadRadius: -2,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              child: Padding(
                // Tiny inset so a thin matboard rim is visible
                padding: const EdgeInsets.all(3),
                child: ClipRect(
                  child: w.previewUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: w.previewUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 400,
                          placeholder: (_, __) => Container(color: _bgDeep),
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(Icons.image_not_supported,
                                color: _brassDim),
                          ),
                        )
                      : Container(color: _bgDeep),
                ),
              ),
            ),
          ),
          // Thread from the bottom of the frame to the tag
          Container(width: 1, height: 8, color: _brass.withValues(alpha: 0.6)),
          // Specimen tag — parchment trapezoid with name + Roman date
          _specimenTag(w),
        ],
      ),
    );
  }

  Widget _specimenTag(Wallpaper w) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
      decoration: BoxDecoration(
        color: _tag,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            w.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.cormorantGaramond(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              color: _ink,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            _romanFromId(w.id),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 7,
              fontWeight: FontWeight.w700,
              color: _ink.withValues(alpha: 0.55),
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Deterministic pseudo-Roman number from an id, used as the specimen
  /// catalog number under each tag. Always between I and XCIX (1-99).
  String _romanFromId(String id) {
    final n = (id.hashCode.abs() % 99) + 1;
    return 'N.º ${_toRoman(n)}';
  }

  String _toRoman(int n) {
    const vals = [50, 40, 10, 9, 5, 4, 1];
    const syms = ['L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
    var v = n;
    final sb = StringBuffer();
    for (var i = 0; i < vals.length; i++) {
      while (v >= vals[i]) {
        sb.write(syms[i]);
        v -= vals[i];
      }
    }
    return sb.toString();
  }
}
