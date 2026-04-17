import 'package:flutter/material.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../data/models/aura_track.dart';
import '../../services/aura_download_service.dart';
import '../../services/aura_player_service.dart';
import '../widgets/sleep_timer_sheet.dart';

class AuraPlayerPage extends StatefulWidget {
  final AuraTrack track;
  const AuraPlayerPage({super.key, required this.track});

  @override
  State<AuraPlayerPage> createState() => _AuraPlayerPageState();
}

class _AuraPlayerPageState extends State<AuraPlayerPage> {
  bool _isDownloading = false;
  String _downloadStatus = '';
  LoadingPhase _downloadPhase = LoadingPhase.downloading;

  Color get _accent => widget.track.colorHex != null
      ? parseHexColor(widget.track.colorHex!, fallback: const Color(0xFF7C4DFF))
      : const Color(0xFF7C4DFF);

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _sleepLabel(BuildContext context) {
    final ends = AuraPlayerService.instance.sleepEndsAt;
    final isEs = LocaleHelper.isSpanishContext(context);
    if (ends == null) return isEs ? 'Temporizador' : 'Timer';
    final left = ends.difference(DateTime.now());
    if (left.isNegative) return isEs ? 'Temporizador' : 'Timer';
    return '${left.inMinutes + 1} min';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final isEs = LocaleHelper.isSpanishContext(context);
    final svc = AuraPlayerService.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(children: [
      Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.4,
            colors: [
              _accent.withOpacity(0.35),
              const Color(0xFF0A0A0F),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      t.category == AuraCategory.frequency
                          ? (isEs ? 'FRECUENCIA' : 'FREQUENCY')
                          : (isEs ? 'NATURALEZA' : 'NATURE'),
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        color: Colors.white.withOpacity(0.5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // Middle section — scrollable so it adapts to any screen height
              // and any description length without overflowing.
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _accent.withOpacity(0.4),
                              _accent.withOpacity(0.05)
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                                color: _accent.withOpacity(0.5),
                                blurRadius: 60,
                                spreadRadius: 4),
                          ],
                        ),
                        child: Center(
                          child: t.category == AuraCategory.frequency
                              ? Text('${t.hz} Hz',
                                  style: const TextStyle(
                                      fontSize: 38,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white))
                              : const Icon(Icons.spa,
                                  size: 80, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(t.displayName,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Text(
                            t.displayDescription,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.75),
                              height: 1.45,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              StreamBuilder<Duration>(
                stream: svc.positionStream,
                builder: (_, snap) {
                  final pos = snap.data ?? Duration.zero;
                  final dur = svc.duration ?? Duration(seconds: t.durationSec);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: _accent,
                            inactiveTrackColor: Colors.white.withOpacity(0.1),
                            thumbColor: _accent,
                            overlayColor: _accent.withOpacity(0.3),
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: pos.inSeconds
                                .toDouble()
                                .clamp(0, dur.inSeconds.toDouble()),
                            max: dur.inSeconds
                                .toDouble()
                                .clamp(1, double.infinity),
                            onChanged: (v) =>
                                svc.seek(Duration(seconds: v.toInt())),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(pos),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.5))),
                            Text(_fmt(dur),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.5))),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: svc,
                builder: (_, __) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.loop,
                          color: svc.loop ? _accent : Colors.white54,
                          size: 26,
                        ),
                        onPressed: () => svc.setLoop(!svc.loop),
                      ),
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accent,
                          boxShadow: [
                            BoxShadow(
                                color: _accent.withOpacity(0.6),
                                blurRadius: 20,
                                spreadRadius: 2),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            svc.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 36,
                          ),
                          onPressed: () =>
                              svc.isPlaying ? svc.pause() : svc.resume(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.stop,
                            color: Colors.white54, size: 26),
                        onPressed: () async {
                          await svc.stop();
                          if (!mounted) return;
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              ListenableBuilder(
                listenable: svc,
                builder: (_, __) {
                  final active = svc.sleepEndsAt != null;
                  return TextButton.icon(
                    onPressed: () => SleepTimerSheet.show(context),
                    icon: Icon(
                      Icons.bedtime,
                      color: active ? _accent : Colors.white54,
                      size: 18,
                    ),
                    label: Text(
                      _sleepLabel(context),
                      style:
                          TextStyle(color: active ? _accent : Colors.white54),
                    ),
                  );
                },
              ),
              TextButton.icon(
                onPressed: _isDownloading
                    ? null
                    : () {
                        setState(() {
                          _isDownloading = true;
                          _downloadPhase = LoadingPhase.downloading;
                          _downloadStatus = isEs
                              ? 'Descargando audio...'
                              : 'Downloading audio...';
                        });
                        AdService.instance.showInterstitialAd(
                            onAdDismissed: () async {
                          WallpaperStatsService.instance
                              .trackDownload('aura_${t.id}');
                          final file =
                              await AuraDownloadService.instance.download(t);
                          if (!mounted) return;
                          setState(() {
                            _downloadPhase = file != null
                                ? LoadingPhase.done
                                : LoadingPhase.error;
                            _downloadStatus = file != null
                                ? (isEs
                                    ? 'Guardado para offline'
                                    : 'Saved for offline')
                                : (isEs
                                    ? 'No se pudo descargar'
                                    : 'Download failed');
                          });
                          await Future.delayed(
                              const Duration(milliseconds: 1200));
                          if (mounted) {
                            setState(() => _isDownloading = false);
                          }
                        });
                      },
                icon:
                    const Icon(Icons.download, size: 18, color: Colors.white54),
                label: Text(
                  isEs ? 'Guardar offline' : 'Save offline',
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      LoadingOverlay(
        visible: _isDownloading,
        status: _downloadStatus,
        accentColor: _accent,
        phase: _downloadPhase,
      ),
      ]),
    );
  }
}
