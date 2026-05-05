import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/design/hud_tokens.dart';

/// Full-screen modal shown right after the guided tour completes — invites
/// the user to claim a free ad-free install ("Welcome Gift"). The actual
/// grace flag was already set in GracePassService at app first-launch; this
/// sheet just nudges the user to spend it on a great wallpaper while
/// explaining the value.
///
/// Two outcomes:
///   - "Aplicar Volcano Dragon" → caller routes to that detail page; install
///     consumes the grace via AdService normally.
///   - "Más tarde" → caller closes the sheet; grace remains active until
///     the user's next install (any wallpaper).
class WelcomeGiftSheet extends StatelessWidget {
  const WelcomeGiftSheet({
    super.key,
    required this.featuredName,
    required this.featuredSubtitle,
    required this.featuredPreviewUrl,
    required this.onAcceptGift,
    required this.onLater,
  });

  /// Display name shown on the gift card (e.g. "Volcano Dragon").
  final String featuredName;

  /// Short tagline ("Escena 3D con dragón ancestral · canvas_scene").
  final String featuredSubtitle;

  /// Network URL used to render the preview thumbnail.
  final String featuredPreviewUrl;

  /// Called when the user accepts the gift — caller should navigate to the
  /// preview/install flow for the featured wallpaper.
  final VoidCallback onAcceptGift;

  /// Called when the user defers the gift. Caller should just dismiss.
  final VoidCallback onLater;

  /// Convenience launcher — call from anywhere with a BuildContext to show
  /// the sheet as a full-screen non-dismissible modal route.
  static Future<void> show(
    BuildContext context, {
    required String featuredName,
    required String featuredSubtitle,
    required String featuredPreviewUrl,
    required VoidCallback onAcceptGift,
    required VoidCallback onLater,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => WelcomeGiftSheet(
          featuredName: featuredName,
          featuredSubtitle: featuredSubtitle,
          featuredPreviewUrl: featuredPreviewUrl,
          onAcceptGift: onAcceptGift,
          onLater: onLater,
        ),
        transitionsBuilder: (_, animation, __, child) {
          final curve =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curve),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    // Wrap the whole dialog in a vertically scrolling box so it never
    // overflows on shorter phones (e.g. Samsung A-series with a tall system
    // nav bar). The dialog is normally ~580dp tall; on a 700dp safe-area
    // device it fits, but on a 600dp one it would overflow by ~80–280px,
    // which is exactly what we saw in logcat.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: h.bg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: h.accent.withValues(alpha: 0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: h.accent.withValues(alpha: 0.18),
                    blurRadius: 40,
                    spreadRadius: -10,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Gift ribbon header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          h.accent,
                          h.accent2,
                        ],
                      ),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(22)),
                    ),
                    width: double.infinity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🎁', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Text(
                          'REGALO DE BIENVENIDA',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.8,
                            color: h.isDark ? Colors.black : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Preview + name
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              featuredPreviewUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, progress) =>
                                  progress == null
                                      ? child
                                      : Container(
                                          color: h.surface,
                                          alignment: Alignment.center,
                                          child: SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                                color: h.accent,
                                                strokeWidth: 2),
                                          ),
                                        ),
                              errorBuilder: (_, __, ___) => Container(
                                color: h.surface,
                                alignment: Alignment.center,
                                child: Icon(Icons.image_outlined,
                                    color: h.textDim, size: 36),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          featuredName,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.fraunces(
                            fontSize: 26,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            color: h.text,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          featuredSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w300,
                            color: h.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Body explanation
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                    child: Text(
                      'Tu primer wallpaper va por la casa. Sin anuncios, sin créditos. Si después decides instalar otro, ese también será gratis si no aceptas el de hoy.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.fraunces(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: h.text.withValues(alpha: 0.85),
                        height: 1.5,
                      ),
                    ),
                  ),

                  // CTAs
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: onAcceptGift,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: h.accent,
                              foregroundColor:
                                  h.isDark ? Colors.black : Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.play_arrow_rounded, size: 22),
                                const SizedBox(width: 6),
                                Text(
                                  'Aplicar $featuredName',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: onLater,
                          child: Text(
                            'Más tarde',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: h.textDim,
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
      ),
    );
  }
}
