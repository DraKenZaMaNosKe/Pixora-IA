import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/services/analytics_service.dart';
import '../../../core/services/auto_rotate_service.dart';
import '../../../core/services/catalog_service.dart';
import '../../../core/services/wallpaper_engine_coordinator.dart';
import '../../../core/utils/locale_helper.dart';

/// Pixora Daily — dedicated page for the auto-rotating wallpaper feature.
///
/// Design: Apple TV Widget concept (#01 from `docs/design/pixora_daily_concepts.html`)
/// picked by user 2026-05-05. Pure black bg, stack carousel of 3 wallpapers,
/// 3 elegant rows for config (Frecuencia, Aplicar a, Categoría), big primary
/// CTA at bottom. Vibe: iOS Settings premium.
///
/// Replaces the previously-buried AutoRotate UI inside settings_page.dart.
/// The underlying service (AutoRotateService + native AutoRotateWorker) is
/// unchanged; this is a UX refactor for discoverability.
///
/// Section §16.X of master doc: "Pixora Daily — feature exception #1
/// to PRODUCTO_TERMINADO pact, 2026-05-05."
class PixoraDailyPage extends StatefulWidget {
  const PixoraDailyPage({super.key});

  @override
  State<PixoraDailyPage> createState() => _PixoraDailyPageState();
}

class _PixoraDailyPageState extends State<PixoraDailyPage> {
  static const _appleBlue = Color(0xFF0A84FF);
  static const _appleBlueDark = Color(0xFF0072E0);

  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;
  int _intervalMinutes = 30;
  int _target = 2; // 0=Home, 1=Lock, 2=Both
  String? _category; // null = all
  int _cachedCount = 0;
  String _cacheSize = '0.0';

