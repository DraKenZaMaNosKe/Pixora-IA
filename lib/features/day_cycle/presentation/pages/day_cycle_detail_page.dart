import 'package:flutter/material.dart';
import '../../../../core/design/hud_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/day_cycle_theme.dart';
import '../../providers/day_cycle_providers.dart';
import '../../../../core/services/day_cycle_service.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/widgets/loading_overlay.dart';

class DayCycleDetailPage extends ConsumerStatefulWidget {
  final DayCycleTheme theme;
  const DayCycleDetailPage({super.key, required this.theme});

  @override
  ConsumerState<DayCycleDetailPage> createState() => _DayCycleDetailPageState();
}

class _DayCycleDetailPageState extends ConsumerState<DayCycleDetailPage> {
  bool _isActivating = false;
  String _progressText = '';
  double _downloadFraction = 0.0;
  LoadingPhase _loadingPhase = LoadingPhase.downloading;

  @override
  void initState() {
    super.initState();
    WallpaperStatsService.instance.trackView('daycycle_${widget.theme.id}');
  }

  final _periods = const [
    {
      'label': 'Morning',
      'time': '6:00 - 12:00',
      'icon': Icons.wb_sunny,
      'color': HudTokens.goldBright
    },
    {
      'label': 'Afternoon',
      'time': '12:00 - 18:00',
      'icon': Icons.wb_cloudy,
      'color': HudTokens.gold
    },
    {
      'label': 'Evening',
      'time': '18:00 - 21:00',
      'icon': Icons.nights_stay,
      'color': HudTokens.goldDeep
    },
    {
      'label': 'Night',
      'time': '21:00 - 6:00',
      'icon': Icons.dark_mode,
      'color': HudTokens.goldDeep
    },
  ];

  List<String> get _imageUrls => [
        widget.theme.morningUrl,
        widget.theme.afternoonUrl,
        widget.theme.eveningUrl,
        widget.theme.nightUrl,
      ];

  Future<void> _activate() async {
    setState(() {
      _isActivating = true;
      _progressText = 'Preparing...';
    });

    // Show alternating ad (awards credits), then activate
    AdService.instance.showInterstitialAd(placement: 'day_cycle_apply', onAdDismissed: () {
      if (mounted) _doActivate();
    });
  }

