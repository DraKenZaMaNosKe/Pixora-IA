import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/supabase_service.dart';
import '../data/models/wallpaper.dart';
import '../data/repositories/wallpaper_repository.dart';

final wallpaperRepositoryProvider = Provider<WallpaperRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    return MockWallpaperRepository();
  }
  return SupabaseWallpaperRepository(client);
});

final trendingWallpapersProvider =
    FutureProvider<List<Wallpaper>>((ref) async {
  final repo = ref.watch(wallpaperRepositoryProvider);
  return repo.fetchTrending();
});
