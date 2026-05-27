import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// M03 — Login Avatar Morph.
///
/// Avatar genérico (skeleton) que se transforma en el avatar real del
/// usuario con scale + glow cuando llega del backend (post Google Sign-In).
/// Transición de 600ms con elastic out — comunica "ya eres tú".
///
/// Diseño del mockup `docs/design/microinteractions_showroom.html` (M03).
class LoginAvatarMorph extends StatelessWidget {
  const LoginAvatarMorph({
    super.key,
    required this.avatarUrl,
    this.size = 80,
  });

  /// `null` o vacío = mostrar skeleton genérico.
  /// URL válida = transición a la imagen real.
  final String? avatarUrl;
  final double size;

  static const Color _amberBright = Color(0xFFFFD66B);
  static const Color _gold = Color(0xFFC9A650);
  static const Color _rust = Color(0xFFC77A3B);

  @override
  Widget build(BuildContext context) {
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Skeleton (siempre presente, se fade-out cuando hay url)
          AnimatedOpacity(
            opacity: hasUrl ? 0 : 1,
            duration: const Duration(milliseconds: 600),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A2018), Color(0xFF1A1208)],
                ),
                border: Border.all(
                  color: _amberBright.withValues(alpha: 0.2),
                ),
              ),
              child: Center(
                child: Container(
                  width: size * 0.4,
                  height: size * 0.4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _amberBright.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ),
          ),
          // Avatar real (fade-in + scale-up cuando aparece)
          AnimatedScale(
            scale: hasUrl ? 1.0 : 0.6,
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            child: AnimatedOpacity(
              opacity: hasUrl ? 1 : 0,
              duration: const Duration(milliseconds: 600),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _amberBright, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _amberBright.withValues(alpha: 0.6),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: hasUrl
                      ? CachedNetworkImage(
                          imageUrl: avatarUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: _gold.withValues(alpha: 0.3),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [_gold, _rust],
                              ),
                            ),
                          ),
                        )
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_gold, _rust],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
