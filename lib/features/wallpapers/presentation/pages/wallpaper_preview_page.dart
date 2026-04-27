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

class _WallpaperPreviewPageState extends ConsumerState<WallpaperPreviewPage> {
  bool _isApplying = false;
  double _downloadProgress = 0.0;
  String _loadingStatus = '';
  LoadingPhase _loadingPhase = LoadingPhase.downloading;

  @override
  void initState() {
    super.initState();
    WallpaperStatsService.instance.trackView(widget.wallpaper.id);
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
                color: context.hud.accent.withOpacity(0.5)),
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

    return Scaffold(
      backgroundColor: context.hud.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(isFav),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFrame(),
                        const SizedBox(height: 22),
                        _buildCatalog(w),
                        const SizedBox(height: 20),
                        _buildPriceRow(),
                        const SizedBox(height: 16),
                        _buildCta(),
                      ],
                    ),
                  ),
                ),
              ],
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
              h.isIosStyle ? 'N° $_lotNumber' : 'LOT · $_lotNumber',
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

  Widget _buildCta() {
    final h = context.hud;
    final label = Platform.isIOS ? 'GUARDAR EN FOTOS' : 'APLICAR A MI TELÉFONO';
    return InkWell(
      onTap: _isApplying ? null : _showApplyDialog,
      borderRadius: h.isIosStyle ? BorderRadius.circular(14) : null,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: h.isIosStyle ? 14 : 16),
        decoration: BoxDecoration(
          color: h.accent,
          borderRadius: h.isIosStyle ? BorderRadius.circular(14) : null,
          boxShadow: h.isIosStyle
              ? [
                  BoxShadow(
                    color: h.accent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: h.isIosStyle
            ? Text(
                Platform.isIOS ? 'Guardar en Fotos' : 'Aplicar wallpaper',
                style: HudTokens.body(
                  size: 16,
                  weight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              )
            : Text(
                label,
                style: _display(14, color: h.bg, w: FontWeight.w900, ls: 0.25),
              ),
      ),
    );
  }
}
