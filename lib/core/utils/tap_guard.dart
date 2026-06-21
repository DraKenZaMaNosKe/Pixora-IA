/// Lightweight tap-rate-limiter para botones críticos.
///
/// Cada page que tenga botones con riesgo de doble-tap accidental o spam
/// crea un controller por botón (típicamente como `final` del State) y
/// llama `tryFire()` al inicio del `onPressed`. Si devuelve `false`, el
/// callback simplemente NO se ejecuta — el tap se "swallowea" sin
/// feedback visual (filosofía: el usuario no nota nada raro, simplemente
/// no pasa nada en el segundo tap demasiado rápido).
///
/// Casos de uso típicos:
///   · Botón "APLICAR WALLPAPER" — cooldown 3s. Evita race en
///     WallpaperService nativo (canvas↔video crash 2026-06-10).
///   · Botón ❤ like — cooldown 700ms. Evita saturar RPCs Supabase
///     cuando user martillea el corazón.
///   · Botón ⚐ reportar — cooldown 2s. Evita abrir múltiples modales
///     encimados o crear reportes duplicados (el RPC ya tiene anti-spam
///     pero esto previene el modal mismo).
///
/// Para visual feedback durante el cooldown usar el estado existente
/// del page (ej. `_isApplying` ya disable el botón). El TapGuard solo
/// añade la capa de timing, no de UI.
class TapGuardController {
  TapGuardController({required this.cooldown});

  final Duration cooldown;
  DateTime? _lastFire;

  /// Returns `true` if enough time has passed since the last accepted
  /// tap (and records this moment as the last accepted). Returns
  /// `false` to indicate the tap should be ignored.
  bool tryFire() {
    final now = DateTime.now();
    if (_lastFire != null && now.difference(_lastFire!) < cooldown) {
      return false;
    }
    _lastFire = now;
    return true;
  }

  /// Reset internal state. Use when the page state genuinely changes
  /// (e.g. wallpaper applied successfully, allow re-apply immediately).
  void reset() {
    _lastFire = null;
  }
}
