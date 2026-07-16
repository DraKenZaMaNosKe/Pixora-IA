# Rate App Modal — Design

**Date:** 2026-07-15
**Status:** Approved, pending implementation
**Mockup:** `docs/design/rate_app_modal_variants.html` → variant 5 (`docs/design/shots/rate_5-sheet.png`)

## Goal

Ask users to rate Pixora on the Play Store at a moment when they have just
had a win, without ever stacking the ask on top of an ad, and without
nagging anyone who says no.

## Policy constraints (non-negotiable)

These are Google Play policy, not preferences. Violating them risks the app.

1. **No incentives for reviews.** Variant 4 (diamonds for rating) was rejected
   for this reason. Never reintroduce a reward for rating.
2. **No review gating.** The 5 stars in the sheet are DECORATIVE — drawn full
   and gold, not tappable. Routing only happy users to the Store (e.g. "how
   many stars?" → 4-5 goes to Play, 1-3 goes to a feedback form) is prohibited.
   The pre-prompt is sentiment-neutral by design: "¿Nos echas la mano?" with
   "Ahora no" / "¡Calificar!" asks for a favour, not an opinion.
3. **Custom pre-prompt + In-App Review API is against Google's design
   guidance.** The guidance says not to ask the user anything before the rating
   card appears. We therefore use a `market://` deep link, where a custom
   pre-prompt is the normal, permitted pattern.

## Decisions

| Question | Decision |
|---|---|
| Trigger | After the user successfully applies N wallpapers AND the app is at least M days old |
| Rating flow | Custom sheet (variant 5) → `market://` deep link |
| Ad collision | Only fire on an apply that did NOT show an ad |
| "Ahora no" | Snooze; max 3 prompts in the app's lifetime, then never again |
| Copy source | Text CMS with hardcoded fallbacks |

### Tunables

```dart
static const _minApplies = 3;               // successful applies before asking
static const _minAge = Duration(days: 2);   // since first launch
static const _snooze = Duration(days: 14);  // after "Ahora no"
static const _maxPrompts = 3;               // lifetime cap
```

## Architecture

### `RateService` — `lib/core/services/rate_service.dart`

Plain Dart singleton (`RateService.instance`), matching the other services in
`lib/core/services/`. Not a `ChangeNotifier` — nothing observes its state; the
sheet is pushed imperatively.

State lives in the Hive box `pixora_settings`, the box `onboarding_page.dart`
already uses for `onboarding_seen_v2`. Reusing it avoids a second box for five
scalars.

| Key | Type | Meaning |
|---|---|---|
| `rate_applied_count` | int | Successful applies so far |
| `rate_first_seen_at` | int | Epoch ms of first launch; seeded on first `init()` |
| `rate_prompt_count` | int | Times the sheet has been shown. Incremented when it is SHOWN, not when it is answered, so an ignored sheet still burns budget |
| `rate_snooze_until` | int | Epoch ms; set on dismiss |
| `rate_done` | bool | Rated, or prompt budget spent → never ask again |

Public API:

```dart
Future<void> init();                 // open box, seed rate_first_seen_at
Future<void> recordApplied();        // +1, then maybe show
Future<void> debugForceShow();       // bypass gates, for device testing
```

`recordApplied()` increments the counter and then evaluates eligibility. One
entry point keeps callers from having to know the rules.

### Eligibility

All five must hold:

1. `!rate_done`
2. `rate_applied_count >= _minApplies`
3. `now - rate_first_seen_at >= _minAge`
4. `now >= rate_snooze_until`
5. `!AdService.instance.lastActionShowedAd`

Rule 5 is the one that keeps the ask from landing right after an interstitial.
Because `AdService` alternates 1-yes/2-no, roughly half of applies qualify, so
in practice the sheet appears within an apply or two of becoming eligible —
it waits for a clean moment rather than taking the first one.

### Responses

`rate_prompt_count` is incremented once, at the moment the sheet is shown.
The handlers below therefore never touch it — they only record the outcome.

| User does | Effect |
|---|---|
| Taps "¡Calificar!" | Open the Store (below). On success, `rate_done = true` |
| Taps "Ahora no" | `rate_snooze_until = now + _snooze` |
| Swipes the sheet away | Same as "Ahora no" |

After any of the three, if `rate_prompt_count >= _maxPrompts`, set
`rate_done = true`.

Swipe-to-dismiss is treated as "Ahora no" rather than as a harsher signal.
Someone who flicks a sheet away mid-scroll has not rejected us; they were
busy. Treating that as a permanent no would silently drop most of the people
we would have reached on the second ask.

### `AdService.lastActionShowedAd` (new)

```dart
bool _lastActionShowedAd = false;
bool get lastActionShowedAd => _lastActionShowedAd;
```

Set to `false` in every early return of `showInterstitialAd` (subscriber, Free
Hour, grace pass, debug bypass, alternating skip, ad-not-loaded) and to `true`
only where an ad is actually shown.

This is deliberately a separate field rather than deriving the answer from
`isNextActionFree`. That getter was inverted from at least 2026-05-08 until
2026-07-15 (it drove a "SIN AD" badge that promised no ad and then showed one).
Parity arithmetic read backwards is exactly the trap that produced that bug;
state that says what it means does not have the failure mode.

### Presentation

The sheet is shown through `pixoraNavigatorKey` (`main.dart:42`), so
`RateService` needs no `BuildContext` and no page has to remember to call it.

Guard before showing:
- `pixoraNavigatorKey.currentContext` is non-null (app is mounted)
- `ModalRoute.of(context)?.isCurrent == true` — don't stack the sheet on top of
  another sheet or a dialog

If the guard fails, do nothing and leave the counters intact: the next
qualifying apply tries again.

### `RateAppSheet` — `lib/features/rate/presentation/rate_app_sheet.dart`

`showModalBottomSheet` following the app's existing convention (see
`lib/features/aura/presentation/widgets/sleep_timer_sheet.dart:11-18`):

