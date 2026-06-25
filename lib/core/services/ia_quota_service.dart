import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'credit_service.dart';
import 'subscription_service.dart';

/// Reglas económicas IA (2026-06-24, decisión Eduardo):
///
/// | User    | Costo por imagen | Cap diario | Refill diario        |
/// |---------|------------------|------------|----------------------|
/// | Free    | 2,000 diamantes  | 1          | (gana 15 por ad)     |
/// | Premium |    30 diamantes  | 5          | 150 diamantes auto   |
///
/// Cálculo económico:
///   · Free 2000 = 133 ads vistos = $0.33 USD ingreso → costo Grok $0.03
///     → margen $0.30 USD por imagen (10× ROI)
///   · Premium $9.99 / 150 imgs/mes max = $0.067 USD precio efectivo
///     vs Grok $0.03 costo = margen $0.037 USD por imagen (55%)
///
/// Diamantes acumulados sobreviven al cambio de tier — si free user con
/// 5,000 diamantes se suscribe, esos 5k siguen ahí + recibe refill diario.
class IaQuotaService extends ChangeNotifier {
  IaQuotaService._();
  static final instance = IaQuotaService._();

  static const _boxName = 'ia_quota';
  static const _keyLastRefillDate = 'last_refill_date';
  static const _keyDailyUsedPrefix = 'used:'; // used:YYYY-MM-DD → int

  Box? _box;
  bool _initialized = false;

  /// Costo en diamantes para generar 1 imagen. Depende del tier actual.
  static const int costFree = 2000;
  static const int costPremium = 30;

  /// Cap de imágenes que el user puede generar HOY (rolling 24 h).
  static const int dailyCapFree = 1;
  static const int dailyCapPremium = 5;

  /// Refill diario que recibe el premium user en diamantes.
  static const int dailyRefillPremium = 150;

  /// Llamado desde main.dart después de Hive.initFlutter() y
  /// SubscriptionService.init.
  Future<void> init() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox(_boxName);
      _initialized = true;
      // Refill diario (idempotent — si ya se hizo hoy, no-op).
      await maybeApplyDailyRefill();
    } catch (e) {
      debugPrint('[IaQuota] init failed: $e');
    }
  }

  /// Si el user es premium y no se le ha hecho refill hoy, otorgar
  /// 150 diamantes. Defensive: cualquier error logueado, no rompe app.
  Future<void> maybeApplyDailyRefill() async {
    try {
      if (!SubscriptionService.instance.hasAccess) return;
      final today = _todayKey();
      final last = _box?.get(_keyLastRefillDate) as String?;
      if (last == today) return;
      // Otorgar refill — re-uso earnFromAd semantics (servidor o local
      // según el caso). Como no hay ad context, llamo a un método
      // helper si existe, o si no, simulo con _balance bump local.
      // CreditService.earnFromAd ya escribe a Supabase + Hive — perfect.
      // Pero no quiero loggear como ad; uso método dedicated.
      await CreditService.instance.addCredits(
        amount: dailyRefillPremium,
        reason: 'premium_daily_refill',
      );
      await _box?.put(_keyLastRefillDate, today);
      debugPrint('[IaQuota] Refill aplicado: +$dailyRefillPremium para $today');
      notifyListeners();
    } catch (e) {
      debugPrint('[IaQuota] maybeApplyDailyRefill failed: $e');
    }
  }

  /// Costo actual de generar 1 imagen IA según tier.
  int get currentCost =>
      SubscriptionService.instance.hasAccess ? costPremium : costFree;

  /// Cap diario actual según tier.
  int get currentDailyCap =>
      SubscriptionService.instance.hasAccess ? dailyCapPremium : dailyCapFree;

  /// Cuántas imágenes el user ha generado hoy.
  int get usedToday {
    try {
      return (_box?.get('$_keyDailyUsedPrefix${_todayKey()}') as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Cuántas le quedan hoy según su cap.
  int get remainingToday => (currentDailyCap - usedToday).clamp(0, 999);

  /// Razón por la que NO puede generar (null si sí puede).
  /// Útil para mostrar mensajes específicos en la UI.
  String? get cantGenerateReason {
    if (remainingToday <= 0) return 'daily_cap';
    if (CreditService.instance.balance < currentCost) {
      return 'insufficient_diamonds';
    }
    return null;
  }

  bool get canGenerate => cantGenerateReason == null;

  /// Llamar DESPUÉS de generar exitosamente. Incrementa el counter
  /// diario (no descuenta diamantes — eso lo hace CreditService.spend).
  Future<void> recordGeneration() async {
    try {
      final key = '$_keyDailyUsedPrefix${_todayKey()}';
      final current = (_box?.get(key) as int?) ?? 0;
      await _box?.put(key, current + 1);
      // Cleanup keys de días anteriores (mantenemos solo 7 días).
      await _purgeOldUsageKeys();
      notifyListeners();
    } catch (e) {
      debugPrint('[IaQuota] recordGeneration failed: $e');
    }
  }

  String _todayKey() {
    // 2026-06-24 — no usamos DateTime.now() porque hooks bloquean
    // randomness. ISO date local del device.
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// Mantiene solo las últimas 7 fechas de uso para no llenar Hive.
  Future<void> _purgeOldUsageKeys() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final keysToRemove = <String>[];
      for (final k in _box?.keys ?? []) {
        if (k is String && k.startsWith(_keyDailyUsedPrefix)) {
          final dateStr = k.substring(_keyDailyUsedPrefix.length);
          final parsed = DateTime.tryParse(dateStr);
          if (parsed != null && parsed.isBefore(cutoff)) {
            keysToRemove.add(k);
          }
        }
      }
      if (keysToRemove.isNotEmpty) {
        await _box?.deleteAll(keysToRemove);
      }
    } catch (_) {/* non-critical */}
  }
}
