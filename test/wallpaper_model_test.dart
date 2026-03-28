import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/features/wallpapers/data/models/wallpaper.dart';

void main() {
  group('Wallpaper.fromJson', () {
    test('parses complete JSON correctly', () {
      final json = {
        'id': 'wp_001',
        'name': 'Test Wallpaper',
        'description': 'A cool wallpaper',
        'imageFile': 'test.webp',
        'previewFile': 'test_preview.webp',
        'imageSize': 2048000,
        'previewSize': 512000,
        'glowColor': '#FF5722',
        'category': 'ANIME',
        'badge': 'NEW',
        'sortOrder': 5,
        'featured': true,
      };

      final w = Wallpaper.fromJson(json);

      expect(w.id, 'wp_001');
      expect(w.name, 'Test Wallpaper');
      expect(w.description, 'A cool wallpaper');
      expect(w.imageFile, 'test.webp');
      expect(w.previewFile, 'test_preview.webp');
      expect(w.imageSize, 2048000);
      expect(w.previewSize, 512000);
      expect(w.glowColor, '#FF5722');
      expect(w.category, 'ANIME');
      expect(w.badge, 'NEW');
      expect(w.sortOrder, 5);
      expect(w.featured, true);
    });

    test('uses defaults for missing optional fields', () {
      final json = {
        'id': 'wp_002',
        'name': 'Minimal',
      };

      final w = Wallpaper.fromJson(json);

      expect(w.id, 'wp_002');
      expect(w.name, 'Minimal');
      expect(w.description, '');
      expect(w.imageFile, '');
      expect(w.previewFile, '');
      expect(w.imageSize, 0);
      expect(w.previewSize, 0);
      expect(w.glowColor, '#FFFFFF');
      expect(w.category, 'MISC');
      expect(w.badge, isNull);
      expect(w.sortOrder, 0);
      expect(w.featured, false);
    });

    test('toJson round-trips correctly', () {
      final original = Wallpaper.fromJson({
        'id': 'wp_003',
        'name': 'Round Trip',
        'description': 'Test',
        'imageFile': 'img.webp',
        'previewFile': 'prev.webp',
        'imageSize': 1000,
        'previewSize': 500,
        'glowColor': '#00FF00',
        'category': 'NATURE',
        'badge': 'HOT',
        'sortOrder': 3,
        'featured': true,
      });

      final json = original.toJson();
      final restored = Wallpaper.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.category, original.category);
      expect(restored.featured, original.featured);
      expect(restored.badge, original.badge);
    });

    test('imageSizeFormatted returns correct format', () {
      expect(
        Wallpaper.fromJson({'id': 'a', 'name': 'a', 'imageSize': 500}).imageSizeFormatted,
        '500 B',
      );
      expect(
        Wallpaper.fromJson({'id': 'b', 'name': 'b', 'imageSize': 5120}).imageSizeFormatted,
        '5 KB',
      );
      expect(
        Wallpaper.fromJson({'id': 'c', 'name': 'c', 'imageSize': 2097152}).imageSizeFormatted,
        '2.0 MB',
      );
    });

    test('URL generation uses SupabaseConfig', () {
      final w = Wallpaper.fromJson({
        'id': 'url_test',
        'name': 'URL Test',
        'imageFile': 'full.webp',
        'previewFile': 'preview.webp',
      });

      expect(w.fullImageUrl, contains('full.webp'));
      expect(w.previewUrl, contains('preview.webp'));
      expect(w.fullImageUrl, contains('supabase'));
    });
  });
}
