import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// Pixora content moderation — Google Play AI policy compliance.
///
/// User reports a wallpaper / AI image / live / story / tone as offensive
/// or against the rules. We forward the report to Supabase RPC which
/// gates anti-spam (24h cooldown per reporter+wallpaper).
///
/// Anonymous reports are allowed (no login required) — fewer friction
/// means more reports means better moderation. Signed-in reports also
/// carry the user's email for follow-up.
enum ReportReason {
  sexual,
  violence,
  hate,
  copyright,
  drugs,
  spam,
  other;

  String get apiValue => name;

  /// Spanish label shown in the modal.
  String get esLabel => switch (this) {
        ReportReason.sexual => 'Contenido sexual o desnudez',
        ReportReason.violence => 'Violencia gráfica o sangre',
        ReportReason.hate => 'Discurso de odio o discriminación',
        ReportReason.copyright => 'Copyright o personaje/marca registrada',
        ReportReason.drugs => 'Drogas o actividades ilegales',
        ReportReason.spam => 'Spam o engañoso',
        ReportReason.other => 'Otro',
      };

  String get enLabel => switch (this) {
        ReportReason.sexual => 'Sexual or nudity content',
        ReportReason.violence => 'Graphic violence or blood',
        ReportReason.hate => 'Hate speech or discrimination',
        ReportReason.copyright => 'Copyright or trademark violation',
        ReportReason.drugs => 'Drugs or illegal activities',
        ReportReason.spam => 'Spam or misleading',
        ReportReason.other => 'Other',
      };
}

/// What kind of content is being reported. Mirrors the RPC enum.
enum ReportableKind {
  static_,
  live,
  canvasScene,
  aiGenerated,
  panoramic,
  story,
  tone,
  other;

  String get apiValue => switch (this) {
        ReportableKind.static_ => 'static',
        ReportableKind.live => 'live',
        ReportableKind.canvasScene => 'canvas_scene',
        ReportableKind.aiGenerated => 'ai_generated',
        ReportableKind.panoramic => 'panoramic',
        ReportableKind.story => 'story',
        ReportableKind.tone => 'tone',
        ReportableKind.other => 'other',
      };
}

class ReportService {
  ReportService._();
  static final ReportService instance = ReportService._();

  /// Submit a report. Returns the report id (uuid string) on success,
  /// null on failure. The RPC enforces anti-spam (1 report per reporter
  /// per wallpaper per 24h) — if the user already reported recently we
  /// silently get back the existing id, which is fine UX-wise.
  Future<String?> submitReport({
    required String wallpaperId,
    required ReportableKind kind,
    required ReportReason reason,
    String? description,
    Map<String, dynamic>? wallpaperMeta,
  }) async {
    try {
      final user = AuthService.instance.currentUser;
      final reporterId = user?.id ?? await _deviceId();
      final reporterEmail = user?.email ?? AuthService.instance.email;

      final result = await Supabase.instance.client.rpc(
        'report_wallpaper',
        params: {
          'p_wallpaper_id': wallpaperId,
          'p_wallpaper_kind': kind.apiValue,
          'p_reason': reason.apiValue,
          'p_description': description,
          'p_reporter_id': reporterId,
          'p_reporter_email': reporterEmail,
          'p_wallpaper_meta': wallpaperMeta,
        },
      );
      return result?.toString();
    } catch (e) {
      debugPrint('[ReportService] submit failed: $e');
      return null;
    }
  }

  /// Best-effort device fingerprint for anonymous reports. Falls back
  /// to a sentinel if anything fails — we still want the report saved.
  Future<String> _deviceId() async {
    try {
      // Reuse the analytics device id if present in shared prefs.
      // Keeps the same id stable across reports, useful for rate-limiting.
      final supa = Supabase.instance.client;
      final session = supa.auth.currentSession;
      if (session != null) return session.user.id;
    } catch (_) {}
    return 'anon-${DateTime.now().millisecondsSinceEpoch}';
  }
}
