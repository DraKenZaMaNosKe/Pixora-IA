import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/aura_track.dart';
import '../data/repositories/aura_repository.dart';

final auraCatalogProvider = FutureProvider<List<AuraTrack>>((ref) async {
  return AuraRepository.instance.fetchCatalog();
});

final auraFrequenciesProvider = Provider<AsyncValue<List<AuraTrack>>>((ref) {
  final all = ref.watch(auraCatalogProvider);
  return all.whenData(AuraRepository.instance.filterFrequencies);
});

final auraNatureProvider = Provider<AsyncValue<List<AuraTrack>>>((ref) {
  final all = ref.watch(auraCatalogProvider);
  return all.whenData(AuraRepository.instance.filterNature);
});
