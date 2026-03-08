import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/story_catalog_service.dart';
import '../data/models/story.dart';

final storyCatalogProvider = FutureProvider<List<Story>>((ref) async {
  return StoryCatalogService.instance.fetchCatalog();
});

final activeStoryIdProvider = StateProvider<String?>((ref) => null);