  Future<void> _doActivate() async {
    WallpaperStatsService.instance.trackDownload('daycycle_${widget.theme.id}');

    if (mounted) {
      setState(() {
        _loadingPhase = LoadingPhase.downloading;
        _progressText = 'Downloading images...';
        _downloadFraction = 0.0;
      });
    }

    final success = await DayCycleService.instance.activate(
      widget.theme,
      target: 0,
      onProgress: (current, total) {
        if (mounted) {
          setState(() {
            _progressText = 'Downloading image $current/$total...';
            _downloadFraction = current / total;
          });
        }
      },
    );

    if (!mounted) return;

    if (success) {
      ref.read(activeDayCycleIdProvider.notifier).state = widget.theme.id;
      setState(() {
        _loadingPhase = LoadingPhase.done;
        _progressText = '${widget.theme.name} activated!';
      });
    } else {
      setState(() {
        _loadingPhase = LoadingPhase.error;
        _progressText = 'Failed to activate. Check your connection.';
      });
    }
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted)
      setState(() {
        _isActivating = false;
        _progressText = '';
      });
  }

  Future<void> _deactivate() async {
    await DayCycleService.instance.deactivate();
    if (mounted) {
      ref.read(activeDayCycleIdProvider.notifier).state = null;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Day cycle deactivated')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(activeDayCycleIdProvider);
    final isActive = activeId == widget.theme.id;
    final currentPeriod = DayCycleTheme.currentPeriodLabel();
    final h = context.hud;
    final isIos = h.isIosStyle;

    return Scaffold(
      backgroundColor: h.bg,
      body: Stack(children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 250,
              pinned: true,
              backgroundColor: h.bg,
              foregroundColor: isIos ? h.text : Colors.white,
              iconTheme: IconThemeData(color: isIos ? h.text : Colors.white),
              flexibleSpace: FlexibleSpaceBar(
                title: Text(widget.theme.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isIos ? h.text : Colors.white,
                      shadows: const [
                        Shadow(blurRadius: 8, color: Colors.black)
                      ],
                    )),
                background: Stack(fit: StackFit.expand, children: [
                  Image.network(widget.theme.previewUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 640,
                      errorBuilder: (_, __, ___) =>
                          Container(color: h.surface)),
                  DecoratedBox(
                      decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, h.bg.withValues(alpha: 0.85)]),
                  )),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.theme.description.isNotEmpty) ...[
                      Text(widget.theme.description,
                          style: TextStyle(
                              color: h.textDim, fontSize: 14, height: 1.5)),
                      const SizedBox(height: 20),
                    ],
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: h.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: h.divider, width: isIos ? 0.5 : 1),
                      ),
                      child: Row(children: [
                        Icon(Icons.access_time, color: h.accent, size: 20),
                        const SizedBox(width: 8),
                        Text('Current period: $currentPeriod',
                            style: TextStyle(
                                color: h.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text('Wallpaper Schedule',
                        style: TextStyle(
                            color: h.text,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...List.generate(
                        4,
                        (i) => _PeriodPreview(
                              label: _periods[i]['label'] as String,
                              time: _periods[i]['time'] as String,
                              icon: _periods[i]['icon'] as IconData,
                              color: isIos
                                  ? h.accent
                                  : (_periods[i]['color'] as Color),
                              imageUrl: _imageUrls[i],
                              isCurrent: currentPeriod == _periods[i]['label'],
                            )),
                    const SizedBox(height: 24),
                    if (_progressText.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Center(
                              child: Text(_progressText,
                                  style: TextStyle(
                                      color: h.textDim, fontSize: 13)))),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isActivating
                            ? null
                            : (isActive ? _deactivate : _activate),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isActive
                              ? (isIos
                                  ? const Color(0xFFFF3B30)
                                  : HudTokens.goldDeep)
                              : h.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isActivating
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(
                                isActive
                                    ? 'Deactivate Day Cycle'
                                    : 'Activate Day Cycle',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
        LoadingOverlay(
          visible: _isActivating,
          progress: _downloadFraction > 0 ? _downloadFraction : null,
          status: _progressText,
          accentColor: context.hud.accent,
          phase: _loadingPhase,
        ),
      ]),
    );
  }
}

class _PeriodPreview extends StatelessWidget {
  final String label, time, imageUrl;
  final IconData icon;
  final Color color;
  final bool isCurrent;
  const _PeriodPreview(
      {required this.label,
      required this.time,
      required this.icon,
      required this.color,
      required this.imageUrl,
      required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isIos ? h.surface : null,
        borderRadius: BorderRadius.circular(14),
        border: isCurrent
            ? Border.all(color: color, width: 2)
            : Border.all(color: h.divider, width: isIos ? 0.5 : 1),
        boxShadow: isIos
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 90,
          child: Row(children: [
            SizedBox(
                width: 130,
                child: Image.network(imageUrl,
                    fit: BoxFit.cover,
                    height: 90,
                    cacheWidth: 260,
                    cacheHeight: 180,
                    errorBuilder: (_, __, ___) => Container(
                        color: h.surface,
                        child: Icon(icon,
                            color: color.withValues(alpha: 0.3), size: 32)))),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(children: [
                            Icon(icon, size: 18, color: color),
                            const SizedBox(width: 6),
                            Text(label,
                                style: TextStyle(
                                    color: h.text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text('NOW',
                                      style: TextStyle(
                                          color: color,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold))),
                            ],
                          ]),
                          const SizedBox(height: 4),
                          Text(time,
                              style: TextStyle(color: h.textDim, fontSize: 12)),
                        ]))),
          ]),
        ),
      ),
    );
  }
}
