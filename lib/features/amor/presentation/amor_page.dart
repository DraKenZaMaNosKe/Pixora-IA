import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/catalog_service.dart';
import '../../../core/services/mystery_slot.dart';
import '../../wallpapers/data/models/wallpaper.dart';
import '../../wallpapers/presentation/widgets/amor_latido_header.dart';
import '../../wallpapers/presentation/widgets/mystery_card_widget.dart';
import '../../wallpapers/presentation/widgets/wallpaper_card.dart';
import '../../wallpapers/providers/wallpaper_providers.dart';

/// Tab "Amor" — skin **Latido** (Eduardo 2026-07-05, elegido entre 5
/// propuestas en amor_skins.html).
///
/// Página completa de wallpapers de amor: parejas de anime, corazones neón,
/// siluetas al atardecer, enemigos convertidos en amigos. Mezcla static +
/// panorámico + canvas_scene vía tag `amor` — Pixora no es solo acción,
/// suspenso y terror; también amor para alegrar la vida del usuario.
///
/// Skin Latido: fondo negro cálido, header AM♥R en Anton rojo #D93A3A con
/// corazón latiendo (lub-dub), lema "sin miedo a sentir".
class AmorPage extends ConsumerWidget {
  const AmorPage({super.key});

  static const _bg = Color(0xFF0A0A0A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(amorWallpapersProvider);
    // RefreshIndicator envuelve TODO — incluso loading y estado vacío — para
    // que el pull-to-refresh siempre funcione (antes el _empty era un Center
    // sin scroll y no se podía jalar para recargar).
    return Container(
      color: _bg,
      child: RefreshIndicator(
        color: AmorLatidoHeader.red,
        backgroundColor: _bg,
        onRefresh: () => _refresh(ref),
        child: async.when(
          loading: () => _fullScreenScroll(
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 120),
                child: CircularProgressIndicator(color: AmorLatidoHeader.red),
              ),
            ),
          ),
          error: (_, __) => _fullScreenScroll(_emptyBody()),
          data: (items) => items.isEmpty
              ? _fullScreenScroll(_emptyBody())
              : _dataBody(items),
        ),
      ),
    );
  }

  /// Grid de wallpapers de amor con Mystery cards proporcionales.
  /// childAspectRatio 0.54 (antes 0.62 → 37px overflow, 0.58 → 18px): las
  /// WallpaperCard traen stats bar + badges que desbordan en un grid apretado.
  /// 2026-07-05.
  Widget _dataBody(List<Wallpaper> items) {
    // Set proporcional de Mystery cards. checkFavorites: true (modelo
    // Wallpaper) — mismo helper que wallpapers/3D.
    final mysterySet = pickMysteryIds(
      items.map((w) => w.id),
      checkFavorites: true,
    );
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: AmorLatidoHeader()),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.54,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final w = items[i];
                final card = WallpaperCard(wallpaper: w);
                if (mysterySet.contains(w.id)) {
                  return MysteryCardWidget(
                    wallpaperId: w.id,
                    placement: 'mystery_amor',
                    revealedChild: card,
                  );
                }
                return card;
              },
              childCount: items.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  /// forceRefresh salta la ventana de 30 min del cache Hive — sin esto,
  /// contenido recién etiquetado `amor` tarda hasta media hora en aparecer.
  Future<void> _refresh(WidgetRef ref) async {
    await CatalogService.instance.fetchCatalog(forceRefresh: true);
    ref.invalidate(catalogProvider);
    await ref.read(amorWallpapersProvider.future);
  }

  /// Envuelve un widget en un scroll de pantalla completa para que el
  /// RefreshIndicator pueda dispararse aun cuando no hay contenido.
  Widget _fullScreenScroll(Widget child) {
    return LayoutBuilder(
      builder: (ctx, box) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: child,
        ),
      ),
    );
  }

  /// Estado vacío — invitación, no tristeza. El contenido de amor se sube
  /// remoto (tag `amor`), así que esto solo se ve antes del primer lote.
  Widget _emptyBody() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AmorLatidoHeader(),
          const SizedBox(height: 18),
          Text(
            'Los primeros wallpapers de amor\nestán en camino.',
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              color: AmorLatidoHeader.bone.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
