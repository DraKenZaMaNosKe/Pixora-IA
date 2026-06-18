import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../../../core/services/analytics_service.dart';
import '../data/models/aura_track.dart';

class AuraPlayerService extends ChangeNotifier {
  AuraPlayerService._();
  static final instance = AuraPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  AuraTrack? _current;
  bool _loop = true;
  Timer? _sleepTimer;
  DateTime? _sleepEndsAt;

  /// Heartbeat that fires every 30 s while a track is playing — feeds the
  /// `aura_play_tick` event to AnalyticsService so the dashboard can compute
  /// "approx minutes listened" per track. Started on play, stopped on pause/
  /// stop.
  Timer? _listenTick;

  AuraTrack? get current => _current;
  bool get loop => _loop;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  DateTime? get sleepEndsAt => _sleepEndsAt;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> init() async {
    await _player.setLoopMode(LoopMode.one);
    _player.playerStateStream.listen((_) => notifyListeners());
  }

  Future<void> play(AuraTrack track) async {
    // Cancel any pending sleep timer from the previous track AND stop the
    // periodic listen tick — otherwise (audit Sprint 1 fix #4):
    //   · a 5-min timer set on track A keeps running and stops track B too soon
    //   · listen tick of track A keeps emitting aura_play_tick for ID A
    //     while user is actually listening to B → stats wrong
    _cancelSleepTimer();
    _stopListenTick();
    // Guardar el estado anterior para rollback si la carga falla.
    final previous = _current;
    _current = track;
    notifyListeners();
    AnalyticsService.instance.trackAuraStarted(track.id);
    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(track.audioUrl),
          tag: MediaItem(
            id: track.id,
            title: track.displayName,
            album: track.category == AuraCategory.frequency
                ? 'Frequencies'
                : 'Nature',
            artist: 'Pixora · AURA',
            duration: Duration(seconds: track.durationSec),
          ),
        ),
      );
      await _player.setLoopMode(_loop ? LoopMode.one : LoopMode.off);
      await _player.play();
      _startListenTick();
    } catch (e) {
      debugPrint('[Pixora] AURA play failed: $e');
      // Rollback: si la carga falló, el reproductor NO está sonando este
      // track. Restaurar `_current` evita que la UI muestre "playing track X"
      // cuando realmente nada está sonando.
      _current = previous;
      notifyListeners();
    }
  }

  /// Fires `aura_play_tick` every 30 s while `_current` is set and the
  /// player is actually playing. Stops the timer and noops if already
  /// running.
  void _startListenTick() {
    _listenTick?.cancel();
    _listenTick = Timer.periodic(const Duration(seconds: 30), (_) {
      final t = _current;
      if (t == null || !_player.playing) return;
      AnalyticsService.instance.trackAuraPlayTick(
        t.id,
        frequency: t.category == AuraCategory.frequency && t.hz != null
            ? '${t.hz}Hz'
            : null,
      );
    });
  }

  void _stopListenTick() {
    _listenTick?.cancel();
    _listenTick = null;
  }

  /// Play any URL (used by PreviewPlayerService for tone previews).
  /// This reuses the same AudioPlayer already registered with just_audio_background.
  ///
  /// IMPORTANT: this method STOPS any AURA track currently playing because
  /// only one AudioPlayer instance exists across the app. Callers in the
  /// tones preview UI should be aware that hitting "preview" while AURA is
  /// active will stop the user's wellness session. Show a confirm UI before
  /// calling this if AURA is active (`AuraPlayerService.instance.current != null`).
  Future<void> playUrl({
    required String url,
    required String id,
    required String title,
    String album = 'Preview',
    String artist = 'Pixora',
  }) async {
    // Clean teardown of AURA state (sleep timer, listen tick, current track)
    // before hijacking the player for preview. Was leaving timers running.
    _stopListenTick();
    _cancelSleepTimer();
    _current = null;
    notifyListeners();
    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(url),
          tag: MediaItem(
            id: id,
            title: title,
            album: album,
            artist: artist,
          ),
        ),
      );
      await _player.setLoopMode(LoopMode.off);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('[Pixora] playUrl failed: $e');
      rethrow;
    }
  }

  Future<void> pause() async {
    _stopListenTick();
    await _player.pause();
  }

  Future<void> resume() async {
    await _player.play();
    if (_current != null) _startListenTick();
  }

  Future<void> stop() async {
    _stopListenTick();
    _cancelSleepTimer();
    // Aggressive memory release. Just_audio's `stop()` rewinds but keeps
    // decoded buffers + audio source loaded in memory (can be 30-80 MB
    // depending on track length). On 4 GB devices this is what pushes
    // lmkd to kill Pixora when the user taps stop in the system
    // notification (audit logcat 2026-06-18 12:38: lmkd reclaim
    // com.orbix.pixora reason min2x watermark breached). Replacing the
    // source with a tiny silent one ("setAsset" with a 1-byte audio) is
    // the only public API in just_audio 0.9.x that drops the decoder
    // without disposing the singleton.
    try {
      await _player.stop();
    } catch (_) {}
    try {
      // Re-set with empty/dummy URI to drop decoder buffers. If this
      // throws (some platforms validate URI), we just lose the memory
      // optimization; functionality still works.
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse('asset:///')),
        preload: false,
      );
    } catch (_) {}
    _current = null;
    notifyListeners();
  }

  Future<void> seek(Duration position) async => _player.seek(position);

  Future<void> setLoop(bool value) async {
    _loop = value;
    await _player.setLoopMode(value ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }

  // ── Sleep timer ────────────────────────────────────────────────────

  void startSleepTimer(Duration d) {
    _cancelSleepTimer();
    _sleepEndsAt = DateTime.now().add(d);
    _sleepTimer = Timer(d, () async {
      for (var v = _player.volume; v > 0; v -= 0.05) {
        await _player.setVolume(v.clamp(0.0, 1.0));
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await _player.stop();
      await _player.setVolume(1.0);
      _current = null;
      _sleepEndsAt = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndsAt = null;
  }

  void cancelSleepTimer() {
    _cancelSleepTimer();
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelSleepTimer();
    _player.dispose();
    super.dispose();
  }
}
