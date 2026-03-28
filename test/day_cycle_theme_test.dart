import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/features/day_cycle/data/models/day_cycle_theme.dart';

void main() {
  group('DayCycleTheme.fromJson', () {
    test('parses complete JSON', () {
      final json = {
        'id': 'dc_001',
        'name': 'Sunset Beach',
        'description': 'Beach through the day',
        'previewImage': 'beach_preview.webp',
        'morningImage': 'beach_morning.webp',
        'afternoonImage': 'beach_afternoon.webp',
        'eveningImage': 'beach_evening.webp',
        'nightImage': 'beach_night.webp',
        'glowColor': '#FF9800',
      };

      final t = DayCycleTheme.fromJson(json);

      expect(t.id, 'dc_001');
      expect(t.name, 'Sunset Beach');
      expect(t.description, 'Beach through the day');
      expect(t.morningImage, 'beach_morning.webp');
      expect(t.afternoonImage, 'beach_afternoon.webp');
      expect(t.eveningImage, 'beach_evening.webp');
      expect(t.nightImage, 'beach_night.webp');
      expect(t.glowColor, '#FF9800');
    });

    test('uses defaults for missing fields', () {
      final t = DayCycleTheme.fromJson({});

      expect(t.id, '');
      expect(t.name, '');
      expect(t.glowColor, '#7C4DFF');
    });

    test('allImages returns 4 images in correct order', () {
      final t = DayCycleTheme.fromJson({
        'morningImage': 'a.webp',
        'afternoonImage': 'b.webp',
        'eveningImage': 'c.webp',
        'nightImage': 'd.webp',
      });

      expect(t.allImages, ['a.webp', 'b.webp', 'c.webp', 'd.webp']);
      expect(t.allImages.length, 4);
    });

    test('currentPeriodLabel returns valid period', () {
      final label = DayCycleTheme.currentPeriodLabel();
      expect(['Morning', 'Afternoon', 'Evening', 'Night'], contains(label));
    });

    test('URLs contain Supabase base', () {
      final t = DayCycleTheme.fromJson({
        'previewImage': 'prev.webp',
        'morningImage': 'morn.webp',
      });

      expect(t.previewUrl, contains('supabase'));
      expect(t.morningUrl, contains('morn.webp'));
    });
  });
}
