import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../data/models/aura_track.dart';

class AuraPlayerService extends ChangeNotifier {
  AuraPlayerService._();
  static final instance = AuraPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  AuraTrack? _current;
  bool _loop = true;
  Timer? _sleepTimer;
  DateTime? _sleepEndsAt;

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
    _current = track;
    notifyListeners();
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
    } catch (e) {
      debugPrint('[Pixora] AURA play failed: $e');
    }
  }

  /// Play any URL (used by PreviewPlayerService for tone previews).
  /// This reuses the same AudioPlayer already registered with just_audio_background.
  Future<void> playUrl({
    required String url,
    required String id,
    required String title,
    String album = 'Preview',
    String artist = 'Pixora',
  }) async {
    _current = null;
    _cancelSleepTimer();
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

  Future<void> pause() async => _player.pause();
  Future<void> resume() async => _player.play();

  Future<void> stop() async {
    await _player.stop();
    _current = null;
    _cancelSleepTimer();
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
