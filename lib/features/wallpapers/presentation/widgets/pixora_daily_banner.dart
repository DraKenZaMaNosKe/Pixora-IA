import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/auto_rotate_service.dart';
import '../../../../core/services/wallpaper_engine_coordinator.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../pixora_daily/presentation/pixora_daily_page.dart';

/// Featured banner card on the Wallpapers home that drives discovery of
/// Pixora Daily — the auto-rotating wallpaper feature that competes with
/// Bing Spotlight on Windows.
///
/// Sits right after the HeroBanner. Tapping opens the dedicated
/// `PixoraDailyPage` where the user can configure interval / target /
/// category and toggle on.
///
/// Reactive to `WallpaperEngineCoordinator` so the copy updates between
/// "Activar Daily" (when off) and "Daily activo · cada X" (when on).
class PixoraDailyBanner extends StatefulWidget {
  const PixoraDailyBanner({super.key});

  @override
  State<PixoraDailyBanner> createState() => _PixoraDailyBannerState();
}

class _PixoraDailyBannerState extends State<PixoraDailyBanner> {
  bool _enabled = false;
  int _intervalMinutes = 0;

  @override
  void initState() {
    super.initState();
    WallpaperEngineCoordinator.instance.addListener(_onEngineChanged);
    _loadStatus();
  }

  @override
  void dispose() {
    WallpaperEngineCoordinator.instance.removeListener(_onEngineChanged);
    super.dispose();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final s = await AutoRotateService.instance.getStatus();
    if (!mounted) return;
    setState(() {
      _enabled = s['enabled'] == true;
      _intervalMinutes = s['intervalMinutes'] as int? ?? 30;
    });
  }

  String _intervalLabel(int m) {
    if (m < 60) return '$m min';
    if (m < 1440) return '${m ~/ 60} h';
    return '24 h';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PixoraDailyPage()),
            );
            // The coordinator notifies on engine change too, but force a
            // refresh in case the user changed config without toggling.
            _loadStatus();
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _enabled
                    ? [
                        const Color(0xFF0A84FF).withValues(alpha: 0.18),
                        const Color(0xFF0072E0).withValues(alpha: 0.10),
                      ]
                    : [
                        const Color(0xFFD9B14A).withValues(alpha: 0.18),
                        const Color(0xFF8A7A56).withValues(alpha: 0.08),
                      ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _enabled
                    ? const Color(0xFF0A84FF).withValues(alpha: 0.45)
                    : const Color(0xFFD9B14A).withValues(alpha: 0.45),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _enabled
                          ? [
                              const Color(0xFF0A84FF),
                              const Color(0xFF0072E0),
                            ]
                          : [
                              const Color(0xFFD9B14A),
                              const Color(0xFFF5D676),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (_enabled
                                ? const Color(0xFF0A84FF)
                                : const Color(0xFFD9B14A))
                            .withValues(alpha: 0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.autorenew_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Pixora Daily',
                            style: GoogleFonts.fraunces(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.italic,
                              color: Colors.white,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (_enabled)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF34D399)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFF34D399)
                                      .withValues(alpha: 0.5),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                'ACTIVO',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: const Color(0xFF34D399),
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9B14A)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'NUEVO',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: const Color(0xFFD9B14A),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _enabled
                            ? LocaleHelper.pick(
                                es: 'Cambia cada ${_intervalLabel(_intervalMinutes)}',
                                en: 'Changes every ${_intervalLabel(_intervalMinutes)}',
                              )
                            : LocaleHelper.pick(
                                es: 'Tu pantalla cambia sola, como Bing Spotlight',
                                en: 'Your screen changes itself, like Bing Spotlight',
                              ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.7),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
