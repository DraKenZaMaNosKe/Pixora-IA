import 'dart:io';
import 'dart:ui';
import '../../../../core/design/hud_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/content/content_manager.dart';
import '../../../../core/content/content_types.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/credit_service.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../data/models/live_wallpaper.dart';
import '../../../../core/widgets/codex_detail_layout.dart';

class LiveWallpaperPreviewPage extends StatefulWidget {
  final LiveWallpaper wallpaper;
  const LiveWallpaperPreviewPage({super.key, required this.wallpaper});

  @override
  State<LiveWallpaperPreviewPage> createState() =>
      _LiveWallpaperPreviewPageState();
}

class _LiveWallpaperPreviewPageState extends State<LiveWallpaperPreviewPage> {
  bool _isApplying = false;
  double _downloadProgress = 0.0;
  String _loadingStatus = '';
  LoadingPhase _loadingPhase = LoadingPhase.downloading;
  // Auto Play mode removed (Apr 2026) — all live wallpapers now ship as
  // Explore-only (touch scrub through frames). Saved bytes + better UX.
  // The `false` branch in apply() still exists as a safety fallback for
  // wallpapers that don't have remote frames yet.
  final bool _interactiveMode = true;
  late Future<bool> _isDownloadedFuture;

  Color get _glowColor => context.hud.accent;

  @override
  void initState() {
    super.initState();
    _isDownloadedFuture = _isDownloaded();
    WallpaperStatsService.instance.trackView('live_${widget.wallpaper.id}');
  }

  Future<void> _applyLiveWallpaper() async {
    // Show alternating ad (awards credits), then proceed
    AdService.instance.showInterstitialAd(
        placement: 'live_wallpaper_apply',
        onAdDismissed: () {
          if (mounted) _doApplyLiveWallpaper();
        });
  }

