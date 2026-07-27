# Device Identity Unification + Heartbeat Wallpaper Reporting — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the admin "En Vivo" panel correlate real users' events, presence, and installed wallpaper under one `device_id`, without losing any likes.

**Architecture:** Two subsystems generate independent `device_id`s for the same phone (`WallpaperStatsService` → ~10-char, `AnalyticsService` → ~16-char). We crown the AnalyticsService id as canonical (it already bridges to the isolated `:wallpaper` process via `pixora_identity.json`), migrate stats/events rows server-side via an idempotent RPC + `device_aliases` table, make `wp_log_event` alias-aware for the staged rollout, and make the heartbeat report the active wallpaper both from the app (on apply) and from the wallpaper service (on Daily rotation / visibility).

**Tech Stack:** Flutter (Dart), Kotlin (Android `:wallpaper` service), Supabase Postgres (plpgsql RPCs), Hive (local storage).

## Global Constraints

- Package: `com.orbix.pixora`. Production branch = `play-store-estable`; work on `desarrollo`.
- Canonical id = `AnalyticsService.instance.deviceId` (Hive box `analytics`, key `device_id`; bridged to `:wallpaper` via `pixora_identity.json` in `filesDir`).
- NEVER lose likes: the heart flag is Hive key `liked_<wallpaperId>` in box `wallpaper_likes` (id-independent); the aggregate counter lives in `wallpaper_stats.likes` via `increment_likes`/`decrement_likes` (id-independent). Only the ROWS in `wallpaper_likes` (UNIQUE `device_id,wallpaper_id`) carry the id — migrate them server-side, never client-side.
- `wallpaper_events` has partial unique index `idx_we_dedupe_view (device_id, wallpaper_id, ts_minute) WHERE event_type='view'` — any bulk `UPDATE device_id` must delete would-be collisions first.
- RPCs `wp_log_event` and `usage_report` are anon-callable and already trust the client-supplied `p_device_id`; the new merge RPC does not raise that trust ceiling materially, but must be idempotent + guarded.
- No automated test suite exists. Verification = `flutter analyze` (scoped), `flutter build apk --debug`, device smoke test on Samsung `RF8X903KZ3K`, and REST/SQL verification queries.
- SQL migrations apply via `python tools/apply_migration.py <file>` (asks permission per CLAUDE.md).
- Ships in ONE app release (recompile AAB from `play-store-estable`) — bundle with the pending rig/ads AAB.
- `usage_report` merges partial state by key presence (`p_state ? 'active_wallpaper_id'`), so the heartbeat may send state WITHOUT `active_*` (periodic beat) and a separate call WITH `active_*` (on apply) — no SQL change to the merge semantics.
- device_id max length in schema = 80 chars (both `wallpaper_events.device_id` and the RPC guards).

---

### Task 1: SQL migration — `device_aliases` + `migrate_device_identity` RPC + alias-aware `wp_log_event`

**Files:**
- Create: `supabase/migrations/20260726_001_device_identity_unify.sql`
- Reference (do not edit): `supabase/migrations/20260501_006_wallpaper_events.sql` (current `wp_log_event`, lines 50-102)

**Interfaces:**
- Produces: RPC `migrate_device_identity(p_old text, p_new text) returns boolean` (anon-callable, idempotent); table `public.device_aliases(old_id text pk, new_id text, migrated_at timestamptz)`; updated `wp_log_event` that repoints a legacy `p_device_id` to its canonical id at insert time.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/20260726_001_device_identity_unify.sql`:

```sql
-- =============================================================================
-- Device identity unification: alias table + one-shot merge RPC + alias-aware
-- wp_log_event. Safe to apply BEFORE the app release (inert without it).
-- Migration: 20260726_001_device_identity_unify
-- =============================================================================
BEGIN;

-- ── 1) alias mapping (old stats id → canonical analytics id) ──
create table if not exists public.device_aliases (
  old_id      text primary key check (length(old_id) between 1 and 80),
  new_id      text not null       check (length(new_id) between 1 and 80),
  migrated_at timestamptz not null default now()
);
create index if not exists idx_device_aliases_new on public.device_aliases (new_id);
alter table public.device_aliases enable row level security;
-- no policies → service_role only

