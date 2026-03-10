import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Communicates with the Android native side for story wallpaper rotation.
class StoryRotationService {
  StoryRotationService._();
  static final instance = StoryRotationService._();

  static const _channel = MethodChannel('com.orbix.pixora/wallpaper');

  /// Starts a story rotation: sends image paths and interval to native side.
  /// The native WorkManager will cycle through the images.
  Future<bool> startStory({
    required String storyId,
    required List<String> imagePaths,
    List<String> captions = const [],
    String glowColor = '#7C4DFF',
    required int intervalMinutes,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'startStory',
        {
          'storyId': storyId,
          'imagePaths': imagePaths,
          'captions': captions,
          'glowColor': glowColor,
          'intervalMinutes': intervalMinutes,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[StoryRotation] startStory error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[StoryRotation] startStory unexpected error: $e');
      return false;
    }
  }

  /// Stops the currently running story rotation.
  Future<bool> stopStory() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('stopStory');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[StoryRotation] stopStory error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[StoryRotation] stopStory unexpected error: $e');
      return false;
    }
  }

  /// Gets the current story status: storyId, currentIndex, total frames.
  Future<Map<String, dynamic>?> getStoryStatus() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMethod<Map>('getStoryStatus');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } on PlatformException catch (e) {
      debugPrint('[StoryRotation] getStoryStatus error: ${e.message}');
    } catch (e) {
      debugPrint('[StoryRotation] getStoryStatus unexpected error: $e');
    }
    return null;
  }
}
