import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/services/report_service.dart';
import '../../../../core/utils/hud_hint_helper.dart';
import '../../../../core/utils/tap_guard.dart';
import '../../../../core/widgets/report_content_modal.dart';
import '../../../../core/content/content_manager.dart';
import '../../../../core/content/content_types.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/credit_service.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../core/widgets/codex_detail_layout.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../../core/widgets/typewriter_text.dart';
import '../../../../core/widgets/microinteractions/heart_burst_button.dart';
import '../../../../core/widgets/offline_badge.dart';
import '../../../../core/widgets/offline_modal.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../../favorites/providers/favorites_provider.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../data/models/wallpaper.dart';
import '../widgets/holocard_like_overlay.dart';

/// Auction-listing preview for a wallpaper. Presents the image as a framed
/// piece with catalog metadata below — as if it were a lot in a fine art
/// auction house. Black ink background, gold borders, serif typography.
class WallpaperPreviewPage extends ConsumerStatefulWidget {
  const WallpaperPreviewPage({required this.wallpaper, super.key});

  final Wallpaper wallpaper;

  @override
  ConsumerState<WallpaperPreviewPage> createState() =>
      _WallpaperPreviewPageState();
}

class _WallpaperPreviewPageState extends ConsumerState<WallpaperPreviewPage>
    with TickerProviderStateMixin {
  bool _isApplying = false;
  double _downloadProgress = 0.0;
  String _loadingStatus = '';
  LoadingPhase _loadingPhase = LoadingPhase.downloading;

  // 2026-06-21 — anti-spam guards. Filosofía: swallow silent (sin
  // feedback visual), el user no nota nada raro cuando da doble-tap.
  final _reportGuard = TapGuardController(cooldown: const Duration(seconds: 2));
  final _favGuard =
      TapGuardController(cooldown: const Duration(milliseconds: 700));
  final _applyGuard = TapGuardController(cooldown: const Duration(seconds: 3));

  late final AnimationController _holoShine;
  late final AnimationController _holoSweep;

  // Controlador del scroll del detalle — lo comparte el TypewriterText para
  // hacer autoscroll y seguir la descripción mientras se escribe.
  final ScrollController _detailScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WallpaperStatsService.instance.trackView(widget.wallpaper.id);
    _holoShine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();
    _holoSweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
  }

  @override
  void dispose() {
    _holoShine.dispose();
    _holoSweep.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  // ── Business logic (unchanged) ────────────────────────────────────────

  // Always HD for apply/download — the user will see this on their lock
  // screen and home. LQ only belongs in browse thumbnails, not the final
  // installed wallpaper.
  String get _downloadFile => widget.wallpaper.imageFile;

  void _setLoading(String status, {double progress = 0.0}) {
    if (mounted) {
      setState(() {
        _loadingStatus = status;
        _downloadProgress = progress;
      });
    }
  }

  Future<void> _applyWallpaper(int target) async {
    // 2026-06-21 — Tap-guard 3s. Doble-tap accidental en APLICAR
    // disparaba race en el WallpaperService nativo (canvas↔video
    // crash 2026-06-10). Swallow silent — el _isApplying state ya
    // muestra el LoadingOverlay como feedback visual.
    if (!_applyGuard.tryFire()) return;
    // Pre-check de conectividad: si está offline Y el archivo NO está en
    // cache local, mostrar el modal Holographic Edge en vez de intentar y
    // fallar. Si lo está, proceder normal (apply offline funciona).
    if (!ConnectivityService.instance.isOnline) {
      final cached = await ContentManager.instance
          .isCached(widget.wallpaper.toContentItem());
      if (!cached) {
        if (!mounted) return;
        final retried = await OfflineModal.show(context, isAutoRotate: false);
        if (retried != true) return;
      }
    }

    setState(() {
      _isApplying = true;
      _downloadProgress = 0.0;
      _loadingStatus = 'Descargando...';
      _loadingPhase = LoadingPhase.downloading;
    });

    final installTarget = switch (target) {
      0 => InstallTarget.homeScreen,
      1 => InstallTarget.lockScreen,
      _ => InstallTarget.bothScreens,
    };

    final success = await ContentManager.instance.downloadAndInstall(
      item: widget.wallpaper.toContentItem(),
      target: installTarget,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
      onPhase: (phase) {
        if (!mounted) return;
        setState(() {
          switch (phase) {
            case 'downloading':
              _loadingPhase = LoadingPhase.downloading;
              _loadingStatus = 'Descargando pieza...';
            case 'sprites':
              _loadingPhase = LoadingPhase.sprites;
              _loadingStatus = 'Descargando efectos...';
              _downloadProgress = 0.0;
            case 'installing':
              _loadingPhase = LoadingPhase.installing;
              _loadingStatus = 'Aplicando...';
            case 'done':
              _loadingPhase = LoadingPhase.done;
              _loadingStatus = '¡Pieza aplicada!';
          }
        });
      },
      onError: (msg) {
        if (mounted) {
          setState(() {
            _loadingPhase = LoadingPhase.error;
            _loadingStatus = msg;
          });
        }
      },
    );

    if (mounted && success) {
      setState(() {
        _loadingPhase = LoadingPhase.done;
        _loadingStatus = '¡Pieza aplicada!';
      });
      await Future.delayed(const Duration(milliseconds: 1200));
    }
    if (mounted) setState(() => _isApplying = false);
  }

  Future<void> _saveToGallery() async {
    setState(() {
      _isApplying = true;
      _downloadProgress = 0.0;
      _loadingStatus = 'Descargando...';
    });

    String? errorMsg;
    final path = await DownloadService.instance.downloadWallpaper(
      _downloadFile,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
      onError: (msg) => errorMsg = msg,
    );

    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg ?? 'Descarga fallida'),
            backgroundColor: context.hud.surface,
          ),
        );
      }
      setState(() => _isApplying = false);
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Archivo no encontrado'),
            backgroundColor: context.hud.surface,
          ),
        );
      }
      setState(() => _isApplying = false);
      return;
    }

    // Track download AFTER it succeeded (audit Sprint 1 fix: was firing
    // before the await above, inflating counter even on network failure).
    WallpaperStatsService.instance.trackDownload(widget.wallpaper.id);

    _setLoading('Guardando en galería...', progress: 1.0);
    final success = await WallpaperService.instance.saveToGallery(path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Guardado en Fotos' : 'No se pudo guardar'),
          backgroundColor: context.hud.surface,
        ),
      );
      if (success) {
        await HudHintHelper.maybeShow(context);
      }
    }
    setState(() => _isApplying = false);
  }

  Future<void> _applyLiveWallpaper() async {
    // 2026-06-21 — Tap-guard 3s — comparte controller con _applyWallpaper
    // porque solo puede haber UNA aplicación en curso (sea live o static).
    if (!_applyGuard.tryFire()) return;
    // Pre-check de conectividad para live wallpapers (mismo patrón que
    // _applyWallpaper). Live wallpapers casi siempre necesitan red porque
    // los videos son archivos nuevos; si está cacheado, dejar pasar.
    if (!ConnectivityService.instance.isOnline) {
      final isAdaptedLive = widget.wallpaper.customPreviewUrl != null;
      final cached = await ContentManager.instance
          .isCached(widget.wallpaper.toContentItem(asLive: isAdaptedLive));
      if (!cached) {
        if (!mounted) return;
        final retried = await OfflineModal.show(context, isAutoRotate: false);
        if (retried != true) return;
      }
    }

    setState(() {
      _isApplying = true;
      _downloadProgress = 0.0;
      _loadingStatus = 'Preparando...';
      _loadingPhase = LoadingPhase.downloading;
    });

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Micrófono requerido para el ecualizador'),
          backgroundColor: context.hud.surface,
        ),
      );
    }

    _setLoading('Descargando pieza...');

    // asLive=true switches the ContentItem to the wallpaper-videos bucket and
    // liveVideo type. That mapping is correct ONLY for wallpapers reached via
    // wallpaperFromLive() — those have customPreviewUrl set and imageFile
    // pointing to the video. For pure static wallpapers (no video backing),
    // keep asLive=false so the download targets wallpaper-images; the install
    // still uses InstallTarget.liveWallpaper so the LiveWallpaperInstaller
    // adds effects on top of the static image (or upgrades it to canvas_scene
    // via the catalog index lookup in WallpaperService.setLiveWallpaper).
    final isAdaptedLive = widget.wallpaper.customPreviewUrl != null;

    final success = await ContentManager.instance.downloadAndInstall(
      item: widget.wallpaper.toContentItem(asLive: isAdaptedLive),
      target: InstallTarget.liveWallpaper,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
      onPhase: (phase) {
        if (!mounted) return;
        setState(() {
          switch (phase) {
            case 'downloading':
              _loadingPhase = LoadingPhase.downloading;
              _loadingStatus = 'Descargando pieza...';
            case 'sprites':
              _loadingPhase = LoadingPhase.sprites;
              _loadingStatus = 'Descargando efectos...';
              _downloadProgress = 0.0;
            case 'installing':
              _loadingPhase = LoadingPhase.installing;
              _loadingStatus = 'Aplicando live wallpaper...';
            case 'done':
              _loadingPhase = LoadingPhase.done;
              _loadingStatus = '¡Live wallpaper aplicado!';
          }
        });
      },
      onError: (msg) {
        if (mounted) {
          setState(() {
            _loadingPhase = LoadingPhase.error;
            _loadingStatus = msg;
          });
        }
      },
    );

    if (mounted && success) {
      setState(() {
        _loadingPhase = LoadingPhase.done;
        _loadingStatus = '¡Live wallpaper aplicado!';
      });
      await Future.delayed(const Duration(milliseconds: 1200));
    }
    if (mounted) setState(() => _isApplying = false);
  }

  void _showApplyDialog() {
    if (Platform.isIOS) {
      _saveToGallery();
      return;
    }
    AdService.instance.showInterstitialAd(
      placement: 'wallpaper_apply',
      onAdDismissed: () {
        if (!mounted) return;
        _showApplyOptions();
      },
    );
  }

  // ── UI helpers ────────────────────────────────────────────────────────

  TextStyle _serif(double size,
          {FontWeight w = FontWeight.w400,
          FontStyle s = FontStyle.normal,
          Color? color,
          double ls = 0.02}) =>
      GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontWeight: w,
        fontStyle: s,
        color: color,
        letterSpacing: ls,
        height: 1.3,
      );

  TextStyle _display(double size,
          {FontWeight w = FontWeight.w900,
          FontStyle s = FontStyle.normal,
          Color? color,
          double ls = -0.02}) =>
      GoogleFonts.playfairDisplay(
        fontSize: size,
        fontWeight: w,
        fontStyle: s,
        color: color,
        letterSpacing: ls,
        height: 1.1,
      );

  TextStyle _meta(double size, {Color? color, double ls = 0.25}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: ls,
      );

  /// Generate a deterministic catalog lot number like "N° 007" from the id.
  String get _lotNumber {
    final id = widget.wallpaper.id;
    final hash = id.hashCode.abs() % 1000;
    return 'N° ${hash.toString().padLeft(3, '0')}';
  }

  void _showApplyOptions() {
    final isFree = AdService.instance.isNextActionFree;
    final credits = CreditService.instance.balance;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.hud.surface,
      // 2026-06-13 FIX: en pantallas chicas (Huawei VNS-L53 y similares) el
      // contenido del sheet excede la altura disponible y RenderFlex
      // overflowed by 34 pixels. Solucion: isScrollControlled permite que el
      // sheet sea mas alto que la mitad de la pantalla, y el SingleChildScrollView
      // mas abajo deja al usuario hacer swipe si aun no cabe todo.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      // 2026-06-07 FIX: AdMob keeps the system nav bar hidden during the
      // interstitial; ~1.3s after dismiss Android restores it and
      // MediaQuery.padding.bottom flips 0→48dp. SafeArea then rebuilds the
      // sheet at a different height, which the user perceives as a "flash"
      // or duplicated render. removeBottom strips that padding from the
      // sheet's local MediaQuery so the SafeArea below has no bottom inset
      // to react to. We add the 16dp bottom margin manually inside the
      // Padding instead, so the sheet still clears the gesture bar.
      builder: (context) {
        return MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              // Cap a 85% de la pantalla para que siempre quede un peek del
              // wallpaper detras y el usuario sepa que es un sheet, no full screen.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    20,
                    24,
                    20 + MediaQuery.of(context).viewPadding.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Text('— ',
                              style: _serif(13,
                                  color: context.hud.accent,
                                  s: FontStyle.italic)),
                          Text(
                            'aplicar pieza',
                            style: _serif(15,
                                color: context.hud.accent,
                                s: FontStyle.italic,
                                w: FontWeight.w500),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: context.hud.accent, width: 1),
                            ),
                            child: Text(
                              isFree ? 'SIN AD' : 'CON AD',
                              style:
                                  _meta(9, color: context.hud.accent, ls: 0.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Diamonds line
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.diamond,
                              color: context.hud.accent, size: 13),
                          const SizedBox(width: 5),
                          Text('$credits diamantes',
                              style: _meta(11,
                                  color: context.hud.textDim, ls: 0.15)),
                          const SizedBox(width: 12),
                          Text('·',
                              style: _meta(11, color: context.hud.textDim)),
                          const SizedBox(width: 12),
                          Text(
                            isFree
                                ? 'próximo sin cobro'
                                : '+${CreditService.creditsPerAd} por ver',
                            style:
                                _meta(11, color: context.hud.textDim, ls: 0.05),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // 2026-06-13 (Eduardo) — LIVE primero para que sea el
                      // primer boton que tocan casi por inercia, antes de
                      // leer. El foil shimmer + glow lo hace destacar como
                      // CTA principal y empuja la conversion a la experiencia
                      // premium (live wallpaper con efectos).
                      _buildLiveFoilOption(() {
                        Navigator.pop(context);
                        _applyLiveWallpaper();
                      }),
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        height: 1,
                        color: context.hud.divider,
                      ),
                      _buildOption(Icons.home_outlined, 'Pantalla principal',
                          'home screen', () {
                        Navigator.pop(context);
                        _applyWallpaper(0);
                      }),
                      _buildOption(Icons.lock_outline, 'Pantalla de bloqueo',
                          'lock screen', () {
                        Navigator.pop(context);
                        _applyWallpaper(1);
                      }),
                      _buildOption(Icons.phone_android_outlined,
                          'Ambas pantallas', 'both', () {
                        Navigator.pop(context);
                        _applyWallpaper(2);
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOption(
      IconData icon, String label, String sub, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: context.hud.accent, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: _display(15,
                          color: context.hud.text,
                          w: FontWeight.w700,
                          ls: -0.01)),
                  const SizedBox(height: 2),
                  Text('— $sub',
                      style: _serif(12,
                          color: context.hud.textDim, s: FontStyle.italic)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: context.hud.accent.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  /// Featured "Live wallpaper" CTA with holographic foil shimmer.
  /// Designed to draw attention to the LIVE option over the static apply
  /// targets (Home / Lock / Both). Visual recipe:
  ///   - Tinted gold background (subtle, 8-14% alpha)
  ///   - 1px gold border + rounded corners (6px)
  ///   - Diagonal foil sweep (gold→cyan→magenta) animates L→R every 3.5s
  ///     using the existing [_holoSweep] controller (free — already ticking
  ///     for the card holo shine, no extra ticker needed)
  ///   - Icon + label in gold-pale (#F0DD9E) so they stand out vs the
  ///     regular options' white text
  Widget _buildLiveFoilOption(VoidCallback onTap) {
    const goldPale = Color(0xFFF0DD9E);
    const gold = Color(0xFFE6B655);
    final radius = BorderRadius.circular(6);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                gold.withValues(alpha: 0.06),
                gold.withValues(alpha: 0.12),
                gold.withValues(alpha: 0.06),
              ],
            ),
            border: Border.all(color: gold.withValues(alpha: 0.30), width: 1),
            borderRadius: radius,
          ),
          child: Stack(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_outlined,
                        color: goldPale, size: 22),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Live wallpaper (con efectos)',
                              style: _display(15,
                                  color: goldPale,
                                  w: FontWeight.w700,
                                  ls: -0.01)),
                          const SizedBox(height: 2),
                          Text('— live + touch',
                              style: _serif(12,
                                  color: context.hud.textDim,
                                  s: FontStyle.italic)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: goldPale.withValues(alpha: 0.85)),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _holoSweep,
                    builder: (ctx, _) {
                      return LayoutBuilder(builder: (ctx, c) {
                        final w = c.maxWidth;
                        // Slide a translucent diagonal band from off-screen
                        // left (-w) to off-screen right (+2w) so the cycle
                        // travels its full width PLUS one band width.
                        final dx = -w + _holoSweep.value * (w * 3);
                        return Stack(children: [
                          Positioned(
                            left: dx,
                            top: 0,
                            bottom: 0,
                            width: w,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(-0.6, -1),
                                  end: Alignment(0.6, 1),
                                  colors: [
                                    Color(0x00000000),
                                    Color(0x73FFEBAA), // 45% pale gold
                                    Color(0x5978DCFF), // 35% cyan
                                    Color(0x66FF96E6), // 40% magenta
                                    Color(0x00000000),
                                  ],
                                  stops: [0.30, 0.45, 0.50, 0.55, 0.70],
                                ),
                              ),
                            ),
                          ),
                        ]);
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Layout ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isFav = ref.watch(favoritesProvider).contains(widget.wallpaper.id);
    final w = widget.wallpaper;

    // Cultural / mythology wallpapers get the editorial Códice layout
    // (deity portrait + chapter heading + drop-cap intro + facts grid +
    // ofrenda card). Others use the legacy preview/CTA stack.
    if (w.cultural != null && w.cultural!.isNotEmpty) {
      return _buildCodexScaffold(isFav);
    }

    return _buildHoloCardScaffold(isFav);
  }

  /// Trading Card Holo (concept #05, Eduardo 2026-05-16). Wallpaper rendered
  /// as a collectible card with animated holographic foil bg, ★★★ RARE stamp,
  /// lot serial, square holo image with diagonal shine sweep, black name strip
  /// with collection chip, italic description, and a pill APPLY CTA pegado
  /// abajo. iOS = silver foil. B&G = gold/copper foil with hue-rotate.
  Widget _buildHoloCardScaffold(bool isFav) {
    final h = context.hud;
    final isIos = h.isIosStyle;

    // 2026-06-21 — Bloquear back gesture mientras está aplicando para
    // no dejar el ContentManager huérfano (download en curso + nav back
    // a veces dejaba archivos parciales en disk). Permite back normal
    // cuando no hay apply activo.
    return PopScope(
      canPop: !_isApplying,
      child: Scaffold(
        backgroundColor:
            isIos ? const Color(0xFFF5F7FA) : const Color(0xFF07060E),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Cosmic background with subtle radials
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: isIos
                      ? const RadialGradient(
                          center: Alignment.topCenter,
                          radius: 1.2,
                          colors: [Color(0x145E5CE6), Color(0xFFF5F7FA)],
                          stops: [0.0, 0.6],
                        )
                      : RadialGradient(
                          center: Alignment.topCenter,
                          radius: 1.4,
                          colors: [
                            const Color(0xFF502878).withValues(alpha: 0.20),
                            const Color(0xFF07060E),
                          ],
                          stops: const [0.0, 0.7],
                        ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Column(
                  children: [
                    _buildHoloTopBar(isFav),
                    const SizedBox(height: 4),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _detailScroll,
                        child: Column(
                          children: [
                            _buildHoloCard(),
                            const SizedBox(height: 12),
                            _buildHoloDescription(),
                            const SizedBox(height: 14),
                            _buildHoloCta(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 2026-06-13 — Animacion de likes (Heart Burst + Holo Shimmer +
            // Stack Counter) flotando encima del holocard. Disparada por el
            // statsEventStream cuando este wallpaper recibe un like (local
            // o remoto via Realtime).
            Positioned.fill(
              child: HolocardLikeOverlay(wallpaperId: widget.wallpaper.id),
            ),
            LoadingOverlay(
              visible: _isApplying,
              progress: _downloadProgress > 0 ? _downloadProgress : null,
              status: _loadingStatus,
              accentColor: context.hud.accent,
              phase: _loadingPhase,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoloTopBar(bool isFav) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    final accent = isIos ? const Color(0xFF0A84FF) : HudTokens.goldBright;

    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.arrow_back_ios_new, color: accent, size: 18),
          ),
        ),
        const Spacer(),
        // 2026-06-20 — Botón Reportar contenido. Requerido por la
        // política de contenido generado por IA de Google Play.
        InkWell(
          onTap: _onReportContent,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.flag_outlined,
              color: accent.withValues(alpha: 0.7),
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // M06 — Heart Burst con partículas rosas al activar. Tap-guard
        // 700ms para que el martilleo del corazón no sature el RPC de
        // toggleLike ni acumule animaciones encimadas.
        HeartBurstButton(
          active: isFav,
          onTap: () {
            if (!_favGuard.tryFire()) return;
            ref.read(favoritesProvider.notifier).toggle(widget.wallpaper.id);
          },
          size: 18,
          color: isFav && isIos ? const Color(0xFFFF3B30) : accent,
        ),
      ],
    );
  }

  void _onReportContent() {
    // Tap-guard 2s — evita abrir múltiples modales encimados o crear
    // reportes duplicados aunque el RPC ya tenga su propio anti-spam.
    if (!_reportGuard.tryFire()) return;
    final w = widget.wallpaper;
    showReportContentModal(
      context,
      wallpaperId: w.id,
      kind: w.isPanoramic ? ReportableKind.panoramic : ReportableKind.static_,
      wallpaperMeta: {
        'name': w.name,
        'category': w.category,
        'preview_url': w.previewUrl,
        'is_panoramic': w.isPanoramic,
      },
    );
  }

  Widget _buildHoloCard() {
    final h = context.hud;
    final isIos = h.isIosStyle;

    // Holographic foil gradient — animated background-position.
    const iosColors = [
      Color(0xFFD8E0EE),
      Color(0xFFF7FAFF),
      Color(0xFFCDD9EE),
      Color(0xFFF7FAFF),
      Color(0xFFB8C8E0),
    ];
    const darkColors = [
      Color(0xFF8B7228),
      Color(0xFFF5D676),
      Color(0xFFB8860B),
      Color(0xFFF5D676),
      Color(0xFF8B7228),
    ];
    final foilColors = isIos ? iosColors : darkColors;

    return AspectRatio(
      aspectRatio: 4 / 5.4,
      child: AnimatedBuilder(
        animation: _holoShine,
        builder: (_, __) {
          // Animate the gradient by shifting alignment from (-1,0) → (1,0)
          final t = _holoShine.value;
          final align = (t < 0.5 ? t * 2 : 2 - t * 2);
          final beginX = -1.0 + align * 2.0;
          return Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(beginX, -1),
                end: Alignment(beginX + 0.8, 1),
                colors: foilColors,
                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: isIos
                      ? const Color(0xFF3C5078).withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.7),
                  blurRadius: isIos ? 22 : 28,
                  offset: const Offset(0, 10),
                ),
                if (!isIos)
                  BoxShadow(
                    color: HudTokens.gold.withValues(alpha: 0.4),
                    blurRadius: 24,
                  ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: isIos ? 0.7 : 0.18),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                // Header — RARE pill + (opcional) TYPE pill + lot serial.
                // 2026-06-24: agregamos pill de TIPO (PANORAMIC / LIVE / 3D)
                // al lado del RARE para que el user identifique de un vistazo
                // qué tipo de wallpaper está viendo. Static no muestra pill
                // extra (es el default).
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '★★★ RARE',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFFFD95E),
                                letterSpacing: 2.4,
                                height: 1.0,
                              ),
                            ),
                          ),
                          if (widget.wallpaper.isPanoramic) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF2BD6)
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '⟷ PANORAMIC',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 1.8,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${_lotNumber.replaceFirst('N° ', 'N° ')} / ∞',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: isIos
                              ? const Color(0xFF1A2640)
                              : const Color(0xFF1A1300),
                          letterSpacing: 1.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Holo image (square) with sweep animation
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: CachedWallpaperImage(
                            imageUrl: widget.wallpaper.previewUrl,
                            useAuroraLoader: true,
                          ),
                        ),
                        // Holographic shine sweep
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _holoSweep,
                              builder: (_, __) {
                                final v = _holoSweep.value;
                                // 0→0.5: -0.6 → 0.6, then back
                                final x = v < 0.5
                                    ? -0.6 + v * 2.4
                                    : 0.6 - (v - 0.5) * 2.4;
                                final opacity =
                                    v < 0.5 ? v * 2 : 1.0 - (v - 0.5) * 2;
                                return FractionalTranslation(
                                  translation: Offset(x, 0),
                                  child: Opacity(
                                    opacity: opacity * 0.6,
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment(-0.5, -1),
                                          end: Alignment(0.5, 1),
                                          colors: [
                                            Color(0x00FFFFFF),
                                            Color(0x59FFFFFF),
                                            Color(0x00FFFFFF),
                                          ],
                                          stops: [0.30, 0.48, 0.66],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                // Name strip — black band with name + collection
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.wallpaper.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.1,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.wallpaper.category.toUpperCase(),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 7,
                          fontWeight: FontWeight.w600,
                          color: isIos
                              ? const Color(0xFF6EC3FF)
                              : const Color(0xFFFFD95E),
                          letterSpacing: 2.8,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 2026-07-05 — Efecto typewriter: la descripción se escribe sola para
  /// que el usuario la vaya leyendo (cada wallpaper cuenta una historia).
  /// Sin cap de líneas: las descripciones ricas (~400 chars) se muestran
  /// completas; la página ya scrollea. TypewriterText reserva la altura
  /// final desde el inicio, así el CTA no brinca mientras escribe.
  Widget _buildHoloDescription() {
    final h = context.hud;
    final isIos = h.isIosStyle;
    final w = widget.wallpaper;
    final text =
        w.displayDescription.isNotEmpty ? w.displayDescription : w.name;
    // Paleta de resaltado — 4 roles que contrastan pero combinan sobre el
    // fondo oscuro (2 cálidos: oro + coral · 2 fríos: menta + celeste).
    // El texto base sube a crema legible (antes usaba textDim, un dorado
    // apagado difícil de leer). Roles:
    //   name    → personajes / sagas (oro brillante)
    //   place   → lugares / mundos (menta)
    //   power   → poderes / energía / acción (celeste)
    //   emotion → emociones / valores / la lección de la escena (coral)
    // `key` queda como alias suave de `place` por compatibilidad.
    final Map<String, Color> hc = isIos
        ? const {
            'name': Color(0xFFB8912E), // oro oscuro
            'place': Color(0xFF00A878), // teal
            'power': Color(0xFF2A7FC0), // azul
            'emotion': Color(0xFFD9663B), // terracota
          }
        : const {
            'name':
                Color(0xFFF2C230), // ámbar dorado vivo (contrasta con crema)
            'place': Color(0xFF6FE0C0), // menta agua
            'power': Color(0xFF8FD3FF), // celeste
            'emotion': Color(0xFFF6A07A), // coral cálido
          };
    TextStyle hl(String role) =>
        TextStyle(color: hc[role], fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TypewriterText(
        text,
        textAlign: TextAlign.center,
        scrollController: _detailScroll,
        cursorColor: isIos ? const Color(0xFF0A84FF) : HudTokens.goldBright,
        highlightStyles: {
          'name': hl('name'),
          'place': hl('place'),
          'power': hl('power'),
          'emotion': hl('emotion'),
          'key': hl('place'),
        },
        style: isIos
            ? GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: h.text,
                height: 1.45,
              )
            : GoogleFonts.cormorantGaramond(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w400,
                color: h.text,
                height: 1.45,
              ),
      ),
    );
  }

  Widget _buildHoloCta() {
    final h = context.hud;
    final isIos = h.isIosStyle;
    final label = _isApplying
        ? (_downloadProgress > 0
            ? 'APLICANDO ${(_downloadProgress * 100).toInt()}%'
            : 'APLICANDO...')
        : 'APLICAR WALLPAPER';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isApplying ? null : _showApplyDialog,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: isIos
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF4A9EFF),
                      Color(0xFF0A84FF),
                      Color(0xFF0066CC),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  )
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFF5D676),
                      Color(0xFFD4AF37),
                      Color(0xFF8B5A1F),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isIos
                  ? Colors.white.withValues(alpha: 0.5)
                  : const Color(0xFFF5D676),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isIos
                    ? const Color(0xFF0A84FF).withValues(alpha: 0.32)
                    : HudTokens.gold.withValues(alpha: 0.40),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isIos ? Colors.white : const Color(0xFF1A1300),
              letterSpacing: 1.8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isFav) {
    final h = context.hud;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                children: [
                  Icon(Icons.arrow_back_ios_new,
                      color: h.accent, size: h.isIosStyle ? 16 : 14),
                  const SizedBox(width: 4),
                  Text(
                    h.isIosStyle ? 'Atrás' : 'volver',
                    style: h.isIosStyle
                        ? HudTokens.body(
                            size: 16,
                            weight: FontWeight.w500,
                            color: h.accent,
                            letterSpacing: -0.2,
                          )
                        : _serif(14,
                            color: h.accent,
                            s: FontStyle.italic,
                            w: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: h.isIosStyle ? h.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(h.isIosStyle ? 999 : 0),
              border:
                  h.isIosStyle ? null : Border.all(color: h.accent, width: 1),
            ),
            child: Text(
              // _lotNumber already includes the "N° " prefix — don't double it.
              h.isIosStyle
                  ? _lotNumber
                  : 'LOT · ${_lotNumber.replaceFirst('N° ', '')}',
              style: HudTokens.mono(
                size: 10,
                color: h.isIosStyle ? h.textDim : h.accent,
                letterSpacing: h.isIosStyle ? 0.4 : 0.3,
                weight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => ref
                .read(favoritesProvider.notifier)
                .toggle(widget.wallpaper.id),
            borderRadius: h.isIosStyle ? BorderRadius.circular(999) : null,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: h.isIosStyle ? h.surface : Colors.transparent,
                shape: h.isIosStyle ? BoxShape.circle : BoxShape.rectangle,
                border:
                    h.isIosStyle ? null : Border.all(color: h.accent, width: 1),
              ),
              alignment: Alignment.center,
              child: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color:
                    isFav && h.isIosStyle ? const Color(0xFFFF3B30) : h.accent,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cabinet of Curiosities CTA — chiseled Cinzel text on a dark stone /
  /// mahogany surface. The `CodexDetailLayout` wraps this in its brass frame.
  /// Si está offline + wallpaper en cache, aparece arriba el badge
  /// "Disponible offline" (Surface 3 · Glow Pill) educando que SÍ se puede
  /// aplicar sin red.
  Widget _buildCta() {
    final h = context.hud;
    final isIos = h.isIosStyle;
    final stoneBg = isIos
        ? const Color(0xFF3A2818) // limestone/sepia dark
        : const Color(0xFF1C0E08); // dark mahogany
    final brassText = isIos
        ? const Color(0xFFE8C476) // brass on dark stone
        : HudTokens.goldBright;
    final label = _isApplying
        ? (_downloadProgress > 0
            ? 'APLICANDO ${(_downloadProgress * 100).toInt()}%'
            : 'APLICANDO...')
        : (Platform.isIOS ? 'GUARDAR EN FOTOS' : 'APLICAR WALLPAPER');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Surface 3 — Glow Pill. Solo visible cuando offline (badge
        // self-gating). No agrega espacio cuando online.
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: OfflineBadge(),
        ),
        _buildCtaButton(label, stoneBg, brassText),
      ],
    );
  }

  Widget _buildCtaButton(String label, Color stoneBg, Color brassText) {
    // M08 — bounce + glow verde cuando llega a done. Mantiene el look
    // Cinzel/mahogany pero comunica "✓ aplicado" sin cambiar la estética.
    final isDone = _loadingPhase == LoadingPhase.done;
    final accentGreen = isDone ? const Color(0xFF3DD68C) : null;
    return AnimatedScale(
      scale: isDone ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      child: InkWell(
        onTap: _isApplying ? null : _showApplyDialog,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: stoneBg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 1),
                spreadRadius: -1,
              ),
              if (accentGreen != null)
                BoxShadow(
                  color: accentGreen.withValues(alpha: 0.4),
                  blurRadius: 16,
                ),
            ],
          ),
          child: Text(
            label,
            style: GoogleFonts.cinzel(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: brassText,
              letterSpacing: 2.4,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  offset: const Offset(0, 1),
                  blurRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Editorial "Códice" layout — used when the wallpaper carries cultural
  /// data (mythology, mexica gods, egyptian deities, etc.). Reuses the apply
  /// CTA + favorite logic from the legacy preview but presents the wallpaper
  /// as a magazine-style page so users discover the cultural story.
  Widget _buildCodexScaffold(bool isFav) {
    final w = widget.wallpaper;
    return Scaffold(
      backgroundColor: context.hud.bg,
      body: Stack(
        children: [
          CodexDetailLayout(
            heroImage: CachedWallpaperImage(
              imageUrl: w.previewUrl,
              fit: BoxFit.cover,
            ),
            title: w.name,
            cultural: w.cultural!,
            applyCta: _buildCta(),
            statusBar: SafeArea(
              child: _buildTopBar(isFav),
            ),
          ),
          LoadingOverlay(
            visible: _isApplying,
            progress: _downloadProgress > 0 ? _downloadProgress : null,
            status: _loadingStatus,
            accentColor: context.hud.accent,
            phase: _loadingPhase,
          ),
        ],
      ),
    );
  }
}
