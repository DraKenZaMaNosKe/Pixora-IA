import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/realm_catalog_service.dart';
import '../../data/realm_shader.dart';
import 'realm_card.dart';

/// Riverpod provider exposing the live REALM catalog fetched from Supabase.
/// `RealmCatalogService` falls back to the in-code list on cold start with
/// no network, so this never errors with empty data in normal conditions.
final realmCatalogProvider = FutureProvider<List<RealmShader>>((ref) async {
  return RealmCatalogService.instance.fetchCatalog();
});

/// Renders a 2-column grid of REALM shader cards. Used by HotWallpapersPage
/// when the user picks the SHADERS or CLOCKS sub-tab. Filters by category
/// (clocksOnly / abstracts) at the widget boundary so the parent page stays
/// free of catalog logic.
class RealmGridSection extends ConsumerWidget {
  final bool clocksOnly;

  const RealmGridSection({super.key, required this.clocksOnly});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(realmCatalogProvider);
    return async.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 80),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) =>
          _empty(context, 'Error cargando · ${e.toString().split(':').first}'),
      data: (all) {
        final items = all.where((s) {
          return clocksOnly
              ? s.category == RealmCategory.clock
              : s.category == RealmCategory.abstract_;
        }).toList();
        if (items.isEmpty) {
          return _empty(
              context,
              clocksOnly
                  ? 'Más relojes próximamente'
                  : 'Más shaders próximamente');
        }
        return RefreshIndicator(
          color: Colors.white,
          onRefresh: () async {
            await RealmCatalogService.instance.clearCache();
            ref.invalidate(realmCatalogProvider);
            await ref.read(realmCatalogProvider.future);
          },
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.65,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => RealmCard(
              shader: items[i],
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context, String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Center(
          child: Text(
            msg,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
          ),
        ),
      );
}
