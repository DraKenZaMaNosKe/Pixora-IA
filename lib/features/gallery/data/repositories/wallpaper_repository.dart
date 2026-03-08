import 'package:supabase_flutter/supabase_flutter.dart';

import '../mock_wallpapers.dart';
import '../models/wallpaper.dart';

abstract class WallpaperRepository {
  Future<List<Wallpaper>> fetchTrending();
}

class MockWallpaperRepository implements WallpaperRepository {
  @override
  Future<List<Wallpaper>> fetchTrending() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return mockWallpapers;
  }
}

class SupabaseWallpaperRepository implements WallpaperRepository {
  SupabaseWallpaperRepository(this.client);

  final SupabaseClient client;

  @override
  Future<List<Wallpaper>> fetchTrending() async {
    final response = await client
        .from('wallpapers')
        .select()
        .order('created_at', ascending: false)
        .limit(30) as List<dynamic>;

    if (response.isEmpty) {
      return mockWallpapers;
    }

    return response
        .map((item) => Wallpaper.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
