import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/day_cycle_catalog_service.dart';
import '../data/models/day_cycle_theme.dart';

final dayCycleCatalogProvider = FutureProvider<List<DayCycleTheme>>((ref) async {
  return DayCycleCatalogService.instance.fetchCatalog();
});

final activeDayCycleIdProvider = StateProvider<String?>((ref) => null);
