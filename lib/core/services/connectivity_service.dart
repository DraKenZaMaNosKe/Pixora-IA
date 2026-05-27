import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Singleton que mantiene el estado de conectividad de la app.
///
/// Combina detección pasiva (sin consumir datos) con verificación opcional
/// activa (HEAD request mínimo) ANTES de operaciones críticas — el patrón
/// "graceful degradation" descrito en el sistema offline:
///
/// - [isOnline] refleja si hay WiFi / datos detectados a nivel sistema.
///   Cero bytes consumidos. Se actualiza automáticamente cuando el usuario
///   cambia entre WiFi / datos / modo avión.
/// - [verifyRealConnection] hace un HEAD a un endpoint conocido (~500 bytes)
///   para detectar el caso "WiFi conectado pero sin internet real" (captive
///   portal, ISP caído). Llamar antes de operaciones que NECESITAN red.
/// - [showRestoredToast] dispara solo cuando la conexión estuvo abajo más
///   de 30 segundos — debouncing para evitar ruido visual en flapping
///   (cambios rápidos WiFi↔datos).
///
/// Patrón ChangeNotifier para que los widgets escuchen con AnimatedBuilder
/// o ListenableBuilder, igual que [CreditService] / [AuthService].
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// True solo cuando acaba de regresar la conexión después de >30s offline.
  /// Los widgets que muestran el toast "Conexión restaurada" lo escuchan;
  /// se resetea a false automáticamente 100ms después de dispararse.
  bool _showRestoredToast = false;
  bool get showRestoredToast => _showRestoredToast;

  DateTime? _offlineSince;
  static const Duration _restoredDebounce = Duration(seconds: 30);

  /// Inicializa. Llamar una sola vez al arrancar la app (main.dart).
  Future<void> init() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      _updateFromResults(initial, notify: false);
    } catch (e) {
      debugPrint('[Connectivity] init checkConnectivity failed: $e');
    }
    _sub = _connectivity.onConnectivityChanged.listen(
      _updateFromResults,
      onError: (Object e) {
        debugPrint('[Connectivity] stream error: $e');
      },
    );
  }

  void _updateFromResults(List<ConnectivityResult> results,
      {bool notify = true}) {
    final hasNetwork = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);

    final wasOffline = !_isOnline;
    _isOnline = hasNetwork;

    if (!hasNetwork) {
      _offlineSince ??= DateTime.now();
    } else if (wasOffline) {
      final downtime = _offlineSince == null
          ? Duration.zero
          : DateTime.now().difference(_offlineSince!);
      _offlineSince = null;
      if (downtime >= _restoredDebounce) {
        _triggerRestoredToast();
      }
    }

    if (notify) notifyListeners();
    debugPrint('[Connectivity] online=$_isOnline results=$results');
  }

  void _triggerRestoredToast() {
    _showRestoredToast = true;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 100), () {
      _showRestoredToast = false;
      notifyListeners();
    });
  }

  /// HEAD request rápido a un endpoint conocido para confirmar que SÍ hay
  /// internet real (no solo WiFi conectado a captive portal). Llamar antes
  /// de descargar / aplicar wallpaper nuevo.
  ///
  /// Retorna `true` si el endpoint respondió < 5s, `false` si timeout o
  /// status code != 2xx/3xx.
  Future<bool> verifyRealConnection(
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (!_isOnline) return false;
    try {
      final response = await http
          .head(Uri.parse('https://www.google.com/generate_204'))
          .timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (e) {
      debugPrint('[Connectivity] verifyRealConnection failed: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
