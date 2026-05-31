import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/design/hud_tokens.dart';
import '../../../../core/widgets/aurora_waves_loading.dart';
import '../../../../core/widgets/section_hero_banner.dart';
import '../../data/realm_shader.dart';
import '../../services/realm_apply_service.dart';

/// REALM shader card — mirrors `_LiveWallpaperCard` styling (preview top,
/// dark strip bottom with name + meta) so VIDEO/SHADER/CLOCK cards look
/// like siblings inside the LIVE tab grid. Tap invokes the system
/// wallpaper picker via `RealmApplyService` after pre-caching the .glsl
/// to avoid the black-flash window.
class RealmCard extends StatelessWidget {
  final RealmShader shader;
  final double width;
  final double height;

  const RealmCard({
    super.key,
    required this.shader,
    required this.width,
    required this.height,
  });

  Future<void> _onTap(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final hud = context.hud;
    messenger.showSnackBar(SnackBar(
      content: Text('Preparando ${shader.name}…',
          style: const TextStyle(fontSize: 13)),
      backgroundColor: hud.surface,
      duration: const Duration(seconds: 2),
    ));
    final ok = await RealmApplyService.instance.apply(shader);
    if (!ok) {
      messenger.showSnackBar(SnackBar(
        content: const Text('No se pudo abrir el wallpaper'),
        backgroundColor: hud.surface,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;

    return SizedBox(
      width: width.isFinite ? width : null,
      height: height.isFinite ? height : null,
      child: GestureDetector(
        onTap: () => _onTap(context),
        child: Container(
          decoration: BoxDecoration(
            color: h.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isIos
                  ? Colors.black.withValues(alpha: 0.06)
                  : HudTokens.gold.withValues(alpha: 0.20),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Preview (full bleed) ─────────────────────────────
              CachedNetworkImage(
                imageUrl: shader.previewUrl,
                fit: BoxFit.cover,
                memCacheWidth: 400,
                placeholder: (_, __) => const AuroraWavesLoading(),
                errorWidget: (_, __, ___) => Container(
                  color: h.surface,
                  child: Icon(
                    shader.category == RealmCategory.clock
                        ? Icons.access_time
                        : Icons.auto_awesome,
                    color: h.accent,
                    size: 40,
                  ),
                ),
              ),

              // ── SHADER / CLOCK badge top-right ───────────────────
              Positioned(
                top: 6,
                right: 6,
                child: HoloFoilPill(
                  label: shader.category == RealmCategory.clock
                      ? 'CLOCK'
                      : 'SHADER',
                  size: HoloFoilPillSize.mini,
                ),
              ),

              // ── Bottom strip with name + NEW badge ──────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isIos
                          ? [
                              Colors.black.withValues(alpha: 0.0),
                              Colors.black.withValues(alpha: 0.92),
                            ]
                          : [
                              const Color(0xFF070710).withValues(alpha: 0.0),
                              const Color(0xFF070710).withValues(alpha: 0.97),
                            ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              shader.name,
                              style: const TextStyle(
                                fontFamily: 'JetBrainsMono',
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (shader.badge != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: h.accent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                shader.badge!,
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
