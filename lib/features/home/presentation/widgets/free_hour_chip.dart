import 'package:flutter/material.dart';

import '../../../../core/services/free_hour_service.dart';
import '../../../../core/services/subscription_service.dart';
import '../../../../core/utils/locale_helper.dart';

/// Discreet AppBar chip for the daily "Free Hour" (ad-free happy hour).
///
/// - Hidden (zero space) when the feature is off or the user is premium.
/// - Idle: a small timer + countdown to the next Free Hour ("3h 24m").
/// - Active: lights up gold — "¡Free! · 23 min".
/// Tapping it opens a short explainer sheet.
class FreeHourChip extends StatelessWidget {
  const FreeHourChip({super.key});

  static const _gold = Color(0xFFD4AF37);

  String _fmt(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '<1m';
  }

  void _explain(BuildContext context, FreeHourState s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F1B17),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.celebration_outlined, color: _gold, size: 22),
              const SizedBox(width: 8),
              Text(
                LocaleHelper.pick(es: 'Hora Free', en: 'Free Hour'),
                style: const TextStyle(
                    color: _gold, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              s.isActive
                  ? LocaleHelper.pick(
                      es:
                          '¡Estás en tu Hora Free! Aplica los wallpapers que quieras SIN anuncios. Te quedan ${_fmt(s.remaining)}.',
                      en:
                          "You're in your Free Hour! Apply all the wallpapers you want with NO ads. ${_fmt(s.remaining)} left.")
                  : LocaleHelper.pick(
                      es: 'Todos los días, a una hora sorpresa, tienes 30 minutos SIN anuncios. Tu próxima Hora Free empieza en ${_fmt(s.timeToNext)}. Te avisamos cuando empiece. 🎉',
                      en: 'Every day, at a surprise time, you get 30 ad-free minutes. Your next Free Hour starts in ${_fmt(s.timeToNext)}. We\'ll ping you when it begins. 🎉'),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 14,
                  height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Premium users don't see it (they're already ad-free forever).
    if (SubscriptionService.instance.hasAccess) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<FreeHourState>(
      valueListenable: FreeHourService.instance.state,
      builder: (context, s, _) {
        if (!s.enabled) return const SizedBox.shrink();
        final active = s.isActive;
        final label = active ? _fmt(s.remaining) : _fmt(s.timeToNext);
        return GestureDetector(
          onTap: () => _explain(context, s),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 108),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: active
                  ? _gold.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                    ? _gold.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active ? Icons.celebration : Icons.timer_outlined,
                  size: 13,
                  color: active ? _gold : Colors.white.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    active ? 'Free $label' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          active ? _gold : Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