  Future<void> _doApplyLiveWallpaper() async {
    setState(() {
      _isApplying = true;
      _downloadProgress = 0.0;
      _loadingStatus = 'Checking system...';
      _loadingPhase = LoadingPhase.downloading;
    });

    // Small delay to ensure previous wallpaper service releases codec
    if (!_interactiveMode) {
      if (mounted) setState(() => _loadingStatus = 'Preparing player...');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (mounted) {
      setState(() {
        _loadingStatus = 'Downloading...';
        _loadingPhase = LoadingPhase.downloading;
      });
    }
    WallpaperStatsService.instance.trackDownload('live_${widget.wallpaper.id}');

    final dir = await getApplicationDocumentsDirectory();
    final w = widget.wallpaper;

    // Explore mode with pre-extracted frames: download images from Supabase
    if (_interactiveMode && w.hasRemoteFrames) {
      if (mounted) {
        setState(() {
          _loadingStatus = 'Downloading scene frames...';
          _loadingPhase = LoadingPhase.downloading;
        });
      }
      final framesDir = Directory('${dir.path}/explore_frames/${w.id}');
      await framesDir.create(recursive: true);

      // Check if already cached
      final existing =
          framesDir.listSync().where((f) => f.path.endsWith('.jpg')).length;
      if (existing < w.frameCount) {
        // Download all frames
        for (var i = 0; i < w.frameCount; i++) {
          final frameFile = File(
              '${framesDir.path}/frame_${(i + 1).toString().padLeft(4, '0')}.jpg');
          if (await frameFile.exists() && await frameFile.length() > 100) {
            continue;
          }
          await DownloadService.instance.downloadFile(
            w.frameUrl(i),
            frameFile,
            retries: 2,
            timeoutSeconds: 30,
            minBytes: 100,
          );
          if (mounted) {
            setState(() => _downloadProgress = (i + 1) / w.frameCount);
          }
        }
      }

      // Set wallpaper with frames path
      if (mounted) {
        setState(() {
          _loadingPhase = LoadingPhase.installing;
          _loadingStatus = 'Applying explore wallpaper...';
        });
      }
      await WallpaperService.instance.setLiveWallpaper(
        framesDir.path,
        w.glowColor,
        interactive: true,
      );
      // Track install to wallpaper_events
      WallpaperStatsService.instance
          .trackInstall('live_${widget.wallpaper.id}');

      if (mounted) {
        setState(() {
          _loadingPhase = LoadingPhase.done;
          _loadingStatus = 'Explore wallpaper set!';
        });
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        setState(() => _isApplying = false);
      }
      return;
    }

    // Auto Play mode: download video via ContentManager.
    // Fallback path for wallpapers without pre-extracted frames — MUST go
    // through MediaPlayer (interactive=false), otherwise the native engine
    // enters frame-scrub mode with a non-directory MP4 path and shows black.
    final success = await ContentManager.instance.downloadAndInstall(
      item: w.toContentItem(explore: false),
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
              _loadingStatus = LocaleHelper.pick(
                es: 'Descargando contenido...',
                en: 'Downloading assets...',
              );
            case 'sprites':
              _loadingPhase = LoadingPhase.sprites;
              _loadingStatus = LocaleHelper.pick(
                es: 'Descargando efectos animados...',
                en: 'Downloading animated effects...',
              );
              _downloadProgress = 0.0;
            case 'installing':
              _loadingPhase = LoadingPhase.installing;
              _loadingStatus = LocaleHelper.pick(
                es: 'Aplicando wallpaper...',
                en: 'Applying live wallpaper...',
              );
            case 'done':
              _loadingPhase = LoadingPhase.done;
              _loadingStatus = LocaleHelper.pick(
                es: '¡Wallpaper aplicado!',
                en: 'Live wallpaper applied!',
              );
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

    if (!success) {
      if (mounted) {
        if (_loadingPhase != LoadingPhase.error) {
          setState(() {
            _loadingPhase = LoadingPhase.error;
            _loadingStatus = 'Failed to set live wallpaper';
          });
          await Future.delayed(const Duration(milliseconds: 1500));
        }
        setState(() => _isApplying = false);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loadingPhase = LoadingPhase.done;
        _loadingStatus = _interactiveMode
            ? 'Explore wallpaper set!'
            : 'Live wallpaper applied!';
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() => _isApplying = false);
    }
  }

  Future<bool> _isDownloaded() async {
    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/live_wallpapers/${widget.wallpaper.videoFile}');
    return file.exists();
  }

  Future<void> _deleteFromDevice() async {
    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/live_wallpapers/${widget.wallpaper.videoFile}');
    if (await file.exists()) {
      await file.delete();
      if (mounted) {
        setState(() {
          _isDownloadedFuture = _isDownloaded();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Video deleted from device'),
            backgroundColor: context.hud.accent,
          ),
        );
      }
    }
  }

  /// Cabinet of Curiosities CTA — chiseled Cinzel text on a dark stone /
  /// mahogany surface. `CodexDetailLayout` wraps this in its brass frame.
  Widget _buildApplyCta() {
    final isIos = context.hud.isIosStyle;
    final stoneBg = isIos
        ? const Color(0xFF3A2818) // limestone/sepia dark
        : const Color(0xFF1C0E08); // dark mahogany
    final brassText = isIos ? const Color(0xFFE8C476) : HudTokens.goldBright;
    final label = _isApplying
        ? (_downloadProgress > 0
            ? 'APLICANDO ${(_downloadProgress * 100).toInt()}%'
            : 'PREPARANDO...')
        : 'APLICAR LIVE WALLPAPER';
    return InkWell(
      onTap: _isApplying ? null : _applyLiveWallpaper,
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

  @override
  Widget build(BuildContext context) {
    final w = widget.wallpaper;

    // If the wallpaper carries cultural editorial data (mythology / culture
    // category), render the Codex layout. Otherwise use the new Apple Music
    // Now Playing inspired layout (cream background, contained album-art preview,
    // dark text — solves the contrast problem of the old fullscreen overlay).
    if (w.cultural != null && w.cultural!.isNotEmpty) {
      return _buildCodexScaffold(context);
    }

    return _buildAppleProScaffold(context);
  }

  /// Apple Pro Window — concept #02 (Eduardo 2026-05-16).
  ///
  /// Layout inspirado en la página de detalle del App Store:
  /// breadcrumb back · video card 9:12 con badge · header row con título +
  /// GET pill · category sub · stat-chips bordeadas · descripción · grid de
  /// quick actions (Download / Favorite / Share). El APPLY (GET) vive en
  /// header-row, no en bottom CTA — Apple Pro pattern.
  Widget _buildAppleProScaffold(BuildContext context) {
    final w = widget.wallpaper;
    final h = context.hud;
    final isIos = h.isIosStyle;
    const iosBlue = Color(0xFF0A84FF);

    final bg = isIos ? Colors.white : h.bg;
    final cardBorder = isIos
        ? const Color(0xFFC6C6C8).withValues(alpha: 0.5)
        : HudTokens.gold.withValues(alpha: 0.18);
    final textPrimary = isIos ? const Color(0xFF1C1C1E) : h.text;
    final textDim = isIos ? const Color(0xFF8E8E93) : h.textDim;
    final dividerColor = isIos
        ? const Color(0xFFC6C6C8).withValues(alpha: 0.4)
        : HudTokens.gold.withValues(alpha: 0.15);
    final surfaceTile = isIos ? const Color(0xFFF2F2F7) : h.surface;
    final accent = isIos ? iosBlue : HudTokens.goldBright;
    final accentDeep = isIos ? const Color(0xFF0066CC) : HudTokens.gold;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Breadcrumb back ──────────────────────────────
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chevron_left, color: accent, size: 22),
                          Text(
                            LocaleHelper.pick(es: 'Live', en: 'Live'),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Video card (9:12 aspect) ─────────────────────
                  AspectRatio(
                    aspectRatio: 9 / 12,
                    child: Container(
                      decoration: BoxDecoration(
                        color: surfaceTile,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder, width: 0.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isIos ? 0.08 : 0.40),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: w.previewUrl,
                            fit: BoxFit.cover,
                            // Card en grid (~200px). Decodificar a 400px (2x
                            // retina) ahorra memoria vs bitmap full size.
                            memCacheWidth: 400,
                            errorWidget: (_, __, ___) =>
                                Container(color: surfaceTile),
                          ),
                          // Badge top-left — LIVE / SHADER / 3D, frosted dark
                          Positioned(
                            top: 8,
                            left: 8,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    w.typeBadge.toUpperCase(),
                                    style: const TextStyle(
                                      fontFamily: 'JetBrainsMono',
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 1.6,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Header row: title + GET button ───────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              w.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                                letterSpacing: -0.4,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              w.category.toUpperCase(),
                              style: TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: textDim,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildAppleProGetButton(
                          accent: accent, accentDeep: accentDeep, isIos: isIos),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Stat chips row ───────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: dividerColor, width: 0.5),
                        bottom: BorderSide(color: dividerColor, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildStatChip(
                          icon: Icons.star_rounded,
                          iconColor: const Color(0xFFFFC107),
                          label: '4.8',
                          textPrimary: textPrimary,
                          textDim: textDim,
                        ),
                        _buildStatSeparator(textDim),
                        _buildStatChip(
                          icon: Icons.visibility_outlined,
                          iconColor: textDim,
                          label: _formatStat(WallpaperStatsService.instance
                                  .getStats('live_${w.id}')['views'] ??
                              0),
                          textPrimary: textPrimary,
                          textDim: textDim,
                        ),
                        _buildStatSeparator(textDim),
                        _buildStatChip(
                          icon: Icons.download_outlined,
                          iconColor: textDim,
                          label: _formatStat(WallpaperStatsService.instance
                                  .getStats('live_${w.id}')['downloads'] ??
                              w.downloadCount),
                          textPrimary: textPrimary,
                          textDim: textDim,
                        ),
                        const Spacer(),
                        Text(
                          '${(w.videoSize / 1024 / 1024).toStringAsFixed(1)} MB',
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: textDim,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Description ──────────────────────────────────
                  if (w.description.isNotEmpty)
                    Text(
                      w.description,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: textPrimary,
                        height: 1.5,
                      ),
                    ),
                  const SizedBox(height: 18),

                  // ── Quick actions grid (3 cols) ──────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickAction(
                          icon: Icons.download_outlined,
                          label: LocaleHelper.pick(
                              es: 'Descargar', en: 'Download'),
                          accent: accent,
                          surfaceTile: surfaceTile,
                          isIos: isIos,
                          onTap: _isApplying ? null : _applyLiveWallpaper,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildQuickAction(
                          icon: Icons.favorite_border_rounded,
                          label:
                              LocaleHelper.pick(es: 'Favorito', en: 'Favorite'),
                          accent: accent,
                          surfaceTile: surfaceTile,
                          isIos: isIos,
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildQuickAction(
                          icon: Icons.ios_share_rounded,
                          label:
                              LocaleHelper.pick(es: 'Compartir', en: 'Share'),
                          accent: accent,
                          surfaceTile: surfaceTile,
                          isIos: isIos,
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── FREE / credits / delete row ──────────────────
                  Builder(builder: (_) {
                    final isFree = AdService.instance.isNextActionFree;
                    final credits = CreditService.instance.balance;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: isFree
                                ? (isIos
                                    ? const Color(0xFFE8F8EE)
                                    : HudTokens.gold.withValues(alpha: 0.10))
                                : accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isFree
                                ? 'FREE'
                                : '+${CreditService.creditsPerAd} credits',
                            style: TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isFree
                                  ? (isIos
                                      ? const Color(0xFF1B7340)
                                      : HudTokens.goldBright)
                                  : accent,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.diamond, size: 12, color: textDim),
                        const SizedBox(width: 4),
                        Text(
                          '$credits',
                          style: TextStyle(
                            fontSize: 11,
                            color: textDim,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  }),
                  FutureBuilder<bool>(
                    future: _isDownloadedFuture,
                    builder: (ctx, snap) {
                      if (snap.data != true) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: _deleteFromDevice,
                            icon: Icon(Icons.delete_outline,
                                size: 16, color: textDim),
                            label: Text(
                              LocaleHelper.pick(
                                  es: 'Borrar del dispositivo',
                                  en: 'Delete from device'),
                              style: TextStyle(fontSize: 12, color: textDim),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // Loading overlay
          LoadingOverlay(
            visible: _isApplying,
            progress: _downloadProgress > 0 ? _downloadProgress : null,
            status: _loadingStatus,
            accentColor: accent,
            phase: _loadingPhase,
          ),
        ],
      ),
    );
  }

  /// Apple Pro Window GET pill — solid colored pill in header row.
  /// iOS: Apple Blue solid. B&G: gold gradient with dark text.
  Widget _buildAppleProGetButton({
    required Color accent,
    required Color accentDeep,
    required bool isIos,
  }) {
    final label = _isApplying
        ? (_downloadProgress > 0
            ? '${(_downloadProgress * 100).toInt()}%'
            : '...')
        : LocaleHelper.pick(es: 'OBTENER', en: 'GET');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isApplying ? null : _applyLiveWallpaper,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
          decoration: BoxDecoration(
            gradient: isIos
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [accent, accentDeep],
                  ),
            color: isIos ? accent : null,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.30),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: _isApplying && _downloadProgress == 0
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isIos ? Colors.white : const Color(0xFF1A1300),
                    letterSpacing: 0.4,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color textPrimary,
    required Color textDim,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatSeparator(Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        '·',
        style: TextStyle(
          fontSize: 12,
          color: color.withValues(alpha: 0.4),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color accent,
    required Color surfaceTile,
    required bool isIos,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: surfaceTile,
            borderRadius: BorderRadius.circular(10),
            border: isIos
                ? null
                : Border.all(
                    color: HudTokens.gold.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: accent,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatStat(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  /// Editorial "Códice" layout used when the wallpaper has cultural metadata.
  /// Same lifecycle, ad service, credits, loading overlay — only the chrome
  /// changes (scrollable magazine-style page instead of fullscreen preview).
  Widget _buildCodexScaffold(BuildContext context) {
    final w = widget.wallpaper;
    return Scaffold(
      backgroundColor: context.hud.bg,
      body: Stack(
        children: [
          CodexDetailLayout(
            heroImage: CachedNetworkImage(
              imageUrl: w.previewUrl,
              fit: BoxFit.cover,
              // Hero image grande en CodexDetailLayout (~width pantalla).
              memCacheWidth: 800,
              errorWidget: (_, __, ___) => Container(color: context.hud.bg),
            ),
            title: w.name,
            cultural: w.cultural!,
            applyCta: _buildApplyCta(),
            statusBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: Colors.white,
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.35),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: HudTokens.goldDeep,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        w.typeBadge,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),

          // Loading overlay (download progress) sits on top of everything.
          LoadingOverlay(
            visible: _isApplying,
            progress: _downloadProgress > 0 ? _downloadProgress : null,
            status: _loadingStatus,
            accentColor: _glowColor,
            phase: _loadingPhase,
          ),
        ],
      ),
    );
  }
}
