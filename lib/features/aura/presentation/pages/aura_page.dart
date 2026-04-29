import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../data/models/aura_track.dart';
import '../../providers/aura_providers.dart';
import '../../services/aura_player_service.dart';
import '../widgets/aura_track_card.dart';
import 'aura_player_page.dart';

class AuraPage extends ConsumerStatefulWidget {
  const AuraPage({super.key});

  @override
  ConsumerState<AuraPage> createState() => _AuraPageState();
}

class _AuraPageState extends ConsumerState<AuraPage> {
  AuraCategory _tab = AuraCategory.frequency;
  bool _isOpening = false;

  void _openTrack(AuraTrack track) {
    if (_isOpening) return; // Guard: prevent spam taps
    _isOpening = true;
    AdService.instance.showInterstitialAd(onAdDismissed: () async {
      await AuraPlayerService.instance.play(track);
      if (!mounted) {
        _isOpening = false;
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AuraPlayerPage(track: track),
      ));
      _isOpening = false; // Reset after returning from player page
    });
  }

  @override
  Widget build(BuildContext context) {
    final freqs = ref.watch(auraFrequenciesProvider);
    final nature = ref.watch(auraNatureProvider);
    final list = _tab == AuraCategory.frequency ? freqs : nature;
    final isEs = LocaleHelper.isSpanishContext(context);

    return Scaffold(
      backgroundColor: context.hud.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.spa, color: context.hud.accent, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AURA',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          isEs
                              ? 'Sonidos para sanar, descansar y dormir'
                              : 'Sounds to heal, rest and sleep',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _Segmented(
                value: _tab,
                onChanged: (v) => setState(() => _tab = v),
                isEs: isEs,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: list.when(
                data: (tracks) {
                  if (tracks.isEmpty) {
                    return Center(
                      child: Text('No tracks yet',
                          style: TextStyle(color: context.hud.textDim)),
                    );
                  }
                  return ListenableBuilder(
                    listenable: AuraPlayerService.instance,
                    builder: (_, __) {
                      final currentId = AuraPlayerService.instance.current?.id;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: tracks.length,
                        itemBuilder: (_, i) {
                          final t = tracks[i];
                          return AuraTrackCard(
                            track: t,
                            isPlaying: t.id == currentId,
                            onTap: () => _openTrack(t),
                          );
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: const TextStyle(color: HudTokens.goldDeep)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final AuraCategory value;
  final ValueChanged<AuraCategory> onChanged;
  final bool isEs;
  const _Segmented(
      {required this.value, required this.onChanged, required this.isEs});

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: h.isIosStyle ? h.surface : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: h.isIosStyle
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _seg(context, AuraCategory.frequency,
              isEs ? 'Frecuencias' : 'Frequencies'),
          _seg(context, AuraCategory.nature, isEs ? 'Naturaleza' : 'Nature'),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, AuraCategory cat, String label) {
    final h = context.hud;
    final selected = value == cat;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(cat),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          decoration: BoxDecoration(
            color: selected
                ? (h.isIosStyle ? h.bg : h.accent)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected && h.isIosStyle
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color:
                  selected ? (h.isIosStyle ? h.text : Colors.white) : h.textDim,
            ),
          ),
        ),
      ),
    );
  }
}
