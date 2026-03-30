import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ringtone_providers.dart';
import '../../data/models/ringtone_pack.dart';
import 'ringtone_pack_page.dart';

class RingtonesPage extends ConsumerWidget {
  const RingtonesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(ringtonePacksProvider);

    return packsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            const Text('Failed to load ringtones', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(ringtonePacksProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (packs) {
        if (packs.isEmpty) {
          return const Center(
            child: Text('No ringtone packs available yet',
                style: TextStyle(color: Colors.white54)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: packs.length,
          itemBuilder: (context, index) => _PackCard(pack: packs[index]),
        );
      },
    );
  }
}

class _PackCard extends StatelessWidget {
  final RingtonePack pack;
  const _PackCard({required this.pack});

  Color get _glowColor {
    try {
      final hex = pack.glowColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.deepPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RingtonePackPage(pack: pack)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withOpacity(0.05),
          border: Border.all(color: _glowColor.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: _glowColor.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _glowColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.music_note, color: _glowColor, size: 30),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pack.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${pack.tones.length} sounds',
                    style: TextStyle(fontSize: 11, color: _glowColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }
}