-- ── 2) one-shot idempotent merge (anon-callable) ──
create or replace function public.migrate_device_identity(p_old text, p_new text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_old is null or p_new is null or length(p_old) = 0 or length(p_new) = 0 then
    raise exception 'both ids required';
  end if;
  if length(p_old) > 80 or length(p_new) > 80 then
    raise exception 'id too long';
  end if;
  if p_old = p_new then
    return true;
  end if;
  -- idempotent: already migrated → success, no-op
  if exists (select 1 from device_aliases where old_id = p_old) then
    return true;
  end if;
  -- anti-chain / anti-cycle
  if exists (select 1 from device_aliases where new_id = p_old)
     or exists (select 1 from device_aliases where old_id = p_new) then
    raise exception 'id already part of an alias mapping';
  end if;
  -- guard: a legacy id that already emits heartbeats is somebody's canonical id
  if exists (select 1 from device_presence where device_id = p_old) then
    raise exception 'old id has presence; refusing to remap';
  end if;

  -- likes: delete would-be duplicates under the new id first, then repoint
  delete from wallpaper_likes l
   where l.device_id = p_old
     and exists (select 1 from wallpaper_likes k
                  where k.device_id = p_new and k.wallpaper_id = l.wallpaper_id);
  update wallpaper_likes set device_id = p_new where device_id = p_old;

  -- events: delete view-dedupe collisions first, then repoint
  delete from wallpaper_events e
   where e.device_id = p_old and e.event_type = 'view'
     and exists (select 1 from wallpaper_events x
                  where x.device_id = p_new and x.event_type = 'view'
                    and x.wallpaper_id = e.wallpaper_id and x.ts_minute = e.ts_minute);
  update wallpaper_events set device_id = p_new where device_id = p_old;

  insert into device_aliases (old_id, new_id) values (p_old, p_new);
  return true;
end$$;
grant execute on function public.migrate_device_identity(text,text) to anon, authenticated;

-- ── 3) alias-aware wp_log_event (staged rollout: old app keeps sending old id) ──
create or replace function public.wp_log_event(
  p_wallpaper_id text,
  p_event_type   text,
  p_device_id    text,
  p_app_version  text default null,
  p_metadata     jsonb default '{}'::jsonb
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_inserted boolean := false;
  v_user_id  uuid := auth.uid();
  v_canon    text;
begin
  if p_event_type not in ('view','preview','install','share','favorite','unfavorite','download') then
    raise exception 'Invalid event_type: %', p_event_type;
  end if;
  if p_device_id is null or length(p_device_id) = 0 then
    raise exception 'device_id required';
  end if;

  -- repoint legacy id → canonical, if an alias exists
  select new_id into v_canon from device_aliases where old_id = p_device_id;
  if v_canon is not null then
    p_device_id := v_canon;
  end if;

  begin
    insert into public.wallpaper_events
      (device_id, user_id, wallpaper_id, event_type, app_version, metadata)
      values (p_device_id, v_user_id, p_wallpaper_id, p_event_type, p_app_version, p_metadata);
    v_inserted := true;
  exception
    when unique_violation then
      v_inserted := false;
  end;

  if v_inserted then
    case p_event_type
      when 'view' then
        update public.wallpapers set view_count = view_count + 1, last_viewed_at = now()
          where id = p_wallpaper_id and published = true;
      when 'install' then
        update public.wallpapers set install_count = install_count + 1, last_installed_at = now()
          where id = p_wallpaper_id and published = true;
      when 'share' then
        update public.wallpapers set share_count = share_count + 1
          where id = p_wallpaper_id and published = true;
      when 'favorite' then
        update public.wallpapers set favorite_count = favorite_count + 1
          where id = p_wallpaper_id and published = true;
      when 'unfavorite' then
        update public.wallpapers set favorite_count = greatest(0, favorite_count - 1)
          where id = p_wallpaper_id and published = true;
      else null;
    end case;
  end if;
  return v_inserted;
end$$;
grant execute on function public.wp_log_event(text,text,text,text,jsonb) to anon, authenticated;

COMMIT;
```

- [ ] **Step 2: Apply the migration**

Run: `python tools/apply_migration.py supabase/migrations/20260726_001_device_identity_unify.sql`
Expected: success, no errors.

- [ ] **Step 3: Verify objects exist + RPC is idempotent/guarded (safe test ids)**

Run this Python (uses service key like the repo scripts):
```python
import json, re, urllib.request
from pathlib import Path
P="https://vzuwvsmlyigjtsearxym.supabase.co"
SK=re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}", Path("KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]
def rpc(fn, body):
    req=urllib.request.Request(f"{P}/rest/v1/rpc/{fn}", data=json.dumps(body).encode(), method="POST")
    req.add_header("apikey",SK); req.add_header("Authorization",f"Bearer {SK}")
    req.add_header("Content-Type","application/json")
    try:
        return urllib.request.urlopen(req,timeout=30).read().decode()
    except urllib.error.HTTPError as e:
        return f"HTTP {e.code}: {e.read().decode()[:200]}"
