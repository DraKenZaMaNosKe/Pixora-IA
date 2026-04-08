import 'package:flutter/material.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../services/aura_player_service.dart';

class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SleepTimerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEs = LocaleHelper.isSpanishContext(context);
    const options = [5, 10, 15, 20, 30, 45, 60, 90];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bedtime, color: Color(0xFF7C4DFF)),
                const SizedBox(width: 8),
                Text(
                  isEs ? 'Temporizador para dormir' : 'Sleep timer',
                  style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isEs ? 'La música se apagará suavemente' : 'Music will fade out softly',
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: options.map((m) {
                return ElevatedButton(
                  onPressed: () {
                    AuraPlayerService.instance.startSleepTimer(Duration(minutes: m));
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A3E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: Text('$m min', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                AuraPlayerService.instance.cancelSleepTimer();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.cancel_outlined, color: Colors.white54),
              label: Text(
                isEs ? 'Cancelar temporizador' : 'Cancel timer',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
