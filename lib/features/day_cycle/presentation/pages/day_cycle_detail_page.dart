import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/day_cycle_theme.dart';
import '../../providers/day_cycle_providers.dart';
import '../../../../core/services/day_cycle_service.dart';
import '../../../../core/services/ad_service.dart';

class DayCycleDetailPage extends ConsumerStatefulWidget {
  final DayCycleTheme theme;
  const DayCycleDetailPage({super.key, required this.theme});

  @override
  ConsumerState<DayCycleDetailPage> createState() => _DayCycleDetailPageState();
}

class _DayCycleDetailPageState extends ConsumerState<DayCycleDetailPage> {
  bool _isActivating = false;
  String _progressText = '';

  final _periods = const [
    {'label': 'Morning', 'time': '6:00 - 12:00', 'icon': Icons.wb_sunny, 'color': Color(0xFFFFB74D)},
    {'label': 'Afternoon', 'time': '12:00 - 18:00', 'icon': Icons.wb_cloudy, 'color': Color(0xFFFF8A65)},
    {'label': 'Evening', 'time': '18:00 - 21:00', 'icon': Icons.nights_stay, 'color': Color(0xFF9575CD)},
    {'label': 'Night', 'time': '21:00 - 6:00', 'icon': Icons.dark_mode, 'color': Color(0xFF5C6BC0)},
  ];

  List<String> get _imageUrls => [
    widget.theme.morningUrl, widget.theme.afternoonUrl,
    widget.theme.eveningUrl, widget.theme.nightUrl,
  ];

  Future<void> _activate() async {
    setState(() { _isActivating = true; _progressText = 'Preparing...'; });

    AdService.instance.showInterstitialAd(onAdDismissed: () {});

    final success = await DayCycleService.instance.activate(
      widget.theme, target: 0,
      onProgress: (current, total) {
        if (mounted) setState(() => _progressText = 'Downloading image $current/$total...');
      },
    );

    if (!mounted) return;

    if (success) {
      ref.read(activeDayCycleIdProvider.notifier).state = widget.theme.id;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.theme.name} day cycle activated!'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to activate. Check your connection.'), backgroundColor: Colors.red),
      );
    }
    setState(() { _isActivating = false; _progressText = ''; });
  }

  Future<void> _deactivate() async {
    await DayCycleService.instance.deactivate();
    if (mounted) {
      ref.read(activeDayCycleIdProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Day cycle deactivated')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(activeDayCycleIdProvider);
    final isActive = activeId == widget.theme.id;
    final currentPeriod = DayCycleTheme.currentPeriodLabel();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250, pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.theme.name,
                style: const TextStyle(fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
              background: Stack(fit: StackFit.expand, children: [
                Image.network(widget.theme.previewUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1A1A2E))),
                const DecoratedBox(decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87]),
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
                    Text(widget.theme.description, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                    const SizedBox(height: 20),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.access_time, color: Colors.white54, size: 20),
                      const SizedBox(width: 8),
                      Text('Current period: $currentPeriod', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  const Text('Wallpaper Schedule', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...List.generate(4, (i) => _PeriodPreview(
                    label: _periods[i]['label'] as String,
                    time: _periods[i]['time'] as String,
                    icon: _periods[i]['icon'] as IconData,
                    color: _periods[i]['color'] as Color,
                    imageUrl: _imageUrls[i],
                    isCurrent: currentPeriod == _periods[i]['label'],
                  )),
                  const SizedBox(height: 24),
                  if (_progressText.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(bottom: 12),
                      child: Center(child: Text(_progressText, style: const TextStyle(color: Colors.white54, fontSize: 13)))),
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: _isActivating ? null : (isActive ? _deactivate : _activate),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isActive ? Colors.red.shade700 : const Color(0xFF7C4DFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isActivating
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isActive ? 'Deactivate Day Cycle' : 'Activate Day Cycle',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodPreview extends StatelessWidget {
  final String label, time, imageUrl;
  final IconData icon;
  final Color color;
  final bool isCurrent;
  const _PeriodPreview({required this.label, required this.time, required this.icon,
    required this.color, required this.imageUrl, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: isCurrent ? Border.all(color: color, width: 2) : Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 90,
          child: Row(children: [
            SizedBox(width: 130, child: Image.network(imageUrl, fit: BoxFit.cover, height: 90,
              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1A1A2E),
                child: Icon(icon, color: color.withOpacity(0.3), size: 32)))),
            Expanded(child: Padding(padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                      child: Text('NOW', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold))),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(time, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]))),
          ]),
        ),
      ),
    );
  }
}
