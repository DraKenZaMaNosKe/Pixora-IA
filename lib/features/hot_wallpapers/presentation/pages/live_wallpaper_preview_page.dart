import 'dart:io';
import 'dart:ui';
import '../../../../core/design/hud_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
          if (await frameFile.exists() && await frameFile.length() > 100)
            continue;
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
            content: Text('Video deleted from device'),
            backgroundColor: context.hud.accent,
          ),
        );
      }
    }
  }

  Widget _buildApplyCta() {
    final isIos = context.hud.isIosStyle;
    final accent = _glowColor;
    final label = _isApplying
        ? (_downloadProgress > 0
            ? 'Downloading ${(_downloadProgress * 100).toInt()}%'
            : 'Preparing...')
        : 'Set as Live Wallpaper';

    Widget content() => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isApplying)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  strokeWidth: 2,
                  color: isIos ? accent : Colors.white,
                ),
              )
            else
              Icon(Icons.download,
                  size: 20, color: isIos ? accent : Colors.white),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isIos ? Colors.white : Colors.white,
                letterSpacing: isIos ? -0.1 : 0.2,
              ),
            ),
          ],
        );

    if (!isIos) {
      // Black & Gold — solid accent
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _isApplying ? null : _applyLiveWallpaper,
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: content(),
        ),
      );
    }

    // iOS — frosted glass with mint accent glow
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isApplying ? null : _applyLiveWallpaper,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.28),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 20,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: content(),
              ),
            ),
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

    return _buildAppleMusicScaffold(context);
  }

  /// Apple Music "Now Playing" inspired layout.
  /// Wallpaper preview lives inside an album-art square (not fullscreen),
  /// surrounded by cream background with dark text — guarantees readability
  /// regardless of how light or busy the wallpaper itself is.
  Widget _buildAppleMusicScaffold(BuildContext context) {
    final w = widget.wallpaper;
    const bgColor = Color(0xFFFAF7F2);
    const inkColor = Color(0xFF0B0B10);
    const grayMid = Color(0xFF6E6E73);
    const grayLight = Color(0xFFAEAEB2);
    final accent = _glowColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // ──────── Top bar ────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left,
                            color: inkColor, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'REPRODUCIENDO',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: grayMid,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_horiz,
                            color: inkColor, size: 22),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        // ──────── Album art (wallpaper preview) ────────
                        const SizedBox(height: 8),
                        Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.35),
                                    blurRadius: 36,
                                    spreadRadius: -8,
                                    offset: const Offset(0, 16),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedNetworkImage(
                                      imageUrl: w.previewUrl,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => Container(
                                          color: const Color(0xFF1A1A22)),
                                    ),
                                    // LIVE pill top-right
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          w.typeBadge.toUpperCase(),
                                          style: const TextStyle(
                                            fontFamily: 'JetBrainsMono',
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: 1.6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // ──────── Now playing meta ────────
                        Text(
                          'WALLPAPER · ${w.category.toUpperCase()}',
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: accent,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          w.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                            color: inkColor,
                            letterSpacing: -0.6,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          w.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: grayMid,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // ──────── Tags row ────────
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: w.tags
                              .take(5)
                              .map((tag) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0EDE7),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      tag,
                                      style: const TextStyle(
                                        fontFamily: 'JetBrainsMono',
                                        fontSize: 10,
                                        color: grayMid,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 12),
                        // ──────── File info ────────
                        Text(
                          '${(w.videoSize / 1024 / 1024).toStringAsFixed(2)} MB · 6s loop',
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 10,
                            color: grayLight,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 18),
                        // ──────── Controls row (heart / share / info) ────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _AppleMusicIconBtn(
                              icon: Icons.favorite_border,
                              onTap: () {},
                            ),
                            _AppleMusicIconBtn(
                              icon: Icons.ios_share,
                              onTap: () {},
                            ),
                            _AppleMusicIconBtn(
                              icon: Icons.info_outline,
                              onTap: () {},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // ──────── Bottom: CTA + meta ────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Column(
                    children: [
                      // Main CTA button
                      _buildAppleMusicCta(),
                      const SizedBox(height: 10),
                      // FREE / credits info
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
                                    ? const Color(0xFFE8F8EE)
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
                                  color:
                                      isFree ? const Color(0xFF1B7340) : accent,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.diamond, size: 12, color: grayMid),
                            const SizedBox(width: 4),
                            Text(
                              '$credits',
                              style: const TextStyle(
                                fontSize: 11,
                                color: grayMid,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        );
                      }),
                      // Delete from device (if downloaded)
                      FutureBuilder<bool>(
                        future: _isDownloadedFuture,
                        builder: (ctx, snap) {
                          if (snap.data != true) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: TextButton.icon(
                              onPressed: _deleteFromDevice,
                              icon: const Icon(Icons.delete_outline,
                                  size: 16, color: grayLight),
                              label: const Text(
                                'Delete from device',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: grayLight,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
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

  /// CTA pill button styled to match the Apple Music aesthetic
  /// (solid Apple blue background, rounded, white text).
  Widget _buildAppleMusicCta() {
    const appleBlue = Color(0xFF0A84FF);
    const appleBlueDeep = Color(0xFF0066CC);
    final label = _isApplying
        ? (_downloadProgress > 0
            ? 'Downloading ${(_downloadProgress * 100).toInt()}%'
            : (_loadingStatus.isNotEmpty
                ? _loadingStatus
                : LocaleHelper.pick(es: 'Aplicando...', en: 'Applying...')))
        : LocaleHelper.pick(es: 'Establecer Wallpaper', en: 'Set as Wallpaper');

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isApplying ? null : _applyLiveWallpaper,
        style: ElevatedButton.styleFrom(
          backgroundColor: appleBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: appleBlue.withValues(alpha: 0.5),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith(
              (states) => appleBlueDeep.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isApplying) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(Icons.download, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
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

/// Apple Music style icon button — circular tap target with neutral icon.
/// Used in the controls row of the new wallpaper preview page.
class _AppleMusicIconBtn extends StatelessWidget {
  const _AppleMusicIconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Icon(icon, size: 22, color: const Color(0xFF0B0B10)),
      ),
    );
  }
}
