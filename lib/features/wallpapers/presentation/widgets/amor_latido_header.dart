import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Header "AM♥R" de la sección Amor — skin **Latido** (Eduardo 2026-07-05).
///
/// Poster tipográfico: la palabra AMOR en Anton gigante rojo profundo con
/// un corazón que late de verdad en medio (reemplaza la O). Debajo, el
/// lema "sin miedo a sentir" en serif itálica y un filete rojo corto.
///
/// Elegido entre 5 propuestas de skin (mockup amor_skins.html). Unisex por
/// diseño: rojo #D93A3A sobre negro, cero rosa pastel — streetwear con
/// actitud, funciona para él y para ella.
class AmorLatidoHeader extends StatefulWidget {
  const AmorLatidoHeader({super.key});

  static const red = Color(0xFFD93A3A);
  static const heartRed = Color(0xFFE8654E);
  static const bone = Color(0xFFF5F0E8);

  @override
  State<AmorLatidoHeader> createState() => _AmorLatidoHeaderState();
}

class _AmorLatidoHeaderState extends State<AmorLatidoHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat;

  @override
  void initState() {
    super.initState();
    _beat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  /// Latido cardiaco de dos golpes (lub-dub) como en el mockup CSS:
  /// 0% → 1.0 · 14% → 1.18 · 28% → 1.0 · 42% → 1.1 · 100% → 1.0
  double _beatScale(double t) {
    if (t < 0.14) {
      return 1.0 + 0.18 * (t / 0.14);
    } else if (t < 0.28) {
      return 1.18 - 0.18 * ((t - 0.14) / 0.14);
    } else if (t < 0.42) {
      return 1.0 + 0.10 * ((t - 0.28) / 0.14);
    } else if (t < 0.56) {
      return 1.10 - 0.10 * ((t - 0.42) / 0.14);
    }
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final anton = GoogleFonts.anton(
      fontSize: 54,
      height: 0.9,
      letterSpacing: 0.5,
      color: AmorLatidoHeader.red,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('AM', style: anton),
              AnimatedBuilder(
                animation: _beat,
                builder: (_, __) => Transform.scale(
                  scale: _beatScale(_beat.value),
                  child: Text(
                    '♥',
                    style: anton.copyWith(
                      color: AmorLatidoHeader.heartRed,
                      fontSize: 46,
                    ),
                  ),
                ),
              ),
              Text('R', style: anton),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'sin miedo a sentir',
            style: GoogleFonts.fraunces(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: AmorLatidoHeader.bone,
            ),
          ),
          const SizedBox(height: 10),
          Container(width: 54, height: 3, color: AmorLatidoHeader.red),
        ],
      ),
    );
  }
}
