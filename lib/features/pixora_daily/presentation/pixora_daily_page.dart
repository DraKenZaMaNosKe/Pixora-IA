import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/analytics_service.dart';
import '../../../core/services/auto_rotate_service.dart';
import '../../../core/services/catalog_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/wallpaper_engine_coordinator.dart';
import '../../../core/utils/locale_helper.dart';
import '../../../core/widgets/offline_modal.dart';
import 'widgets/daily_activation_overlay.dart';

/// Pixora Daily — Synthwave Daily layout (concept #03, Eduardo 2026-05-16).
///
/// Background: deep purple→magenta gradient + scanlines CRT + horizon-grid
/// floor cyan. Header: Orbitron Tron-style title with chromatic aberration.
/// Carousel: 3 thumbs each with its own neon ring (pink/cyan/yellow). Menu
/// rows: dark translucent cards with per-row neon outline + glow. CTA:
/// arcade button. Category sheet: neon panel with active-row highlight.
class PixoraDailyPage extends StatefulWidget {
  const PixoraDailyPage({super.key});

  @override
  State<PixoraDailyPage> createState() => _PixoraDailyPageState();
}

class _PixoraDailyPageState extends State<PixoraDailyPage>
    with WidgetsBindingObserver {
  // ── Synthwave palette ───────────────────────────────────────────
  static const _neonPink = Color(0xFFFF2BD6);
  static const _neonCyan = Color(0xFF00F0FF);
  static const _neonYellow = Color(0xFFFFE44D);
  static const _bgTop = Color(0xFF1A0033);
  static const _bgMid = Color(0xFF3D0066);
  static const _bgDeep = Color(0xFF7A0099);

  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;
  int _intervalMinutes = 30;
  int _target = 2;
  String? _category;
  int _cachedCount = 0;
  String _cacheSize = '0.0';
  List<String> _previewUrls = const [];
  // Fase 3 — true cuando Daily está habilitado pero Pixora YA NO es el live
  // wallpaper activo (el usuario/Samsung lo revirtió). La rotación in-service
  // no puede correr en ese estado; mostramos un banner para reactivar.
  bool _componentLost = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.instance.track('pixora_daily_opened');
    _loadStatus();
    _loadPreviewSamples();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver del picker de live wallpaper (Fase 3), recargar estado para
    // que el banner de reactivación desaparezca si el componente ya volvió.
    if (state == AppLifecycleState.resumed) {
      _loadStatus();
    }
  }

  Future<void> _loadStatus() async {
    final status = await AutoRotateService.instance.getStatus();
    final enabled = status['enabled'] == true;
    // Si Daily está activo, verificar que Pixora siga siendo el live wallpaper.
    // Si no lo es, el componente se perdió y la rotación no puede correr.
    final componentLost = enabled
        ? !(await AutoRotateService.instance.isPixoraLiveActive())
        : false;
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _intervalMinutes = status['intervalMinutes'] as int? ?? 30;
      _target = status['target'] as int? ?? 2;
      _category = status['category'] as String?;
      _cachedCount = status['cachedCount'] as int? ?? 0;
      _cacheSize = status['cacheSizeMB'] as String? ?? '0.0';
      _componentLost = componentLost;
      _loading = false;
    });
  }

  Future<void> _reactivate() async {
    AnalyticsService.instance.track('pixora_daily_reactivate');
    await AutoRotateService.instance.reactivateLiveWallpaper();
    // El picker se abre; al volver a la app recargamos el estado.
  }

  Future<void> _loadPreviewSamples() async {
    try {
      final catalog = await CatalogService.instance.fetchCatalog();
      if (!mounted || catalog.isEmpty) return;
      final picks = (catalog.toList()..shuffle()).take(3).toList();
      setState(() {
        _previewUrls = picks.map((w) => w.previewUrl).toList();
      });
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    AnalyticsService.instance.track(
      _enabled ? 'pixora_daily_disabled' : 'pixora_daily_enabled',
      {
        'interval_min': _intervalMinutes,
        'target': _target,
        'category': _category ?? 'all'
      },
    );
    if (_enabled) {
      await AutoRotateService.instance.stop();
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _busy = false;
      });
    } else {
      // Pre-check: si está offline + cache vacío, mostrar el Holographic
      // modal en vez de fallar silenciosamente. Si está cached, dejar pasar
      // (el primer tick puede recuperar desde el cache local).
      if (!ConnectivityService.instance.isOnline) {
        final cacheDir = await getApplicationDocumentsDirectory();
        final autoRotateCache = Directory('${cacheDir.path}/auto_rotate_cache');
        final cached = autoRotateCache.existsSync() &&
            autoRotateCache
                .listSync()
                .whereType<File>()
                .where((f) => !f.path.endsWith('.tmp') && f.lengthSync() > 0)
                .isNotEmpty;
        if (!cached) {
          if (!mounted) return;
          setState(() => _busy = false);
          final retried = await OfflineModal.show(context, isAutoRotate: true);
          if (retried != true) return;
          setState(() => _busy = true);
        }
      }
      // Show the synthwave activation overlay BEFORE kicking off the
      // AutoRotateService.start(). The overlay auto-closes after 3s and
      // calls our onComplete callback, which then runs the real start +
      // shows the success snackbar.
      // Eduardo's request 2026-05-17: full-screen synthwave transition with
      // moving grid lines at the moment of activation.
      final route = PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => DailyActivationOverlay(
          intervalLabel: _intervalLabel(_intervalMinutes),
          onComplete: () async {
            final ok = await AutoRotateService.instance.start(
              intervalMinutes: _intervalMinutes,
              target: _target,
              category: _category,
            );
            if (!mounted) return;
            setState(() {
              _enabled = ok;
              _busy = false;
            });
            if (ok) {
              final preempted = AutoRotateService.instance.lastPreempted;
              final preemptedMsg = preempted == WallpaperEngine.none
                  ? ''
                  : LocaleHelper.pick(
                      es: ' · Reemplazó ${WallpaperEngineCoordinator.labelEs(preempted)}',
                      en: ' · Replaced ${WallpaperEngineCoordinator.labelEs(preempted)}',
                    );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(LocaleHelper.pick(
                    es: '✨ Daily ACTIVO · cada ${_intervalLabel(_intervalMinutes)}$preemptedMsg',
                    en: '✨ Daily ACTIVE · every ${_intervalLabel(_intervalMinutes)}$preemptedMsg',
                  )),
                  backgroundColor: _neonPink,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              );
            }
          },
        ),
        transitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      );
      // ignore: use_build_context_synchronously
      Navigator.of(context).push(route);
    }
  }

  Future<void> _pickInterval() async {
    // La rotación ocurre al desbloquear el cel (on-wake). El intervalo es el
    // MÍNIMO de tiempo entre cambios: si desbloqueas antes de que pase, no
    // rota; si ya pasó, el siguiente desbloqueo trae fondo nuevo.
    final v = await _showSynthSheet<int>(
      title: LocaleHelper.pick(es: 'CAMBIAR CADA', en: 'CHANGE EVERY'),
      items: [
        (0, LocaleHelper.pick(es: 'Cada desbloqueo', en: 'Every unlock')),
        (30, LocaleHelper.pick(es: '30 minutos', en: '30 minutes')),
        (60, LocaleHelper.pick(es: '1 hora', en: '1 hour')),
        (180, LocaleHelper.pick(es: '3 horas', en: '3 hours')),
        (360, LocaleHelper.pick(es: '6 horas', en: '6 hours')),
        (720, LocaleHelper.pick(es: '12 horas', en: '12 hours')),
        (1440, LocaleHelper.pick(es: 'Una vez al día', en: 'Once a day')),
      ],
      current: _intervalMinutes,
      accent: _neonPink,
    );
    if (v != null && v != _intervalMinutes) {
      setState(() => _intervalMinutes = v);
      if (_enabled) await _restart();
    }
  }

  Future<void> _pickTarget() async {
    final v = await _showSynthSheet<int>(
      title: LocaleHelper.pick(es: 'APLICAR A', en: 'APPLY TO'),
      items: [
        (0, LocaleHelper.pick(es: 'Pantalla principal', en: 'Home screen')),
        (1, LocaleHelper.pick(es: 'Pantalla de bloqueo', en: 'Lock screen')),
        (2, LocaleHelper.pick(es: 'Ambas pantallas', en: 'Both screens')),
      ],
      current: _target,
      accent: _neonCyan,
    );
    if (v != null && v != _target) {
      setState(() => _target = v);
      if (_enabled) await _restart();
    }
  }

  Future<void> _pickCategory() async {
    final v = await _showSynthSheet<String?>(
      title: LocaleHelper.pick(es: 'CATEGORÍA', en: 'CATEGORY'),
      items: [
        (
          null,
          LocaleHelper.pick(es: 'Todas las categorías', en: 'All categories'),
        ),
        (
          'DAILY',
          LocaleHelper.pick(
              es: 'Pixora Daily (curado)', en: 'Pixora Daily (curated)'),
        ),
        (
          'PANORAMIC',
          LocaleHelper.pick(es: 'Solo panorámicos', en: 'Panoramic only'),
        ),
        ('NATURE', LocaleHelper.pick(es: 'Naturaleza', en: 'Nature')),
        ('ANIME', 'Anime'),
        ('GAMING', 'Gaming'),
        ('SCIFI', 'Sci-Fi'),
        ('FANTASY', LocaleHelper.pick(es: 'Fantasía', en: 'Fantasy')),
        ('CULTURE', LocaleHelper.pick(es: 'Cultura', en: 'Culture')),
        ('CALENDAR', LocaleHelper.pick(es: 'Calendarios', en: 'Calendar')),
      ],
      current: _category,
      accent: _neonYellow,
    );
    if (v != _category) {
      setState(() => _category = v);
      if (_enabled) await _restart();
    }
  }

  Future<T?> _showSynthSheet<T>({
    required String title,
    required List<(T, String)> items,
    required T current,
    required Color accent,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SynthSheet<T>(
        title: title,
        items: items,
        current: current,
        accent: accent,
      ),
    );
  }

  Future<void> _restart() async {
    await AutoRotateService.instance.stop();
    final ok = await AutoRotateService.instance.start(
      intervalMinutes: _intervalMinutes,
      target: _target,
      category: _category,
    );
    if (mounted) setState(() => _enabled = ok);
  }

  String _intervalLabel(int m) {
    if (m <= 0) {
      return LocaleHelper.pick(es: 'cada desbloqueo', en: 'every unlock');
    }
    if (m < 60) return '$m min';
    if (m < 1440) {
      final h = m ~/ 60;
      return '$h h';
    }
    return LocaleHelper.pick(es: 'al día', en: 'a day');
  }

  String _targetLabel(int t) => switch (t) {
        0 => LocaleHelper.pick(es: 'Principal', en: 'Home'),
        1 => LocaleHelper.pick(es: 'Bloqueo', en: 'Lock'),
        _ => LocaleHelper.pick(es: 'Ambas', en: 'Both'),
      };

  String _categoryLabel(String? c) {
    if (c == null) return LocaleHelper.pick(es: 'Todas', en: 'All');
    return switch (c) {
      'PANORAMIC' => LocaleHelper.pick(es: 'Panorámicos', en: 'Panoramic'),
      'NATURE' => LocaleHelper.pick(es: 'Naturaleza', en: 'Nature'),
      'ANIME' => 'Anime',
      'GAMING' => 'Gaming',
      'SCIFI' => 'Sci-Fi',
      'FANTASY' => LocaleHelper.pick(es: 'Fantasía', en: 'Fantasy'),
      'CULTURE' => LocaleHelper.pick(es: 'Cultura', en: 'Culture'),
      _ => c,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgTop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _neonCyan),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Layer 1: gradient background
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_bgTop, _bgMid, _bgDeep, _neonPink],
                  stops: [0.0, 0.4, 0.8, 1.0],
                ),
              ),
            ),
          ),
          // Layer 2: horizon-grid floor bottom
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 220,
            child: IgnorePointer(child: _HorizonGrid()),
          ),
          // Layer 3: scanlines
          const Positioned.fill(
            child: IgnorePointer(child: _Scanlines()),
          ),
          // Layer 4: content
          _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: _neonCyan, strokeWidth: 2),
                )
              : SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 80, bottom: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),
                        if (_componentLost) ...[
                          const SizedBox(height: 12),
                          _buildReactivateBanner(),
                        ],
                        const SizedBox(height: 14),
                        _buildCarousel(),
                        const SizedBox(height: 20),
                        _buildRows(),
                        if (_enabled) ...[
                          const SizedBox(height: 12),
                          _buildStatsCard(),
                        ],
                        const SizedBox(height: 20),
                        _buildPrimaryCta(),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  /// Fase 3 — banner cuando Daily está activo pero Pixora dejó de ser el
  /// live wallpaper (el usuario o el sistema lo revirtió). Un tap reactiva.
  Widget _buildReactivateBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _neonPink.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _neonPink, width: 1),
          boxShadow: [
            BoxShadow(color: _neonPink.withValues(alpha: 0.3), blurRadius: 14),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _neonPink, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleHelper.pick(
                      es: 'Pixora Daily está en pausa',
                      en: 'Pixora Daily is paused',
                    ),
                    style: GoogleFonts.orbitron(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    LocaleHelper.pick(
                      es: 'Cambió tu fondo de pantalla. Toca para reactivar la rotación.',
                      en: 'Your wallpaper changed. Tap to resume rotation.',
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _reactivate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _neonPink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  LocaleHelper.pick(es: 'REACTIVAR', en: 'RESUME'),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PIXORA · DAILY',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
              color: _neonCyan,
              shadows: [
                Shadow(
                  color: _neonCyan.withValues(alpha: 0.7),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'PIXORA DAILY',
            style: GoogleFonts.orbitron(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.02 * 30,
              color: _neonYellow,
              height: 1.0,
              shadows: [
                const Shadow(
                  color: _neonPink,
                  offset: Offset(2, 0),
                ),
                const Shadow(
                  color: _neonCyan,
                  offset: Offset(-2, 0),
                ),
                Shadow(
                  color: _neonYellow.withValues(alpha: 0.65),
                  blurRadius: 14,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            LocaleHelper.pick(
              es: 'Tu pantalla, viva todo el día',
              en: 'Your screen, alive all day',
            ),
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w400,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarousel() {
    final urls = _previewUrls;
    final colors = [_neonPink, _neonCyan, _neonYellow];
    return SizedBox(
      height: 110,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: List.generate(3, (i) {
            final hasImage = i < urls.length;
            final color = colors[i];
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 7 : 0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.55),
                        blurRadius: 18,
                      ),
                    ],
                    border: Border.all(color: color, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: hasImage
                        ? Image.network(
                            urls[i],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: const Color(0xFF1A0033)),
                          )
                        : Container(color: const Color(0xFF1A0033)),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildRows() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          _synthRow(
            color: _neonPink,
            icon: '⏱',
            label: LocaleHelper.pick(es: 'FRECUENCIA', en: 'FREQUENCY'),
            value: _intervalLabel(_intervalMinutes).toUpperCase(),
            onTap: _pickInterval,
          ),
          const SizedBox(height: 8),
          _synthRow(
            color: _neonCyan,
            icon: '◳',
            label: LocaleHelper.pick(es: 'APLICAR A', en: 'APPLY TO'),
            value: _targetLabel(_target).toUpperCase(),
            onTap: _pickTarget,
          ),
          const SizedBox(height: 8),
          _synthRow(
            color: _neonYellow,
            icon: '★',
            label: LocaleHelper.pick(es: 'CATEGORÍA', en: 'CATEGORY'),
            value: _categoryLabel(_category).toUpperCase(),
            onTap: _pickCategory,
          ),
        ],
      ),
    );
  }

  Widget _synthRow({
    required Color color,
    required String icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0A001E).withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 1.5),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 14),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  icon,
                  style: GoogleFonts.orbitron(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                    shadows: [
                      Shadow(
                          color: color.withValues(alpha: 0.7), blurRadius: 6),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.orbitron(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                value,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.88),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right,
                  size: 16, color: Colors.white.withValues(alpha: 0.55)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _neonCyan.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _neonCyan, width: 1),
          boxShadow: [
            BoxShadow(color: _neonCyan.withValues(alpha: 0.35), blurRadius: 12),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: _neonCyan, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleHelper.pick(es: 'DAILY ACTIVO', en: 'DAILY ACTIVE'),
                    style: GoogleFonts.orbitron(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _neonCyan,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_cachedCount cached · $_cacheSize MB',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.6),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryCta() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _busy ? null : _toggle,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _neonPink.withValues(alpha: 0.55),
                  _neonCyan.withValues(alpha: 0.55),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _neonYellow, width: 2),
              boxShadow: [
                BoxShadow(
                  color: _neonYellow.withValues(alpha: 0.45),
                  blurRadius: 24,
                ),
                BoxShadow(
                  color: _neonPink.withValues(alpha: 0.30),
                  blurRadius: 18,
                  spreadRadius: -4,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _neonYellow,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _enabled
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 20,
                        color: _neonYellow,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _enabled
                            ? LocaleHelper.pick(
                                es: 'PAUSAR DAILY', en: 'PAUSE DAILY')
                            : LocaleHelper.pick(
                                es: 'ACTIVAR DAILY', en: 'ENABLE DAILY'),
                        style: GoogleFonts.orbitron(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _neonYellow,
                          letterSpacing: 2.0,
                          shadows: [
                            Shadow(
                              color: _neonYellow.withValues(alpha: 0.85),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Horizon grid floor — perspective-rotated cyan grid
// ═════════════════════════════════════════════════════════════════════
class _HorizonGrid extends StatelessWidget {
  const _HorizonGrid();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _HorizonGridPainter());
  }
}

class _HorizonGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cyan = Color(0xFF00F0FF);
    // Vertical lines fan out from horizon (top center) to bottom edges
    final vPaint = Paint()
      ..color = cyan.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final hPaint = Paint()
      ..color = cyan.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    final vanish = Offset(size.width / 2, 0);
    for (var i = -10; i <= 10; i++) {
      final endX = size.width / 2 + (i * size.width * 0.18);
      canvas.drawLine(vanish, Offset(endX, size.height), vPaint);
    }
    // Horizontal lines with perspective spacing (closer at top)
    for (var i = 1; i <= 8; i++) {
      final t = math.pow(i / 8, 2).toDouble();
      final y = t * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hPaint);
    }
    // Bottom cyan glow overlay
    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          cyan.withValues(alpha: 0.12),
          cyan.withValues(alpha: 0.22),
        ],
        stops: const [0, 0.3, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═════════════════════════════════════════════════════════════════════
// Scanlines overlay (CRT effect)
// ═════════════════════════════════════════════════════════════════════
class _Scanlines extends StatefulWidget {
  const _Scanlines();
  @override
  State<_Scanlines> createState() => _ScanlinesState();
}

class _ScanlinesState extends State<_Scanlines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return CustomPaint(
          painter: _ScanlinesPainter(offset: _c.value * 4),
        );
      },
    );
  }
}

class _ScanlinesPainter extends CustomPainter {
  _ScanlinesPainter({required this.offset});
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.18);
    for (var y = offset; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinesPainter old) => old.offset != offset;
}

// ═════════════════════════════════════════════════════════════════════
// Synthwave bottom sheet picker
// ═════════════════════════════════════════════════════════════════════
class _SynthSheet<T> extends StatelessWidget {
  const _SynthSheet({
    required this.title,
    required this.items,
    required this.current,
    required this.accent,
  });
  final String title;
  final List<(T, String)> items;
  final T current;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.75;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0A001E).withValues(alpha: 0.96),
            const Color(0xFF3C005A).withValues(alpha: 0.96),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: accent, width: 2),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.40),
            blurRadius: 30,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top dragger
              Center(
                child: Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  title,
                  style: GoogleFonts.orbitron(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 1.6,
                    shadows: [
                      Shadow(
                          color: accent.withValues(alpha: 0.7), blurRadius: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (val, label) in items)
                        _SheetRow<T>(
                          value: val,
                          label: label,
                          isActive: val == current,
                          accent: accent,
                          onTap: () => Navigator.pop(context, val),
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

class _SheetRow<T> extends StatelessWidget {
  const _SheetRow({
    required this.value,
    required this.label,
    required this.isActive,
    required this.accent,
    required this.onTap,
  });
  final T value;
  final String label;
  final bool isActive;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: isActive ? accent.withValues(alpha: 0.12) : null,
            border: Border(
              left: BorderSide(
                color: isActive ? accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: GoogleFonts.orbitron(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (isActive) Icon(Icons.check_rounded, color: accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
