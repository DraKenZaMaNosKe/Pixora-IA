import 'package:flutter/material.dart';

/// M05 — Catalog Shimmer Skeleton.
///
/// Card placeholder con shimmer animado mientras se carga contenido real.
/// Reemplaza spinners en grids de wallpapers, listas de tracks, etc.
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M05).
///
/// Uso:
/// ```dart
/// GridView.builder(
///   itemCount: 6, // skeleton count
///   itemBuilder: (_, __) => const ShimmerCard(aspectRatio: 9 / 16),
/// );
/// ```
class ShimmerCard extends StatefulWidget {
  const ShimmerCard({
    super.key,
    this.aspectRatio = 9 / 16,
    this.borderRadius = 6,
  });

  final double aspectRatio;
  final double borderRadius;

  @override
  State<ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<ShimmerCard>
    with SingleTickerProviderStateMixin {
  static const Color _base = Color(0xFF2A1818);
  static const Color _highlight = Color(0xFF3A2818);

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          // shift from -1 to 1 across the bar
          final shift = _ctrl.value * 2 - 1;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              gradient: LinearGradient(
                begin: Alignment(-1 + shift * 2, -0.5),
                end: Alignment(1 + shift * 2, 0.5),
                colors: const [_base, _highlight, _base],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Grid de cards shimmer — útil cuando aún no llega el catálogo.
class ShimmerCardGrid extends StatelessWidget {
  const ShimmerCardGrid({
    super.key,
    this.count = 6,
    this.crossAxisCount = 2,
    this.spacing = 8,
    this.aspectRatio = 9 / 16,
  });

  final int count;
  final int crossAxisCount;
  final double spacing;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: aspectRatio,
      ),
      itemBuilder: (_, __) => ShimmerCard(aspectRatio: aspectRatio),
    );
  }
}
