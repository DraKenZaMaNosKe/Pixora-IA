import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/core/constants/supabase_config.dart';

void main() {
  group('SupabaseConfig', () {
    test('imageUrl builds correct URL', () {
      final url = SupabaseConfig.imageUrl('test.webp');
      expect(url, contains('vzuwvsmlyigjtsearxym.supabase.co'));
      expect(url, contains('wallpaper-images'));
      expect(url, endsWith('test.webp'));
    });

    test('catalogUrl builds correct URL', () {
      final url = SupabaseConfig.catalogUrl();
      expect(url, contains('dynamic_catalog.json'));
      expect(url, contains('storage/v1/object/public'));
    });

    test('imageUrl handles filenames with spaces', () {
      final url = SupabaseConfig.imageUrl('my wallpaper.webp');
      expect(url, contains('my wallpaper.webp'));
    });

    test('storageBase uses correct format', () {
      expect(SupabaseConfig.storageBase, contains('/storage/v1/object/public'));
    });
  });
}
