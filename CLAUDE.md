# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. Keep it lean — this file is loaded into every session's context.

## Project

**Pixora IA** — Flutter app for Android (primary) and iOS (reduced set) offering wallpapers (static, live video, interactive, shader, day-cycle), stories, ringtones, and the **AURA** wellness audio module. Developed by Orbix Studio.

- Package: `com.orbix.pixora`
- Working branch: `play-store-estable`
- Version: `pubspec.yaml` → `version: X.Y.Z+N`
- iOS gating: everything except `WallpapersPage`, `FavoritesPage`, `SettingsPage` is wrapped in `if (!Platform.isIOS)` in `home_page.dart`

## First 30 seconds of a new session

1. `git status` + `git log --oneline -5` — know where you are
2. Skim this file (you're doing it) for conventions and pitfalls
3. Check `C:\Users\lalo\.claude\projects\D--Orbix-Pixora-IA\memory\MEMORY.md` — persistent user memories
4. If the task touches AURA, also skim `docs/superpowers/plans/2026-04-07-aura-*.md`
5. If the task is business/product (not coding), read the master doc (see §Pointers below)

## Common commands

```bash
# Flutter
flutter pub get
flutter analyze lib/features/<feature>      # scope for speed
flutter build apk --debug                    # → build/app/outputs/flutter-apk/app-debug.apk
flutter build appbundle                      # release AAB for Play Store
flutter run                                  # (ask user first — confirmed device)

# Device testing (Samsung primary: RF8X903KZ3K)
adb devices
adb -s RF8X903KZ3K install -r build/app/outputs/flutter-apk/app-debug.apk
# On INSTALL_FAILED_UPDATE_INCOMPATIBLE (release signature conflict):
adb -s RF8X903KZ3K uninstall com.orbix.pixora && adb -s RF8X903KZ3K install build/app/outputs/flutter-apk/app-debug.apk

# Verify runtime on device
adb -s RF8X903KZ3K logcat -c
adb -s RF8X903KZ3K shell am start -n com.orbix.pixora/.MainActivity
adb -s RF8X903KZ3K logcat -d | grep -E "flutter|Pixora|AndroidRuntime|FATAL"
```

No automated test suite exists. Validation is manual on device.

## Architecture big picture

**Feature-folder layout.** `lib/features/<name>/{data,presentation,providers,services}`. Each feature owns its model, Supabase catalog service, Riverpod providers, pages and widgets. Cross-cutting singletons live in `lib/core/services/`.

**Singleton pattern, not Riverpod for services.** `lib/core/services/*.dart` files expose `SomeService.instance` (plain Dart singletons, `ChangeNotifier` where reactivity is needed). Riverpod is used for UI-level providers (`lib/features/<x>/providers/`).

**Native bridge.** `MainActivity.kt` must extend **`AudioServiceActivity`** (NOT `FlutterActivity`) — required by `just_audio_background`. Exposes `com.orbix.pixora/wallpaper` MethodChannel with `setWallpaper`, `setLiveWallpaper`, `setRingtone`, `startStory`, `startDayCycle`, `startAutoRotate`, `setShaderWallpaper`, `resetEngine`. `PixoraWallpaperService` runs in isolated `:wallpaper` process (see §Pitfalls).

## Cross-cutting singletons (NEVER reimplement)

| Singleton | Purpose | Key rule |
|---|---|---|
| `AdService.instance.showInterstitialAd(onAdDismissed:)` | Interstitial ads | **Every** install/apply/download action MUST go through this. Alternates 1-yes/2-no internally, auto-awards credits on dismissal. |
| `CreditService.instance` | Hive-backed diamond credits (`ChangeNotifier`) | Use `earnFromAd()` / `spend()`. Never mutate `_balance` directly. `_debugDisableAds=true` bypasses ads in dev. |
| `AuthService.instance` | Optional Google Sign-In | App works fully signed-out. Don't gate features behind auth. |
| `WallpaperStatsService.instance.trackView(id)` / `trackDownload(id)` | View/download counts on cards | ID conventions: `tone_<x>`, `tone_pack_<x>`, `aura_<x>`, bare wallpaper id otherwise. |
| `AuraPlayerService.instance` | Sole owner of the `AudioPlayer` for AURA | Sleep timer + loop + background live here. UI reads streams, calls methods — never touches the player directly. |

## Catalog fetching — two patterns, don't mix

1. **Static JSON in Supabase Storage** (wallpapers, live wallpapers, stories, day cycles, ringtones). Template: `lib/core/services/live_wallpaper_catalog_service.dart`. `http.get(storageBase/<bucket>/<catalog>.json)` + 6h in-memory cache.
2. **Postgres table via `supabase_flutter`** (AURA only so far). Template: `lib/features/aura/data/repositories/aura_repository.dart`. `Supabase.instance.client.from('aura_tracks').select()`.

When adding a new content vertical, pick one and stay with it. Don't invent a third.

## Hard-learned pitfalls ⚠️

### A. WallpaperService Surface producer conflict
A `WallpaperService` Engine's Surface accepts **one producer at a time**: Canvas (`lockCanvas`) OR MediaPlayer (`setSurface`). Once Canvas touched it, `MediaPlayer.setSurface()` fails with `setVideoSurfaceTexture -22 (EINVAL)`. `unlockCanvasAndPost()` does NOT release the binding. Switching modes REQUIRES killing the `:wallpaper` process so Android respawns the Engine with a fresh Surface. This is what `MainActivity.killWallpaperProcess()` does on every mode switch. Also why the manifest has `android:process=":wallpaper"` for `PixoraWallpaperService`. **Do not try to share the Surface.** History: commits `cc9da25`, `e871c31`, `061aa1c`.

### B. MainActivity must extend AudioServiceActivity
`just_audio_background` requires the hosting Activity to be `AudioServiceActivity` from `com.ryanheise.audioservice`. Reverting to `FlutterActivity` crashes at startup with `PlatformException: The Activity class declared in your AndroidManifest.xml is wrong`. Fixed in `1b26bee`.

### C. NDK version must match plugins
`android/app/build.gradle` → `ndkVersion "27.0.12077973"`. Plugins request it; downgrading triggers a Gradle warning and can break native builds.

### D. ClockRenderer hourly flash must check minute == 0
`ClockRenderer.kt` triggers a full-screen glow flash when the hour changes. The condition must include `minute <= 1` — otherwise the flash fires when the user unlocks their phone 20 minutes after the hour, which makes no sense. The flash should only fire if the user is looking at the wallpaper at the actual hour change. Fixed in the `hour != lastHour && lastHour >= 0 && minute <= 1` guard.

### E. GitHub Push Protection is active
Secret scanning blocks pushes containing Supabase JWTs, Google OAuth IDs/secrets, Freesound keys, keystore passwords, etc. Before committing anything that might contain a secret (docs, snapshots, config examples), grep for the patterns and redact. If a push is rejected, amend the commit — don't try to force it.

## Feature module map

| Path | What lives there |
|---|---|
| `lib/features/home/` | Bottom nav — 3 parallel lists (`_pages`, `_title`, `BottomNavigationBar.items`) must stay in sync, each non-iOS tab wrapped in `if (!Platform.isIOS)` |
| `lib/features/wallpapers/` | Main static wallpaper grid (always visible, incl. iOS) |
| `lib/features/hot_wallpapers/` | The LIVE tab (video wallpapers + Explore mode, despite the legacy folder name) |
| `lib/features/aura/` | Wellness audio — frequencies + nature, Supabase-backed |
| `lib/features/stories/`, `day_cycle/`, `ringtones/`, `ai_generate/`, `favorites/`, `settings/` | Each a tab |
| `lib/core/services/` | Cross-cutting singletons (see table above) |
| `lib/core/utils/locale_helper.dart` | Tiny ES/EN picker — `LocaleHelper.isSpanish` + `LocaleHelper.pick(es:, en:)`. No `.arb` l10n setup. |
| `lib/core/constants/supabase_config.dart` | URL + anon key (public, in lib) |
| `tools/aura/` | AURA content pipeline (ffmpeg + Python + Supabase uploader). `tracks_manifest.json` is the single source of truth. |
| `docs/superpowers/plans/` | Implementation plans from brainstorming sessions |

## Content dimensions (official Pixora specs)

| Type | Dimensions (px) | Aspect | Notes |
|---|---|---|---|
| Static wallpaper (phone) | 1080 x 2340 | ~9:16 | Portrait, WebP |
| **Panoramic wallpaper** | **4192 x 1024** | **~4:1** | Ultra-wide, scrollable on home. **Generate in Gemini** (Grok doesn't support custom ultra-wide) |
| Video wallpaper (LIVE) | 720p wide, 5-8s | varies | MP4 H.264 baseline, no audio, <2 MB |
| Day Cycle (per image) | 1080 x 2340 | ~9:16 | 4 images: morning/afternoon/evening/night |
| Story frame | 1080 x 2340 | ~9:16 | 4-8 frames per story |
| Preview wallpaper | 540 x 1170 | ~9:16 | WebP, <50 KB |
| Preview video | 720 x 720 | 1:1 | WebP, <50 KB |
| Play Store screenshot | 1080 x 1920 or 1080 x 2340 | 9:16 | Min 2, max 8 |

**AI image generation**: use Gemini for panoramics (4192x1024) and custom sizes. Grok works for standard sizes. Always specify "no text, no letters" in prompts when generating base images for text-overlay features (e.g. cemetery tombstones).

## Conventions

- **Commits**: Conventional Commits scoped by feature. Examples: `feat(aura):`, `fix(live):`, `chore(android):`, `docs:`, `refactor:`, `security:`
- **Bilingual**: use `LocaleHelper` for new user-facing strings in AURA and any feature that needs it. Most legacy features are English-only with occasional inline Spanish.
- **CRLF warnings** on Windows during git add are expected — ignore unless git errors out.
- **Don't create `.md` files** unless explicitly asked.

## Permissions (settings.json) — what's active

Settings live in `.claude/settings.json` (committed, safe defaults) and `.claude/settings.local.json` (gitignored, personal overrides).

**Auto-allowed** (no prompt): reads, git status/log/diff, flutter pub/analyze/build/test, adb devices + install + logcat + shell am/input, ffmpeg/ffprobe, python, Supabase MCP reads (`list_*`, `execute_sql`, `get_*`).

**Will ask first**: `git push`, `git pull`, `git merge`, `gh pr/release`, `apply_migration`, `deploy_edge_function`, `flutter run`, emulator boot, sdkmanager/avdmanager.

**DENIED — don't try**: `rm -rf`, `git reset --hard`, `git rebase`, `git push --force`, `git clean -f`, `filter-branch`, Supabase `pause/restore/delete/create_project`, **Edit/Write on `KEYS_LOCAL.md`**, `android/key.properties`, `*.keystore`, `*.jks`, `**/.env*`, Chrome registry policies, `taskkill /F`.

**Bypass legitimately**: If you need to modify a denied file consciously (e.g. rotate a key), use `Bash(python:*)` to script the edit. The deny is there to block accidental automated edits, not conscious intentional ones.

## Subagents — invoke proactively

**`orbix-dev-guardian`** (Sonnet, color pink, user-scope). Launch after every significant change in Pixora. It runs:
- `flutter analyze` scoped to touched files
- `flutter build apk --debug`
- Install on Samsung + launch + logcat smoke test
- Supabase health check (row counts, 3 sample URLs return 200)
- Master doc snapshot to `docs/master_doc_snapshots/` (gitignored)
- Append a verification sub-section to the master doc
- Emit a structured progress report

Its persistent memory lives at `C:\Users\lalo\.claude\agent-memory\orbix-dev-guardian\`. Delegate validation work to it — it has specialized knowledge and preserves your context.

**When NOT to invoke it**: for mechanical single-line edits, git ops, running a command you can do yourself in 5 seconds.

## Memory system

Two persistent memory stores:

1. **User memory** (main Claude): `C:\Users\lalo\.claude\projects\D--Orbix-Pixora-IA\memory\`
   - `MEMORY.md` is the index — one-line entries, max ~200 lines (truncated after)
   - Each entry is a `.md` file with frontmatter (`name`, `description`, `type: user|feedback|project|reference`)
   - Update when learning user preferences, feedback patterns, project decisions, or external references
   - Don't save code patterns, file paths, or anything derivable from grep

2. **Agent memory** (`orbix-dev-guardian`): `C:\Users\lalo\.claude\agent-memory\orbix-dev-guardian\`
   - Same schema. Builds up cross-project institutional knowledge.

## Ultrathink rule

**Propose** `ultrathink` (or `think hard` for middle ground) before any turn that is expensive to reverse:
- Architecture decisions with multiple valid approaches
- Monetization model choices
- Bugs that resisted 2+ fix attempts
- Code review of critical/risky code pre-release

**Never use silently** — always ask permission first with a short note like *"esto es difícil de revertir, ¿le damos ultrathink?"*. Don't use for mechanical work: git ops, following patterns, typo fixes, adding a tab like an existing one.

Saved as feedback memory `feedback_ultrathink_suggest.md` — persists across sessions.

## Pointers to deeper context

| What you need | Where to find it |
|---|---|
| Business context, mission, history, revenue targets, version log, full secrets inventory | **Master document** (canonical source of truth) at `G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx`. Read via `python-docx`. **Do not mirror its contents here** — it drifts. |
| Secrets (Supabase service role, Google OAuth, keystore, Freesound, Play Console, GitHub PAT) | Master doc §11. Local working copy in `KEYS_LOCAL.md` (gitignored) for scripts — canonical source wins if they diverge. |
| AURA content pipeline design | `docs/superpowers/plans/2026-04-07-aura-content-pipeline.md` |
| AURA app integration design | `docs/superpowers/plans/2026-04-07-aura-app-integration.md` |
| Agent definition | `C:\Users\lalo\.claude\agents\orbix-dev-guardian.md` |

## Master doc update duty

After any of these, append (don't rewrite) a sub-section to the master `.docx` via `python-docx`:

| Trigger | Section |
|---|---|
| New feature shipped | §7 (Arquitectura) + new status sub-section |
| Business/monetization decision | §8 |
| Version bump in `pubspec.yaml` | §12 (Registro de Versiones) |
| New credential added | §11 (never paste the value — reference `KEYS_LOCAL.md`) |
| New platform pitfall learned | Add to "lecciones aprendidas" so it's not re-learned |
| AURA track added/removed | §14.3 or §14.4 |

## Active objectives & pending tasks

The master document is the canonical task tracker. Key sections with actionable objectives:

- **§14 AURA**: melodic frequency tracks (Suno/Udio + ffmpeg layering), binaural beats, guided meditations
- **§16 Art Gallery Wallpapers**: 10 museum scene prompts (5 static + 5 panoramic), interactive zoom-on-tap, Day Cycle museum variant, "Your Personal Museum" customization
- **Cemetery/Memorial**: Día de Muertos configurable tombstones (name + date + phrase overlay), panoramic + normal modes

When starting a session, check the master doc for the latest pending tasks.

## What NOT to do

- ❌ Commit `KEYS_LOCAL.md`, `android/key.properties`, `*.keystore`, `*.jks`, `.env*`, `.claude/settings.local.json`, `tools/aura/out/`, `tools/aura/raw/`, `docs/master_doc_snapshots/` — all gitignored for a reason
- ❌ Mirror master doc business content into CLAUDE.md or the repo (drift)
- ❌ Paste secrets into the repo ever — even in comments, examples, or tests
- ❌ Share a `WallpaperService` Surface between Canvas and MediaPlayer
- ❌ Revert `MainActivity` to extend `FlutterActivity`
- ❌ Reimplement ads, credits, or stats tracking — use the singletons
- ❌ Invent a third catalog fetching pattern
- ❌ Rebase/reset/force-push published branches
- ❌ Use `ultrathink` without asking
- ❌ Skip device testing on Pixora before claiming work is done
