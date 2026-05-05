import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/events_service.dart';
import '../data/models/event.dart';

/// Riverpod provider for the seasonal events catalog. Refreshing the
/// invalidate flag (via `ref.invalidate(eventsProvider)`) forces a network
/// re-fetch — used by pull-to-refresh on the EventosPage.
final eventsProvider = FutureProvider<List<PixoraEvent>>((ref) async {
  return EventsService.instance.getEvents();
});

/// Convenience: only the events currently active right now.
/// UI uses this to size the hero polaroid when there's at least one active.
final activeEventsProvider = FutureProvider<List<PixoraEvent>>((ref) async {
  final all = await ref.watch(eventsProvider.future);
  return all.where((e) => e.isActive).toList();
});