- `backgroundColor: h.surface` (`context.hud`), never a hardcoded colour
- `RoundedRectangleBorder` with `BorderRadius.vertical(top: Radius.circular(20))`
- 40x4 drag handle in `h.divider`
- `isScrollControlled: true` + `SingleChildScrollView` — the Huawei VNS-L53
  (1080x1920) is the short screen that has caused RenderFlex overflows before

Content, top to bottom: 🥹 emoji · title · five decorative gold stars
(`Icons.star`, `h.accent`) · body copy · two side-by-side buttons with
"Ahora no" as an outlined button and "¡Calificar!" filled.

Both buttons get equal visual weight in layout. "Ahora no" is a real option,
not a decoy.

### Copy — Text CMS

`LocaleHelper.fromCms(key, fallbackEs:, fallbackEn:)` with hardcoded fallbacks,
so the sheet renders correctly before the CMS cache warms.

| Key | ES fallback | EN fallback |
|---|---|---|
| `rate.title` | ¿Nos echas la mano? | Lend us a hand? |
| `rate.body` | Una reseña tuya vale oro para un estudio chiquito como el nuestro. | A review from you is worth its weight in gold to a studio as small as ours. |
| `rate.cta_yes` | ¡Calificar! | Rate us! |
| `rate.cta_no` | Ahora no | Not now |

Rows must be inserted into the Supabase `app_strings` table (via pixora-admin's
TEXTOS tab or SQL) — the client only reads; there is no auto-registration.

### Opening the Store

```dart
market://details?id=com.orbix.pixora
```

via `url_launcher` (already a dependency). If `launchUrl` fails or returns
false, fall back to
`https://play.google.com/store/apps/details?id=com.orbix.pixora`.

`market://` resolves only when the Play Store app is present, which is also why
it does nothing useful on a debug build installed over adb — the https fallback
covers testing.

Set `rate_done = true` when the launch succeeds. We cannot know whether the
user actually left a review (neither `market://` nor the In-App Review API
reports that), and asking again someone who did us the favour is worse than
missing a second chance with someone who didn't.

## Hook

`lib/core/content/content_manager.dart:137`, inside `if (success)` where
`WallpaperStatsService.instance.trackInstall(item.id)` already fires:

```dart
unawaited(RateService.instance.recordApplied());
```

`unawaited` because the install flow must not wait on the prompt.

### Known coverage gap (accepted)

Three flows apply wallpapers without going through `ContentManager` and will
not count toward the trigger:

- `lib/features/arcano/presentation/arcano_page.dart:686` — ARCANO moon phases
- `lib/features/hot_wallpapers/presentation/pages/live_wallpaper_preview_page.dart:229` — Explore frames mode
- `lib/features/realm/services/realm_apply_service.dart:21` — REALM shaders

A user who only ever uses those would never see the sheet. They are minority
flows, and adding them later is one line each. Not doing it now keeps the
change small; this section exists so the gap is a decision on record rather
than a surprise.

## Testing

Manual, on device (Samsung RF8X903KZ3K primary, Huawei G2R4C17516000149 for
the short screen). No automated suite exists in this repo.

1. `debugForceShow()` renders the sheet — check layout on both devices,
   especially no RenderFlex overflow on the Huawei.
2. "¡Calificar!" on a debug build opens the Play listing via the https
   fallback, and `rate_done` flips to `true`.
3. "Ahora no" sets `rate_snooze_until` ~14 days out and increments
   `rate_prompt_count`.
4. Three dismissals set `rate_done` — a fourth `debugForceShow()` bypasses the
   gates by design, so verify the cap by inspecting the Hive values rather than
   by the sheet not appearing.
5. Real trigger path: with the tunables temporarily lowered, apply wallpapers
   and confirm the sheet appears only on an apply that showed no ad.

## Out of scope

- In-App Review API (rejected above on design-guidance grounds)
- Any reward for rating (policy)
- Tappable stars / sentiment routing (policy)
- A "Califícanos" entry in Settings — worth considering later, but it converts
  poorly on its own and is not what this design is for