# fake ids that don't exist anywhere → creates a harmless alias row
print("first :", rpc("migrate_device_identity", {"p_old":"zzt_test_old_1","p_new":"zzt_test_new_1"}))
print("repeat:", rpc("migrate_device_identity", {"p_old":"zzt_test_old_1","p_new":"zzt_test_new_1"}))  # idempotent → true
print("cycle :", rpc("migrate_device_identity", {"p_old":"zzt_test_new_1","p_new":"zzt_test_x"}))       # should error
```
Expected: `first: true`, `repeat: true`, `cycle:` HTTP 400 with "id already part of an alias mapping".

- [ ] **Step 4: Clean up the test alias row**

Run: `python tools/apply_migration.py` is not for DML; instead run inline Python:
```python
# delete the throwaway alias created in Step 3
import re,urllib.request; from pathlib import Path
P="https://vzuwvsmlyigjtsearxym.supabase.co"
SK=re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}", Path("KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]
req=urllib.request.Request(f"{P}/rest/v1/device_aliases?old_id=eq.zzt_test_old_1", method="DELETE")
req.add_header("apikey",SK); req.add_header("Authorization",f"Bearer {SK}")
print(urllib.request.urlopen(req,timeout=30).status)
```
Expected: `204`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260726_001_device_identity_unify.sql
git commit -m "feat(identity): device_aliases + migrate_device_identity RPC + alias-aware wp_log_event"
```

---

### Task 2: Harden `AnalyticsService.deviceId` (in-memory cache)

**Files:**
- Modify: `lib/core/services/analytics_service.dart:115-122`

**Interfaces:**
- Consumes: nothing new.
- Produces: `AnalyticsService.instance.deviceId` returns a STABLE id for the whole process lifetime even if Hive (`_box`) is null — prerequisite for making it the canonical id.

- [ ] **Step 1: Add the in-memory cache field**

In `analytics_service.dart`, near the other private fields of the class (top of the class body, next to `_box`), add:
```dart
  String? _deviceIdCache;
```

- [ ] **Step 2: Rewrite the getter to cache in memory**

Replace lines 115-122 (the current `deviceId` getter):
```dart
  String get deviceId {
    final cached = _box?.get(_deviceIdKey) as String?;
    if (cached != null && cached.isNotEmpty) return cached;
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        Random().nextInt(1 << 32).toRadixString(36);
    _box?.put(_deviceIdKey, id);
    return id;
  }
```
with:
```dart
  String get deviceId {
    final mem = _deviceIdCache;
    if (mem != null && mem.isNotEmpty) return mem;
    final cached = _box?.get(_deviceIdKey) as String?;
    if (cached != null && cached.isNotEmpty) {
      _deviceIdCache = cached;
      return cached;
    }
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        Random().nextInt(1 << 32).toRadixString(36);
    _deviceIdCache = id;      // stable for this process even if Hive is down
    _box?.put(_deviceIdKey, id); // best-effort persist
    return id;
  }
```

- [ ] **Step 3: Verify it analyzes clean**

Run: `flutter analyze lib/core/services/analytics_service.dart`
Expected: No issues found (or only pre-existing warnings unrelated to this file).

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/analytics_service.dart
git commit -m "fix(analytics): cache deviceId in memory so it's stable when Hive fails"
```

---

### Task 3: Delegate stats `_deviceId` to canonical + one-shot migration on init

**Files:**
- Modify: `lib/core/services/wallpaper_stats_service.dart:180-187` (the `_deviceId` getter)
- Modify: `lib/core/services/wallpaper_stats_service.dart:54-58` (`init()`, to trigger migration)

**Interfaces:**
- Consumes: `AnalyticsService.instance.deviceId` (Task 2); `migrate_device_identity` RPC (Task 1).
- Produces: stats events/likes now use the canonical id for NEW writes; existing rows migrated once per device.

- [ ] **Step 1: Confirm the import exists**

Check the top of `wallpaper_stats_service.dart` imports `analytics_service.dart`. If missing, add:
```dart
import 'analytics_service.dart';
```

- [ ] **Step 2: Replace the `_deviceId` getter to delegate**

Replace lines 180-187:
```dart
  /// Device ID for anonymous like tracking.
  String get _deviceId {
    var id = _likesBox?.get('device_id') as String?;
    if (id == null) {
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      _likesBox?.put('device_id', id);
    }
    return id;
  }
