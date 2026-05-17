import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/content/content_manager.dart';
import '../../../../core/content/content_types.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/credit_service.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../core/widgets/codex_detail_layout.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../../favorites/providers/favorites_provider.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../data/models/wallpaper.dart';

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

  late final AnimationController _holoShine;
  late final AnimationController _holoSweep;

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
    WallpaperStatsService.instance.trackDownload(widget.wallpaper.id);

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

    _setLoading('Guardando en galería...', progress: 1.0);
    final success = await WallpaperService.instance.saveToGallery(path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Guardado en Fotos' : 'No se pudo guardar'),
          backgroundColor: context.hud.surface,
        ),
      );
    }
    setState(() => _isApplying = false);
  }

  Future<void> _applyLiveWallpaper() async {
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

    final success = await ContentManager.instance.downloadAndInstall(
      item: widget.wallpaper.toContentItem(asLive: true),
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

  /// Artist line for the auction feel. Falls back if description empty.
  String get _artistLine {
    final desc = widget.wallpaper.description.trim();
    if (desc.isNotEmpty) return '— $desc';
    return '— Pixora original collection';
  }

  void _showApplyOptions() {
    final isFree = AdService.instance.isNextActionFree;
    final credits = CreditService.instance.balance;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.hud.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Text('— ',
                      style: _serif(13,
                          color: context.hud.accent, s: FontStyle.italic)),
                  Text(
                    'aplicar pieza',
                    style: _serif(15,
                        color: context.hud.accent,
                        s: FontStyle.italic,
                        w: FontWeight.w500),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.hud.accent, width: 1),
                    ),
                    child: Text(
                      isFree ? 'SIN AD' : 'CON AD',
                      style: _meta(9, color: context.hud.accent, ls: 0.2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Diamonds line
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.diamond, color: context.hud.accent, size: 13),
                  const SizedBox(width: 5),
                  Text('$credits diamantes',
                      style: _meta(11, color: context.hud.textDim, ls: 0.15)),
                  const SizedBox(width: 12),
                  Text('·', style: _meta(11, color: context.hud.textDim)),
                  const SizedBox(width: 12),
                  Text(
                    isFree
                        ? 'próximo sin cobro'
                        : '+${CreditService.creditsPerAd} por ver',
                    style: _meta(11, color: context.hud.textDim, ls: 0.05),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildOption(
                  Icons.home_outlined, 'Pantalla principal', 'home screen', () {
                Navigator.pop(context);
                _applyWallpaper(0);
              }),
              _buildOption(
                  Icons.lock_outline, 'Pantalla de bloqueo', 'lock screen', () {
                Navigator.pop(context);
                _applyWallpaper(1);
              }),
              _buildOption(
                  Icons.phone_android_outlined, 'Ambas pantallas', 'both', () {
                Navigator.pop(context);
                _applyWallpaper(2);
              }),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                height: 1,
                color: context.hud.divider,
              ),
              _buildOption(Icons.auto_awesome_outlined,
                  'Live wallpaper (con efectos)', 'live + touch', () {
                Navigator.pop(context);
                _applyLiveWallpaper();
              }),
            ],
          ),
        ),
      ),
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
    final w = widget.wallpaper;

    return Scaffold(
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
        InkWell(
          onTap: () =>
              ref.read(favoritesProvider.notifier).toggle(widget.wallpaper.id),
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav && isIos ? const Color(0xFFFF3B30) : accent,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHoloCard() {
    final h = context.hud;
    final isIos = h.isIosStyle;

    // Holographic foil gradient — animated background-position.
    final iosColors = const [
      Color(0xFFD8E0EE),
      Color(0xFFF7FAFF),
      Color(0xFFCDD9EE),
      Color(0xFFF7FAFF),
      Color(0xFFB8C8E0),
    ];
    final darkColors = const [
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
                // Header — RARE pill + lot serial
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      Text(
                        _lotNumber.replaceFirst('N° ', 'N° ') + ' / ∞',
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
                            imageUrl: widget.wallpaper.fullImageUrl,
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

  Widget _buildHoloDescription() {
    final h = context.hud;
    final isIos = h.isIosStyle;
    final w = widget.wallpaper;
    final text = w.description.isNotEmpty ? w.description : w.name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: isIos
            ? GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: h.textDim,
                height: 1.4,
              )
            : GoogleFonts.cormorantGaramond(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w400,
                color: h.textDim,
                height: 1.4,
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

  /// Double gold-bordered frame around the wallpaper image (or rounded
  /// shadow card in iOS).
  Widget _buildFrame() {
    final h = context.hud;
    if (h.isIosStyle) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: CachedWallpaperImage(
              imageUrl: widget.wallpaper.fullImageUrl,
              useAuroraLoader: true,
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: h.accent, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border:
                  Border.all(color: h.accent.withValues(alpha: 0.35), width: 1),
            ),
            child: CachedWallpaperImage(
              imageUrl: widget.wallpaper.fullImageUrl,
              useAuroraLoader: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCatalog(Wallpaper w) {
    final h = context.hud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          h.isIosStyle ? w.name : w.name.toUpperCase(),
          style: h.isIosStyle
              ? HudTokens.body(
                  size: 28,
                  weight: FontWeight.w700,
                  color: h.text,
                  letterSpacing: -0.6,
                )
              : _display(24, color: h.text, ls: -0.02),
        ),
        const SizedBox(height: 4),
        Text(
          h.isIosStyle
              ? widget.wallpaper.description.isNotEmpty
                  ? widget.wallpaper.description
                  : 'Pixora original collection'
              : _artistLine,
          style: h.isIosStyle
              ? HudTokens.body(
                  size: 14,
                  weight: FontWeight.w400,
                  color: h.textDim,
                  letterSpacing: -0.1,
                )
              : _serif(14,
                  color: h.accent, s: FontStyle.italic, w: FontWeight.w400),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: h.divider, width: h.isIosStyle ? 0.5 : 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _catItem(
                    h.isIosStyle ? 'FORMATO' : 'FORMAT', 'Vertical 9:16'),
              ),
              Expanded(
                child: _catItem(h.isIosStyle ? 'RESOLUCIÓN' : 'RESOLUTION',
                    w.imageSizeFormatted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _catItem(
                  h.isIosStyle ? 'COLECCIÓN' : 'COLLECTION', w.category),
            ),
            Expanded(
              child: _catItem(h.isIosStyle ? 'AÑO' : 'DATE', 'MMXXVI'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _catItem(String k, String v) {
    final h = context.hud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          h.isIosStyle ? k : k,
          style: HudTokens.mono(
            size: h.isIosStyle ? 11 : 10,
            color: h.textDim,
            letterSpacing: h.isIosStyle ? 0.4 : 0.2,
            weight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          v,
          style: h.isIosStyle
              ? HudTokens.body(
                  size: 15,
                  weight: FontWeight.w600,
                  color: h.text,
                  letterSpacing: -0.2,
                )
              : _serif(14,
                  color: h.text, s: FontStyle.italic, w: FontWeight.w400),
        ),
      ],
    );
  }

  Widget _buildPriceRow() {
    final h = context.hud;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: h.divider, width: h.isIosStyle ? 0.5 : 1),
          bottom: BorderSide(
              color: h.isIosStyle ? h.divider : h.accent.withValues(alpha: 0.3),
              width: h.isIosStyle ? 0.5 : 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            h.isIosStyle ? 'Precio' : '— precio / en Pixora',
            style: HudTokens.mono(
              size: h.isIosStyle ? 12 : 10,
              color: h.textDim,
              letterSpacing: h.isIosStyle ? -0.1 : 0.25,
              weight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            Platform.isIOS ? 'Save' : (h.isIosStyle ? 'Gratis' : 'GRATIS'),
            style: h.isIosStyle
                ? HudTokens.body(
                    size: 18,
                    weight: FontWeight.w700,
                    color: h.accent,
                    letterSpacing: -0.3,
                  )
                : _display(22, color: h.accent, w: FontWeight.w900, ls: 0.04),
          ),
        ],
      ),
    );
  }

  /// Cabinet of Curiosities CTA — chiseled Cinzel text on a dark stone /
  /// mahogany surface. The `CodexDetailLayout` wraps this in its brass frame.
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
    return InkWell(
      onTap: _isApplying ? null : _showApplyDialog,
      child: Container(
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