  // 3 sample wallpaper URLs for the stack carousel preview. We pull these
  // from the live catalog so the user sees REAL content from his app.
  List<String> _previewUrls = const [];

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.track('pixora_daily_opened');
    _loadStatus();
    _loadPreviewSamples();
  }

  Future<void> _loadStatus() async {
    final status = await AutoRotateService.instance.getStatus();
    if (!mounted) return;
    setState(() {
      _enabled = status['enabled'] == true;
      _intervalMinutes = status['intervalMinutes'] as int? ?? 30;
      _target = status['target'] as int? ?? 2;
      _category = status['category'] as String?;
      _cachedCount = status['cachedCount'] as int? ?? 0;
      _cacheSize = status['cacheSizeMB'] as String? ?? '0.0';
      _loading = false;
    });
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
              es: '✨ Pixora Daily activo · cada ${_intervalLabel(_intervalMinutes)}$preemptedMsg',
              en: '✨ Pixora Daily active · every ${_intervalLabel(_intervalMinutes)}$preemptedMsg',
            )),
            backgroundColor: _appleBlue,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _pickInterval() async {
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PickerSheet<int>(
        title: LocaleHelper.pick(es: 'Frecuencia', en: 'Frequency'),
        items: const [
          (5, '5 min'),
          (15, '15 min'),
          (30, '30 min'),
          (60, '1 h'),
          (120, '2 h'),
          (360, '6 h'),
          (720, '12 h'),
          (1440, '24 h'),
        ],
        current: _intervalMinutes,
      ),
    );
    if (v != null && v != _intervalMinutes) {
      setState(() => _intervalMinutes = v);
      if (_enabled) await _restart();
    }
  }

  Future<void> _pickTarget() async {
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PickerSheet<int>(
        title: LocaleHelper.pick(es: 'Aplicar a', en: 'Apply to'),
        items: [
          (0, LocaleHelper.pick(es: 'Pantalla principal', en: 'Home screen')),
          (1, LocaleHelper.pick(es: 'Pantalla de bloqueo', en: 'Lock screen')),
          (2, LocaleHelper.pick(es: 'Ambas pantallas', en: 'Both screens')),
        ],
        current: _target,
      ),
    );
    if (v != null && v != _target) {
      setState(() => _target = v);
      if (_enabled) await _restart();
    }
  }

  Future<void> _pickCategory() async {
    final v = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled:
          true, // permite que el sheet sea más alto que la mitad
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PickerSheet<String?>(
        title: LocaleHelper.pick(es: 'Categoría', en: 'Category'),
        items: [
          (
            null,
            LocaleHelper.pick(es: 'Todas las categorías', en: 'All categories')
          ),
          (
            'DAILY',
            LocaleHelper.pick(
                es: 'Pixora Daily (curado)', en: 'Pixora Daily (curated)')
          ),
          (
            'PANORAMIC',
            LocaleHelper.pick(es: 'Solo panorámicos', en: 'Panoramic only')
          ),
          ('NATURE', LocaleHelper.pick(es: 'Naturaleza', en: 'Nature')),
          ('ANIME', 'Anime'),
          ('GAMING', 'Gaming'),
          ('SCIFI', LocaleHelper.pick(es: 'Sci-Fi', en: 'Sci-Fi')),
          ('FANTASY', LocaleHelper.pick(es: 'Fantasía', en: 'Fantasy')),
          ('CULTURE', LocaleHelper.pick(es: 'Cultura', en: 'Culture')),
          ('CALENDAR', LocaleHelper.pick(es: 'Calendarios', en: 'Calendar')),
        ],
        current: _category,
      ),
    );
    if (v != _category) {
      setState(() => _category = v);
      if (_enabled) await _restart();
    }
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
    if (m < 60) return '$m min';
    if (m < 1440) {
      final h = m ~/ 60;
      return LocaleHelper.pick(es: '$h h', en: '$h h');
    }
    return LocaleHelper.pick(es: '24 h', en: '24 h');
  }

  String _targetLabel(int t) => switch (t) {
        0 => LocaleHelper.pick(es: 'Pantalla principal', en: 'Home screen'),
        1 => LocaleHelper.pick(es: 'Pantalla de bloqueo', en: 'Lock screen'),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: _appleBlue, strokeWidth: 2),
            )
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 12),
                    _buildStackCarousel(),
                    const SizedBox(height: 24),
                    _buildRows(),
                    const SizedBox(height: 16),
                    if (_enabled) _buildStatsCard(),
                    const SizedBox(height: 20),
                    _buildPrimaryCta(),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleHelper.pick(es: 'PIXORA · DAILY', en: 'PIXORA · DAILY'),
            style: TextStyle(
              fontFamily: 'GeistMono',
              fontSize: 10,
              letterSpacing: 2,
              color: _appleBlue,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pixora Daily',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            LocaleHelper.pick(
              es: 'Tu pantalla, viva todo el día',
              en: 'Your screen, alive all day',
            ),
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.5),
              fontWeight: FontWeight.w400,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackCarousel() {
    final urls = _previewUrls;
    return SizedBox(
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (urls.length > 0)
            _stackCard(urls[0], const Offset(-100, 8), -12, 1, 0.7),
          if (urls.length > 1)
            _stackCard(urls[1], const Offset(100, 8), 12, 2, 0.85),
          if (urls.length > 2)
            _stackCard(urls[2], Offset.zero, 0, 3, 1.0, withBorder: true),
          // Empty state if catalog hasn't loaded yet
          if (urls.isEmpty)
            Container(
              width: 180,
              height: 230,
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: const Icon(Icons.image_outlined,
                  color: Colors.white24, size: 40),
            ),
        ],
      ),
    );
  }

  Widget _stackCard(
      String url, Offset offset, double rot, int z, double opacity,
      {bool withBorder = false}) {
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: rot * 3.14159 / 180,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: 180,
            height: 230,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              image: DecorationImage(
                image: NetworkImage(url),
                fit: BoxFit.cover,
              ),
              border: withBorder
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.1), width: 2)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRows() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _row(
            icon: Icons.timer,
            title: LocaleHelper.pick(es: 'Frecuencia', en: 'Frequency'),
            value: LocaleHelper.pick(
              es: 'cada ${_intervalLabel(_intervalMinutes)}',
              en: 'every ${_intervalLabel(_intervalMinutes)}',
            ),
            onTap: _pickInterval,
          ),
          const SizedBox(height: 8),
          _row(
            icon: Icons.phone_android,
            title: LocaleHelper.pick(es: 'Aplicar a', en: 'Apply to'),
            value: _targetLabel(_target),
            onTap: _pickTarget,
          ),
          const SizedBox(height: 8),
          _row(
            icon: Icons.collections_outlined,
            title: LocaleHelper.pick(es: 'Categoría', en: 'Category'),
            value: _categoryLabel(_category),
            onTap: _pickCategory,
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _appleBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _appleBlue, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.4), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _appleBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _appleBlue.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: _appleBlue, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleHelper.pick(es: 'Daily activo', en: 'Daily active'),
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    LocaleHelper.pick(
                      es: '$_cachedCount cacheados · $_cacheSize MB',
                      en: '$_cachedCount cached · $_cacheSize MB',
                    ),
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.6),
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _toggle,
          style: ElevatedButton.styleFrom(
            backgroundColor: _enabled ? const Color(0xFF1C1C1E) : _appleBlue,
            disabledBackgroundColor: _appleBlue.withValues(alpha: 0.5),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
            side: _enabled
                ? const BorderSide(color: Color(0xFF38383A), width: 1)
                : null,
          ).copyWith(
            overlayColor: WidgetStateProperty.all(_appleBlueDark),
          ),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _enabled ? Icons.pause : Icons.play_arrow,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _enabled
                          ? LocaleHelper.pick(
                              es: 'Pausar Daily', en: 'Pause Daily')
                          : LocaleHelper.pick(
                              es: 'Activar Daily', en: 'Enable Daily'),
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.current,
  });
  final String title;
  final List<(T, String)> items;
  final T current;

  @override
  Widget build(BuildContext context) {
    // Cap the sheet at 75% de la pantalla — el resto deja ver la página
    // detrás. Si los items no caben, scroll vertical (antes hacía overflow
    // por 74px con 8 items + status/nav bars en pantallas chicas).
    final maxH = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (val, label) in items)
                        InkWell(
                          onTap: () => Navigator.pop(context, val),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      fontFamily: 'Geist',
                                      fontSize: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (val == current)
                                  const Icon(
                                    Icons.check,
                                    color: Color(0xFF0A84FF),
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
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