```
with:
```dart
  /// Device ID for anonymous like/event tracking.
  ///
  /// 2026-07-26 — Unified with the canonical AnalyticsService id (same id the
  /// heartbeat/presence uses) so events + presence correlate. The old legacy
  /// key `device_id` in the likes box is preserved (not deleted) and used only
  /// by the one-shot server-side migration in [_migrateDeviceIdOnce].
  String get _deviceId => AnalyticsService.instance.deviceId;
```

- [ ] **Step 3: Add the one-shot migration method**

Add this method to the class (e.g. right after the `_deviceId` getter):
```dart
  /// One-shot server-side migration of the legacy stats id → canonical id.
  /// Renames this device's wallpaper_likes + wallpaper_events rows so its
  /// history isn't split. Idempotent server-side; the local flag is only set
  /// on a 2xx so a failure retries next cold start. Legacy key is kept.
  Future<void> _migrateDeviceIdOnce() async {
    try {
      if (_likesBox?.get('device_id_migrated_v1') == true) return;
      final legacy = _likesBox?.get('device_id') as String?;
      final canonical = AnalyticsService.instance.deviceId;
      if (legacy == null || legacy.isEmpty || legacy == canonical) {
        await _likesBox?.put('device_id_migrated_v1', true);
        return;
      }
      await _client.rpc('migrate_device_identity', params: {
        'p_old': legacy,
        'p_new': canonical,
      });
      await _likesBox?.put('device_id_migrated_v1', true);
    } catch (e) {
      debugPrint('[Stats] device_id migration deferred: $e');
      // do NOT set the flag → retried on next cold start
    }
  }
```

- [ ] **Step 4: Trigger the migration in `init()` (non-blocking)**

In `init()`, right after `_likesBox = await Hive.openBox('wallpaper_likes');` (line 58), add:
```dart
    unawaited(_migrateDeviceIdOnce());
