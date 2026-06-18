import 'dart:async';
import 'dart:io';
import '../../../../core/design/hud_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/content/content_manager.dart';
import '../../../../core/content/content_types.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../data/models/live_wallpaper.dart';
import '../../../../core/widgets/codex_detail_layout.dart';
import '../widgets/live_detail_animation_overlay.dart';
import 'package:share_plus/share_plus.dart';

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

  // 2026-06-14 — Like state hidratado al init desde WallpaperStatsService
  // (Hive box local). Toggle dispara el flow completo: optimistic local +
  // RPC increment/decrement_likes + insert/delete en wallpaper_likes table.
  // El HolocardLikeOverlay encima reacciona al statsEventStream y muestra
  // los efectos (Heart Burst + Holo Shimmer + Stack Counter).
  late String _statsId;
  bool _isLiked = false;
  int _likeCount = 0;
  int _viewCount = 0;
  // 2026-06-14 — Guardamos la subscription para cancelarla en dispose.
  // Sin esto, cada apertura del detail registraba un listener nuevo que
  // luego seguía vivo intentando setState sobre el widget desmontado
  // (memory leak + setState after dispose en alta carga Realtime).
  StreamSubscription<StatEvent>? _statsSub;

  Color get _glowColor => context.hud.accent;

  @override
  void initState() {
    super.initState();
    // 2026-06-14 — ID unificado SIN prefijo live_ para que el contador
    // sea el mismo que el del holocard estatico y el grid live. Antes el
    // prefijo creaba una fila separada en wallpaper_stats (live_X vs X)
    // y los likes nunca se sincronizaban entre las dos vistas.
    _statsId = widget.wallpaper.id;
    WallpaperStatsService.instance.trackView(_statsId);
    _isLiked = WallpaperStatsService.instance.hasLiked(_statsId);
    final initial = WallpaperStatsService.instance.getStats(_statsId);
    _likeCount = initial['likes'] ?? 0;
    _viewCount = initial['views'] ?? 0;
    // Listen for any stat event (like, unlike, view, download) — local
    // optimistic + Realtime cross-device. Rebuild so _downloadsText() and
    // friends re-read from the cache.
    _statsSub = WallpaperStatsService.instance.statsEventStream.listen((e) {
      if (!mounted) return;
      if (e.wallpaperId != _statsId) return;
      setState(() {
        if (e.type == 'like' || e.type == 'unlike') {
          _likeCount = e.newValue;
          _isLiked = WallpaperStatsService.instance.hasLiked(_statsId);
        } else if (e.type == 'view') {
          _viewCount = e.newValue;
        }
        // For download events the cache is already updated by
        // WallpaperStatsService — this setState just triggers a rebuild
        // so the displayed counter picks up the new value.
      });
    });
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    super.dispose();
  }

  Future<void> _onLikeTap() async {
    // Optimistic visual flip first for snappy UX. WallpaperStatsService
    // toggleLike() is idempotent via internal Hive box + mutex.
    setState(() => _isLiked = !_isLiked);
    await WallpaperStatsService.instance.toggleLike(_statsId);
  }

  Future<void> _onShareTap() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${widget.wallpaper.name} · Pixora IA live wallpaper\nhttps://pixora.app',
          subject: widget.wallpaper.name,
        ),
      );
      WallpaperStatsService.instance.trackShare(_statsId);
    } catch (_) {}
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
    // trackDownload removed here — ContentManager.downloadAndInstall
    // (line ~217) handles it AFTER the download succeeds. Was causing
    // double-counting + inflated counter on failed downloads.

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
      WallpaperStatsService.instance.trackInstall(_statsId);

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

    return _buildNeonEditorialScaffold(context);
  }

  /// Neon Editorial Magazine — concept #04 (Eduardo 2026-06-14).
  ///
  /// Layout magazine-style con tipografia bold Bungee Inline + accent
  /// amarillo + grid 2x2 de info-blocks + pull-quote cyan + CTA amarillo
  /// flat con shadow offset. Boton LIKE wire al WallpaperStatsService
  /// (toggleLike). HolocardLikeOverlay encima dispara los efectos visuales
  /// cuando este wallpaper recibe un like (local o remote via Realtime).
  Widget _buildNeonEditorialScaffold(BuildContext context) {
    final w = widget.wallpaper;
    const bgDeep = Color(0xFF0A001A);
    const yellow = Color(0xFFFFE44D);
    const cyan = Color(0xFF00F0FF);
    const red = Color(0xFFFF3B5C);
    const text = Color(0xFFE8E0FF);

    final issueNum = (w.id.hashCode.abs() % 999).toString().padLeft(3, '0');

    return Scaffold(
      backgroundColor: bgDeep,
      body: Stack(
        children: [
          // Background gradient mesh subtil
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.4),
                  radius: 1.2,
                  colors: [
                    Color(0x33FF2BD6),
                    Color(0xFF0A001A),
                  ],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Back ─────────────────────────────────────────
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chevron_left,
                              color: yellow, size: 22),
                          Text(
                            LocaleHelper.pick(es: 'Live', en: 'Live'),
                            style: GoogleFonts.shareTechMono(
                              color: yellow,
                              fontSize: 12,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Header strip: ISSUE + BOLD TITLE ────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ISSUE №$issueNum · ${_monthYearEs()} · LIVE',
                          style: GoogleFonts.shareTechMono(
                            color: yellow,
                            fontSize: 10,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _bungeeTitle(w.name, yellow, text),
                      ],
                    ),
                  ),

                  // ── Video stage with LIVE tag + yellow borders ──
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: yellow, width: 4),
                        bottom: BorderSide(color: yellow, width: 4),
                      ),
                    ),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: w.previewUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 800,
                            errorWidget: (_, __, ___) =>
                                const ColoredBox(color: bgDeep),
                          ),
                          // LIVE pulsing badge
                          Positioned(
                            top: 10,
                            left: 10,
                            child: _livePulseBadge(red),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Info grid 2x2 ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(
                              child:
                                  _infoBlock('LIKES', _likeCount.toString())),
                          const SizedBox(width: 12),
                          Expanded(
                              child:
                                  _infoBlock('VIEWS', _viewCount.toString())),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _infoBlock('DOWNLOADS', _downloadsText())),
                          const SizedBox(width: 12),
                          Expanded(child: _infoBlock('SIZE', _sizeText(w))),
                        ]),
                      ],
                    ),
                  ),

                  // ── Pull quote ──────────────────────────────────
                  if (w.description != null && w.description!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: cyan, width: 2),
                          right: BorderSide(color: cyan, width: 2),
                        ),
                      ),
                      child: Text(
                        '"${w.description}"',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSerifDisplay(
                          fontStyle: FontStyle.italic,
                          fontSize: 14,
                          color: text,
                          height: 1.4,
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // ── CTA principal OBTENER ──────────────────────
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _obtainButton(yellow, bgDeep),
                  ),

                  // ── 2 secundarios: LIKE / COMPARTIR ────────────
                  // (DESCARGAR removido 2026-06-14 — el flujo de descarga
                  // se hace via "APLICAR WALLPAPER" arriba, no como acción
                  // separada. Evita redundancia y descarga sin propósito.)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Row(
                      children: [
                        Expanded(
                            child: _secBtn(
                          icon: _isLiked ? '♥' : '♡',
                          label: LocaleHelper.pick(es: 'LIKE', en: 'LIKE'),
                          highlighted: _isLiked,
                          onTap: _onLikeTap,
                        )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _secBtn(
                          icon: '⇄',
                          label:
                              LocaleHelper.pick(es: 'COMPARTIR', en: 'SHARE'),
                          highlighted: false,
                          onTap: _onShareTap,
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Animation overlay: PRINT STAMP (sello editorial) + TICKER
          // TAPE (live feed bottom) — combo 1+5 elegido por Eduardo
          // 2026-06-14. Reacciona a statsEventStream filtrado por _statsId
          // (like local, like remoto, view remoto, download).
          LiveDetailAnimationOverlay(wallpaperId: _statsId),

          // ── Loading overlay durante apply ────────────────────
          LoadingOverlay(
            visible: _isApplying,
            progress: _downloadProgress > 0 ? _downloadProgress : null,
            status: _loadingStatus,
            accentColor: yellow,
            phase: _loadingPhase,
          ),
        ],
      ),
    );
  }

  String _monthYearEs() {
    const months = [
      'ENE',
      'FEB',
      'MAR',
      'ABR',
      'MAY',
      'JUN',
      'JUL',
      'AGO',
      'SEP',
      'OCT',
      'NOV',
      'DIC'
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.year}';
  }

  String _downloadsText() {
    final n =
        WallpaperStatsService.instance.getStats(_statsId)['downloads'] ?? 0;
    return n.toString();
  }

  String _sizeText(LiveWallpaper w) {
    final bytes = w.videoSize;
    if (bytes <= 0) return '~';
    final mb = bytes / (1024 * 1024);
    return mb >= 10 ? '${mb.toStringAsFixed(0)}M' : '${mb.toStringAsFixed(1)}M';
  }

  Widget _bungeeTitle(String name, Color accent, Color text) {
    // Split por la primera palabra para el efecto "primera línea blanca,
    // segunda accent" del diseño elegido.
    final parts = name.split(' ');
    final first = parts.first;
    final rest = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          first.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.bungeeInline(
            fontSize: 28,
            color: text,
            height: 1,
            letterSpacing: -0.5,
          ),
        ),
        if (rest.isNotEmpty)
          Text(
            rest.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.bungeeInline(
              fontSize: 28,
              color: accent,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
      ],
    );
  }

  Widget _livePulseBadge(Color red) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: red,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _BlinkingDot(),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: GoogleFonts.goldman(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBlock(String label, String value) {
    const yellow = Color(0xFFFFE44D);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0x0DFFE44D),
        border: Border(left: BorderSide(color: yellow, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.shareTechMono(
              color: yellow,
              fontSize: 9,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.bungeeInline(
              color: const Color(0xFFE8E0FF),
              fontSize: 22,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _obtainButton(Color yellow, Color bgDeep) {
    final label = _isApplying
        ? (_downloadProgress > 0
            ? '${(_downloadProgress * 100).toInt()}%'
            : '...')
        : LocaleHelper.pick(es: '▼ OBTENER WALLPAPER', en: '▼ GET WALLPAPER');
    return GestureDetector(
      onTap: _isApplying ? null : _applyLiveWallpaper,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: yellow,
          boxShadow: [
            BoxShadow(
              color: bgDeep,
              offset: const Offset(6, 6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.blackOpsOne(
              color: bgDeep,
              fontSize: 16,
              letterSpacing: 4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _secBtn({
    required String icon,
    required String label,
    required bool highlighted,
    required VoidCallback onTap,
  }) {
    const text = Color(0xFFE8E0FF);
    const red = Color(0xFFFF3B5C);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: highlighted ? red : Colors.transparent,
          border: Border.all(
              color: highlighted ? red : text.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              icon,
              style: TextStyle(
                fontSize: 18,
                color: highlighted ? Colors.white : text,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.shareTechMono(
                fontSize: 10,
                color: highlighted ? Colors.white : text,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Placeholder kept for back-compat with imports — old AppleProScaffold removed.
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

/// Punto blanco que parpadea — usado dentro del LIVE badge en el Neon
/// Editorial scaffold para reforzar la sensación de "en vivo".
class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_ctrl),
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
