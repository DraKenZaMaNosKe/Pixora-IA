import 'dart:io';

/// Lightweight connectivity check — no extra dependencies.
class Connectivity {
  Connectivity._();

  /// Returns true if device can reach the internet.
  /// Fast: DNS lookup only (~50ms).
  static Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
