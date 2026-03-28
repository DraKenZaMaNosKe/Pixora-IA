import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/features/stories/data/models/story.dart';

void main() {
  group('Story.fromJson', () {
    test('parses complete story with frames', () {
      final json = {
        'id': 'story_001',
        'title': 'Dragon Ball Saga',
        'description': 'An epic story',
        'coverImage': 'cover.webp',
        'glowColor': '#FF5722',
        'category': 'ANIME',
        'intervalMinutes': 15,
        'frames': [
          {
            'imageFile': 'frame1.webp',
            'captionEs': 'Hola',
            'captionEn': 'Hello',
            'captionJa': 'こんにちは',
          },
          {
            'imageFile': 'frame2.webp',
            'captionEs': 'Mundo',
            'captionEn': 'World',
            'captionJa': '世界',
          },
        ],
      };

      final s = Story.fromJson(json);

      expect(s.id, 'story_001');
      expect(s.title, 'Dragon Ball Saga');
      expect(s.frames.length, 2);
      expect(s.intervalMinutes, 15);
      expect(s.glowColor, '#FF5722');
    });

    test('uses defaults for missing fields', () {
      final s = Story.fromJson({
        'id': 'minimal',
        'title': 'Minimal',
        'coverImage': 'cover.webp',
      });

      expect(s.description, '');
      expect(s.glowColor, '#7C4DFF');
      expect(s.category, 'STORIES');
      expect(s.intervalMinutes, 30);
      expect(s.frames, isEmpty);
    });
  });

  group('StoryFrame', () {
    test('captionForLang cycles through languages', () {
      final frame = StoryFrame.fromJson({
        'imageFile': 'test.webp',
        'captionEs': 'Español',
        'captionEn': 'English',
        'captionJa': '日本語',
      });

      expect(frame.captionForLang(0), 'Español');
      expect(frame.captionForLang(1), 'English');
      expect(frame.captionForLang(2), '日本語');
      expect(frame.captionForLang(3), 'Español'); // wraps around
      expect(frame.captionForLang(4), 'English');
    });

    test('allCaptions returns all three', () {
      final frame = StoryFrame.fromJson({
        'imageFile': 'test.webp',
        'captionEs': 'A',
        'captionEn': 'B',
        'captionJa': 'C',
      });

      expect(frame.allCaptions, ['A', 'B', 'C']);
    });

    test('falls back to caption field if captionEs missing', () {
      final frame = StoryFrame.fromJson({
        'imageFile': 'test.webp',
        'caption': 'Fallback caption',
      });

      expect(frame.captionEs, 'Fallback caption');
    });
  });
}
