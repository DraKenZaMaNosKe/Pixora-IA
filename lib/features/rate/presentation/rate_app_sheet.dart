import 'package:flutter/material.dart';

import '../../../core/design/hud_tokens.dart';
import '../../../core/services/rate_service.dart';
import '../../../core/utils/locale_helper.dart';

/// "¿Nos echas la mano?" — the review ask.
///
/// The five stars are DECORATIVE and must stay that way. Making them tappable
/// and routing by rating (4-5 to the Store, 1-3 to a feedback form) is review
/// gating, which Google Play prohibits. The copy is deliberately
/// sentiment-neutral for the same reason: it asks for a favour, never for an
/// opinion.
///
/// See docs/superpowers/specs/2026-07-15-rate-app-modal-design.md.
class RateAppSheet extends StatelessWidget {
  const RateAppSheet._();

  static Future<void> show(BuildContext context) async {
    final h = context.hud;
    // isScrollControlled + the scroll view below: the Huawei VNS-L53 is
    // 1080x1920 and has produced RenderFlex overflows on sheets before.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: h.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const RateAppSheet._(),
    );
    // Runs on every close, including "¡Calificar!". That is safe because
    // markRated() sets rate_done, which _isEligible() checks before the
    // snooze this writes.
    await RateService.instance.markDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            20 + MediaQuery.of(context).viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: h.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Bundled rather than the 🥹 character: U+1F979 is Emoji 14.0
              // (2021) and minSdk is 24 (Android 7, 2016), so every device
              // below Android 13 renders it as an empty box — in the one
              // sheet where we ask for a good review. Noto Emoji, Apache 2.0.
              Image.asset(
                'assets/rate/face_tears.webp',
                width: 48,
                height: 48,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(height: 12),
              Text(
                LocaleHelper.fromCms(
                  'rate.title',
                  fallbackEs: '¿Nos echas la mano?',
                  fallbackEn: 'Lend us a hand?',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: h.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              // Decorative. Do not wire these to a tap handler — see the
              // class doc.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (_) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(Icons.star, color: h.accent, size: 26),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                LocaleHelper.fromCms(
                  'rate.body',
                  fallbackEs: 'Una reseña tuya vale oro para un estudio '
                      'chiquito como el nuestro.',
                  fallbackEn: 'A review from you is worth its weight in gold '
                      'to a studio as small as ours.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: h.textDim, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  // "Ahora no" gets equal layout weight. It is a real option,
                  // not a decoy.
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: h.text,
                        side: BorderSide(color: h.divider),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        LocaleHelper.fromCms(
                          'rate.cta_no',
                          fallbackEs: 'Ahora no',
                          fallbackEn: 'Not now',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        RateService.instance.markRated();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: h.accent,
                        foregroundColor: h.bg,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        LocaleHelper.fromCms(
                          'rate.cta_yes',
                          fallbackEs: '¡Calificar!',
                          fallbackEn: 'Rate us!',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
