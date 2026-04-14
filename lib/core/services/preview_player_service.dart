import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../../features/aura/services/aura_player_service.dart';

/// Previews tones and short audio clips using AuraPlayerService's AudioPlayer.
/// Does NOT create its own AudioPlayer — reuses the one already registered
/// with just_audio_background to avoid "Platform player already exists" errors.
class PreviewPlayerService {
  PreviewPlayerService._();
  static final instance = PreviewPlayerService._();

  /// Reuse AuraPlayerService's internal player via a public preview method.
  /// This guarantees only ONE AudioPlayer exists in the entire app.
  Future<void> play({
    required String url,
    required String id,
    required String title,
    String album = 'Pixora Tones',
    String artist = 'Pixora',
  }) async {
    try {
      // Stop whatever AURA is playing
      await AuraPlayerService.instance.stop();

      // Use AuraPlayerService's player for the preview
      await AuraPlayerService.instance.playUrl(
        url: url,
        id: id,
        title: title,
        album: album,
        artist: artist,
      );
    } catch (e) {
      debugPrint('[PreviewPlayer] Play failed: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    await AuraPlayerService.instance.stop();
  }

  Stream<PlayerState>? get playerStateStream =>
      AuraPlayerService.instance.playerStateStream;

  bool get isPlaying => AuraPlayerService.instance.isPlaying;
}
