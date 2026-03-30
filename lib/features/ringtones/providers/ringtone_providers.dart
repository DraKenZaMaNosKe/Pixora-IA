import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/ringtone_service.dart';
import '../data/models/ringtone_pack.dart';

final ringtonePacksProvider = FutureProvider<List<RingtonePack>>((ref) async {
  return RingtoneService.instance.fetchCatalog();
});
