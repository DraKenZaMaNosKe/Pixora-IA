import 'package:flutter/material.dart';

import '../../data/realm_catalog.dart';
import '../../data/realm_shader.dart';
import 'realm_card.dart';

/// Renders a 2-column grid of REALM shader cards. Used by HotWallpapersPage
/// when the user picks the SHADERS or CLOCKS sub-tab. Stateless — the
/// selection state lives in the parent page.
class RealmGridSection extends StatelessWidget {
  /// If `clocksOnly` is true, only clock-category shaders are rendered;
  /// false renders only abstract/decorative shaders. Splitting at the
  /// widget boundary keeps the parent page free of filtering logic.
  final bool clocksOnly;

  const RealmGridSection({super.key, required this.clocksOnly});

  @override
  Widget build(BuildContext context) {
    final List<RealmShader> items =
        clocksOnly ? RealmCatalog.clocks : RealmCatalog.abstracts;

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Center(
          child: Text(
            clocksOnly
                ? 'Más relojes próximamente'
                : 'Más shaders próximamente',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return GridView.builder(
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
    );
  }
}