```
Confirm `import 'dart:async';` is present for `unawaited` (add if missing).

- [ ] **Step 5: Verify it analyzes clean**

Run: `flutter analyze lib/core/services/wallpaper_stats_service.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/wallpaper_stats_service.dart
git commit -m "feat(stats): delegate device_id to canonical + one-shot server-side migration"
```

---

### Task 4: `PresenceService.reportApplied()` + hook it into `trackInstall`

**Files:**
- Modify: `lib/core/services/presence_service.dart` (add `reportApplied`)
- Modify: `lib/core/services/wallpaper_stats_service.dart:371-378` (`trackInstall`)

**Interfaces:**
- Consumes: `AnalyticsService.instance.deviceId`; `usage_report` RPC partial-state semantics.
- Produces: `PresenceService.instance.reportApplied(String contentId, {required String kind})` — fires one immediate `usage_report` carrying `active_wallpaper_id` so "En Vivo" shows what was just applied.

- [ ] **Step 1: Add `reportApplied` to PresenceService**

In `presence_service.dart`, add this method to the class (after `_ping`):
```dart
  /// Fire an immediate heartbeat that INCLUDES the active wallpaper, called the
  /// moment the user applies one. The periodic beat deliberately omits active_*
  /// (would go stale vs Daily rotation); usage_report merges by key presence,
  /// so this partial state only touches active_kind/active_wallpaper_id.
  Future<void> reportApplied(String contentId, {required String kind}) async {
    try {
      final did = AnalyticsService.instance.deviceId;
      if (did.isEmpty || contentId.isEmpty) return;
      await Supabase.instance.client.rpc('usage_report', params: {
        'p_device_id': did,
        'p_state': {
          'source': 'app',
          if (_appVersion != null) 'app_version': _appVersion,
          'active_kind': kind,
          'active_wallpaper_id': contentId,
          'wallpaper_set_at': DateTime.now().toUtc().toIso8601String(),
        },
        'p_credits': const <dynamic>[],
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Presence] reportApplied failed: $e');
    }
  }
```

- [ ] **Step 2: Hook it into `trackInstall` (wallpapers/scenes only)**

In `wallpaper_stats_service.dart`, replace `trackInstall` (lines 371-378):
```dart
  Future<void> trackInstall(String wallpaperId) async {
    await _logEvent(wallpaperId, 'install');
    try {
      unawaited(MysteryExclusionService.instance.exclude(wallpaperId));
    } catch (e) {
      debugPrint('[Stats] mystery exclude failed: $e');
    }
  }
```
with:
```dart
  Future<void> trackInstall(String wallpaperId) async {
    await _logEvent(wallpaperId, 'install');
    // 2026-07-26 — report the active wallpaper to presence so "En Vivo" shows
    // it. Skip ringtones/stories/ai (not wallpapers). The precise kind is
    // corrected shortly after by UsageAccountant (wallpaper service).
    if (!wallpaperId.startsWith('tone_') &&
        !wallpaperId.startsWith('story_') &&
        wallpaperId != 'ai_generated') {
      unawaited(
          PresenceService.instance.reportApplied(wallpaperId, kind: 'static'));
    }
    try {
      unawaited(MysteryExclusionService.instance.exclude(wallpaperId));
    } catch (e) {
      debugPrint('[Stats] mystery exclude failed: $e');
    }
  }
```

- [ ] **Step 3: Add the PresenceService import if missing**

Check `wallpaper_stats_service.dart` imports. If `presence_service.dart` is not imported, add:
```dart
import 'presence_service.dart';
```

- [ ] **Step 4: Verify it analyzes clean**

Run: `flutter analyze lib/core/services/presence_service.dart lib/core/services/wallpaper_stats_service.dart`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/presence_service.dart lib/core/services/wallpaper_stats_service.dart
git commit -m "feat(presence): report active wallpaper on apply (fills active_wallpaper_id)"
```

---

### Task 5: `UsageAccountant.reportStateOnly()` from `:wallpaper` (Daily rotation + first visible)

**Files:**
- Modify: `android/app/src/main/kotlin/com/orbix/pixora/UsageAccountant.kt` (add `reportStateOnly` + a throttle field; call from `engineVisible` and `wallpaperChanged`)

**Interfaces:**
- Consumes: existing `identity()`, `stateJson(id)`, `postRpc(id, body)`.
- Produces: authoritative `active_wallpaper_id`/`active_kind` from the wallpaper engine, throttled to ≥1 per 10 min, credits empty.

- [ ] **Step 1: Add the throttle field + constant**

Near the other private mutable fields of `UsageAccountant` (e.g. next to `backoffMs`), add:
```kotlin
    private var lastStateReportElapsed = 0L
```
Near the other companion/const values (e.g. next to `RECOVER_DELAY_MS`), add:
```kotlin
    private val STATE_REPORT_MIN_GAP_MS = 10 * 60 * 1000L  // ≥1 state-only report / 10 min
```
(If constants live in a `companion object`, put it there as `const val`.)

- [ ] **Step 2: Add the `reportStateOnly` method**

Add this method to `UsageAccountant` (e.g. after `recoverAndMaybeFlush`):
```kotlin
    /** Report current active-wallpaper state to presence WITHOUT credits.
     *  The only path that can reflect Daily rotation (happens inside the
     *  service) and the engine's ground-truth. Throttled; needs identity file. */
    fun reportStateOnly() {
        val now = SystemClock.elapsedRealtime()
        post {
            if (lastStateReportElapsed != 0L &&
                now - lastStateReportElapsed < STATE_REPORT_MIN_GAP_MS) return@post
            val id = identity() ?: return@post
            val body = JSONObject().apply {
                put("p_device_id", id.deviceId)
                put("p_state", stateJson(id))
                put("p_credits", JSONArray())
            }
            val code = postRpc(id, body)
            if (code in 200..299) lastStateReportElapsed = now
        }
    }
```

- [ ] **Step 3: Call it on first visible**

In `engineVisible()` (lines 100-109), after the existing `post { ... }` block closes, add a call at the end of the function body:
```kotlin
    fun engineVisible() {
        val now = SystemClock.elapsedRealtime()
        val wall = System.currentTimeMillis()
        post {
            visibleCount++
            if (visibleCount == 1 && !occluded && openSegment == null) {
                openSegment(now, wall)
            }
        }
        reportStateOnly()
    }
```

- [ ] **Step 4: Call it on wallpaper change (Daily rotation)**

In `wallpaperChanged()` (lines 141-149), add the call at the end of the function body:
```kotlin
    fun wallpaperChanged() {
        val now = SystemClock.elapsedRealtime()
        val wall = System.currentTimeMillis()
        post {
            if (openSegment != null) closeSegment(now)
            catalogCache = null // catalog may have changed; force a re-read
            if (visibleCount > 0 && !occluded) openSegment(now, wall)
        }
        reportStateOnly()
    }
```

- [ ] **Step 5: Confirm imports**

Verify `UsageAccountant.kt` already imports `org.json.JSONArray` and `org.json.JSONObject` (it uses them in `doFlush`). If `JSONArray` is missing, add:
```kotlin
import org.json.JSONArray
```

- [ ] **Step 6: Verify it builds**

Run: `flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. (Confirm the "✓ Built" line AND a fresh mtime — see memory `tech_build_wrapper_hides_gradle_exit`.)

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/kotlin/com/orbix/pixora/UsageAccountant.kt
git commit -m "feat(usage): reportStateOnly from :wallpaper on visible + Daily rotation"
```

---

### Task 6: Device smoke test + post-deploy verification

**Files:** none (verification only).

- [ ] **Step 1: Install on Samsung and exercise the flows**

```bash
adb -s RF8X903KZ3K install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s RF8X903KZ3K shell am start -n com.orbix.pixora/.MainActivity
```
In the app: apply a wallpaper. This device has BOTH legacy ids, so it exercises the migration.

- [ ] **Step 2: Verify migration ran + presence now carries the wallpaper**

Run (Python with service key):
```python
import json, re, urllib.request
from pathlib import Path
P="https://vzuwvsmlyigjtsearxym.supabase.co"
SK=re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}", Path("KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]
def get(p):
    r=urllib.request.Request(f"{P}/rest/v1/{p}"); r.add_header("apikey",SK); r.add_header("Authorization",f"Bearer {SK}")
    return json.loads(urllib.request.urlopen(r,timeout=30).read())
print("aliases:", len(get("device_aliases?select=old_id,new_id")))
dp=get("device_presence?select=device_id,active_wallpaper_id&limit=1000")
print("presence with active_wallpaper_id:", sum(1 for d in dp if d.get('active_wallpaper_id')), "/", len(dp))
```
Expected: `aliases:` ≥ 1 (the Samsung migrated); `presence with active_wallpaper_id` higher than the pre-fix 18.

- [ ] **Step 3: Verify likes consistency did not drift**

Open the admin dashboard consistency check (`wp_admin_server.py` counter-vs-rows) or run:
```python
# spot-check: the Samsung's likes rows now live under the canonical id
# (compare counts before/after — must not drop)
```
Expected: like counts unchanged for the migrated device.

- [ ] **Step 4: Post-rollout monitoring query (run days after the AAB is live)**

```python
from datetime import datetime, timezone, timedelta
since=(datetime.now(timezone.utc)-timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ")
ev={e['device_id'] for e in get(f"wallpaper_events?select=device_id&ts=gte.{since}&limit=20000") if e.get('device_id')}
dp={d['device_id'] for d in get("device_presence?select=device_id&limit=2000")}
print("events∩presence:", len(ev & dp), "of", len(ev), "active devices")
```
Expected: the intersection grows from 0 as the user base updates.

- [ ] **Step 5: Final commit / handoff note**

No code change. Record results in the master doc §7 verification sub-section and note that the fix requires the new AAB live in Play Store to take effect for real users.

---

## Deployment order

1. **Task 1** (SQL) — apply now; inert without the app, so zero risk.
2. **Tasks 2-5** (Flutter/Kotlin) — one release; recompile AAB from `play-store-estable`, bundle with the pending rig/ads AAB.
3. **Task 6** — smoke test on device pre-release; monitoring query after the AAB is live.

## Trade-offs accepted

- Retroactive correlation only for devices that UPDATE the app; devices that never update stay as `admin_presence_proxy` "estimated" rows (the endpoint merge dedupes once ids coincide).
- One more anon RPC on the attack surface — bounded by UNIQUE constraints + the presence guard; the pipeline already trusts client-supplied ids.
- `active_wallpaper_id` from Dart (`kind:'static'`) may be imprecise for a few minutes until `UsageAccountant.reportStateOnly` corrects the kind — acceptable for a live panel.
- Ringtones/stories are out of scope for `reportApplied` (YAGNI — the ask was wallpapers). The `active_ringtone_*` columns already exist if we extend later.
