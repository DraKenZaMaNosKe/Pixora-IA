import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/hud_tokens.dart';
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
    final h = context.hud;
    // iOS White theme uses "Apple Blue Filled" — picked by user 2026-05-06
    // for high contrast on white app bg. Black & Gold keeps the original
    // gold/blue gradient (it has proper contrast over the dark background).
    final isLight = !h.isDark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PixoraDailyPage()),
            );
            _loadStatus();
          },
          borderRadius: BorderRadius.circular(16),
          child: isLight ? _buildLightTheme() : _buildDarkTheme(),
        ),
      ),
    );
  }

  /// iOS White theme — Apple Premium (concept #01, 2026-05-15).
  /// 135° gradient #0A84FF → #0066CC, translucent white pills, white text,
  /// large blue glow shadow. Matches the rest of the Apple Premium iOS HOME
  /// tokens (hero pill, NEW badges) for full coherence.
  Widget _buildLightTheme() {
    const appleBlue = Color(0xFF0A84FF);
    const appleBlueDeep = Color(0xFF0066CC);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [appleBlue, appleBlueDeep],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: appleBlue.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
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
                    const Text(
                      'Pixora Daily',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.05,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _enabled ? 'ACTIVO' : 'NUEVO',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: Colors.white,
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
                          es: 'Wallpapers aleatorios',
                          en: 'Random wallpapers',
                        ),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.white.withValues(alpha: 0.7),
            size: 22,
          ),
        ],
      ),
    );
  }

  /// Black & Gold theme — Concept #01 "Strict Black & Gold" (2026-05-15).
  /// Always gold accent (no more blue when ACTIVO). Coherente con dashboard
  /// + LIVE hero. El "ACTIVO" / "NUEVO" pill ahora es gold también — el
  /// dot pulsante distingue estado, no el color.
  Widget _buildDarkTheme() {
    const goldDeep = Color(0xFFD9B14A);
    const goldBright = Color(0xFFF5D676);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            goldDeep.withValues(alpha: 0.18),
            const Color(0xFF8A7A56).withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: goldDeep.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [goldDeep, goldBright],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: goldDeep.withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.autorenew_rounded,
              color: Color(0xFF070710),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: goldDeep.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: _enabled
                            ? Border.all(
                                color: goldBright.withValues(alpha: 0.6),
                                width: 0.5,
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_enabled) ...[
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: goldBright,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: goldBright,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _enabled ? 'ACTIVO' : 'NUEVO',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: goldBright,
                            ),
                          ),
                        ],
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
                          es: 'Wallpapers aleatorios',
                          en: 'Random wallpapers',
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
            color: goldBright.withValues(alpha: 0.7),
            size: 22,
          ),
        ],
      ),
    );
  }
}
