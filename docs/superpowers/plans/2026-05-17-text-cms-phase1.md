# Pixora Admin Text CMS — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get the smoke-test version of the Text CMS working end-to-end so Eduardo can edit 4 strings of the `parallax_wallpapers_page.dart` (3D · TILT section) from `pixora-admin` and see them update on his Samsung after an app restart.

**Architecture:** New Postgres tables in Supabase (`app_sections` + `app_components` + `app_strings`) consumed by the existing `wp_admin_server.py` (extends with 5 HTTP endpoints) and by a new `AppStringsService` singleton in Flutter that caches via Hive (TTL 1h). A new `TEXTOS` tab in `dashboard/index.html` renders the 3D · TILT screen pixel-close to the real app, with click-to-edit modals. Strings flow: admin edits → server upserts → app refetches on next cold-start (FCM push deferred to optional Task 11).

**Tech Stack:** Supabase Postgres + RLS, Python `http.server` (no Flask), vanilla JavaScript (no frameworks), Flutter + Hive + http package, FCM (subscribe-only in Phase 1).

**Spec:** `docs/superpowers/specs/2026-05-17-text-cms-design.md` (approved 2026-05-17)

**Spec adjustment (resolved during planning):** the spec says "3 strings of WallpaperPreviewPage" but inspection of the actual code shows the 3D · TILT screen lives in `lib/features/parallax_wallpapers/presentation/pages/parallax_wallpapers_page.dart` and contains **4 strings**, not 3 (the title "Profundidad curada." is rendered as two `Text.rich` parts: `'Profundidad\n'` + `'curada.'` because the second part has a shimmer effect). All 4 will be migrated in Task 9.

---

## File Structure

**Create (5 new files):**
- `supabase/migrations/20260518_001_text_cms.sql` — 3 tables + RLS + trigger
- `tools/wallpapers/_seed_text_cms.py` — one-shot seed script for the 4 smoke-test strings (kept under `_` prefix because it's a one-shot; cleaned up if not needed long-term)
- `lib/core/services/app_strings_service.dart` — new ChangeNotifier singleton (follows the `AdService.instance` pattern from `lib/core/services/ad_service.dart:19-21`)

**Modify (5 existing files):**
- `tools/wallpapers/wp_admin_server.py` — add 5 endpoints (read existing pattern at lines 70-200 for handler shape)
- `tools/wallpapers/dashboard/index.html` — add `TEXTOS` tab in the nav + WYSIWYG render section + edit modal + bulk-save logic
- `lib/core/utils/locale_helper.dart` — add `fromCms()` method (existing file is 23 lines; preserve `pick()` exactly)
- `lib/main.dart:111-112` — wire `AppStringsService.instance.initialize()` after `PushNotificationService.instance.init()` and before `AdService.instance.initialize()`
- `lib/features/parallax_wallpapers/presentation/pages/parallax_wallpapers_page.dart:78,91,106,122` — migrate 4 hardcoded strings to `LocaleHelper.fromCms(...)` calls

**Optional (Task 11, can be skipped):**
- `tools/wallpapers/_fcm_push.py` — FCM HTTP v1 API helper (requires service account JSON setup)

---

## Conventions

- **Commits:** Conventional Commits scoped by feature. Use scope `text-cms` for everything in this plan (`feat(text-cms): ...`, `chore(text-cms): ...`).
- **No automated tests:** Pixora has no test suite (CLAUDE.md). Verification is manual via `flutter analyze`, `flutter build apk --debug`, `adb install`, and `adb logcat`.
- **Singleton pattern for `AppStringsService`:** copy the exact shape from `AdService` (`AdService._()` private constructor + `static final instance = AdService._()`).
- **Eduardo's manual steps:** clearly marked with 🧑‍💻 emoji — these are things only he can do (test on his device, edit a string in the admin UI for the smoke test, etc.).

---

## Task 1: Migration SQL

**Files:**
- Create: `supabase/migrations/20260518_001_text_cms.sql`

- [ ] **Step 1: Create the migration file**

Write the exact SQL below to `supabase/migrations/20260518_001_text_cms.sql`:

```sql
-- Pixora Admin Text CMS — Phase 1 tables (2026-05-18)
-- Spec: docs/superpowers/specs/2026-05-17-text-cms-design.md
--
-- Three normalized tables for the editable string registry.
-- The Flutter app reads via the anon key (RLS allows read).
-- pixora-admin writes via service_role key (no INSERT/UPDATE/DELETE policies,
-- so anon is implicitly blocked from mutating).

CREATE TABLE IF NOT EXISTS public.app_sections (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  order_index INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.app_components (
  id           SERIAL PRIMARY KEY,
  section_id   INT NOT NULL REFERENCES public.app_sections(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  file_path    TEXT,
  description  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(section_id, name)
);

CREATE TABLE IF NOT EXISTS public.app_strings (
  id            SERIAL PRIMARY KEY,
  component_id  INT NOT NULL REFERENCES public.app_components(id) ON DELETE CASCADE,
  key           TEXT NOT NULL UNIQUE,
  es            TEXT NOT NULL,
  en            TEXT NOT NULL,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_app_strings_component_id ON public.app_strings(component_id);
CREATE INDEX IF NOT EXISTS idx_app_strings_key          ON public.app_strings(key);

ALTER TABLE public.app_sections   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_strings    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon can read sections"   ON public.app_sections;
DROP POLICY IF EXISTS "anon can read components" ON public.app_components;
DROP POLICY IF EXISTS "anon can read strings"    ON public.app_strings;

CREATE POLICY "anon can read sections"
  ON public.app_sections   FOR SELECT TO anon USING (true);
CREATE POLICY "anon can read components"
  ON public.app_components FOR SELECT TO anon USING (true);
CREATE POLICY "anon can read strings"
  ON public.app_strings    FOR SELECT TO anon USING (true);

CREATE OR REPLACE FUNCTION public.bump_app_strings_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_strings_updated_at ON public.app_strings;
CREATE TRIGGER trg_app_strings_updated_at
BEFORE UPDATE ON public.app_strings
FOR EACH ROW EXECUTE FUNCTION public.bump_app_strings_updated_at();
```

- [ ] **Step 2: Commit the migration**

```bash
git add supabase/migrations/20260518_001_text_cms.sql
git commit -m "feat(text-cms): add migration for app_sections + app_components + app_strings"
```

**Acceptance:** file exists, commit landed, branch still `play-store-estable`.

---

## Task 2: Apply migration to Supabase

**Files:** none modified (DB-only change)

- [ ] **Step 1: Apply via existing helper**

Run:
```bash
python tools/apply_migration.py supabase/migrations/20260518_001_text_cms.sql
```

Expected output: `OK applied 20260518_001_text_cms.sql (~2,400 bytes)`.

If the command errors with `psycopg2.errors.UndefinedFile` for `KEYS_LOCAL.md`, confirm the file exists at `D:/Orbix/Pixora-IA/KEYS_LOCAL.md`. If the script fails on connection, the IPv4 add-on may have lapsed — check `db.vzuwvsmlyigjtsearxym.supabase.co` resolves to an IPv4 (CLAUDE.md notes the paid add-on was enabled 2026-05-05).

- [ ] **Step 2: Verify the 3 tables exist**

Create a temporary inspection script (we'll delete it after this task — it's a one-time verification):

`tools/_verify_text_cms_tables.py`:
```python
# -*- coding: utf-8 -*-
import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
import re
from pathlib import Path
import psycopg2

KEYS = Path(__file__).resolve().parent.parent / "KEYS_LOCAL.md"
pw = re.search(r"Database password:\s*([A-Za-z0-9_!@#%^&*+=:.\-]+)", KEYS.read_text(encoding="utf-8")).group(1)
conn = psycopg2.connect(f"postgresql://postgres:{pw}@db.vzuwvsmlyigjtsearxym.supabase.co:5432/postgres", connect_timeout=15)
cur = conn.cursor()
cur.execute("""
  SELECT table_name FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name IN ('app_sections','app_components','app_strings')
  ORDER BY table_name;
""")
rows = [r[0] for r in cur.fetchall()]
print("Tables found:", rows)
assert rows == ['app_components', 'app_sections', 'app_strings'], f"Missing tables: expected 3, got {rows}"
print("OK - all 3 tables present")
conn.close()
```

Run:
```bash
python tools/_verify_text_cms_tables.py
```

Expected output:
```
Tables found: ['app_components', 'app_sections', 'app_strings']
OK - all 3 tables present
```

- [ ] **Step 3: Cleanup inspection script**

```bash
rm tools/_verify_text_cms_tables.py
```

**Acceptance:** 3 tables exist in `public` schema; no extra files left in the repo.

---

## Task 3: Seed the 4 smoke-test strings

**Files:**
- Create: `tools/wallpapers/_seed_text_cms.py`

- [ ] **Step 1: Write the seed script**

Write to `tools/wallpapers/_seed_text_cms.py`:

```python
# -*- coding: utf-8 -*-
"""Seed the 4 smoke-test strings for the 3D - TILT section.

Inserts one app_section (WALLPAPERS), one app_component
(ParallaxWallpapersPage), and four app_strings.

Idempotent: re-running updates the strings to the values defined here.
"""
import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

import re
from pathlib import Path
import psycopg2

KEYS = Path(__file__).resolve().parent.parent.parent / "KEYS_LOCAL.md"
pw = re.search(r"Database password:\s*([A-Za-z0-9_!@#%^&*+=:.\-]+)", KEYS.read_text(encoding="utf-8")).group(1)

DSN = f"postgresql://postgres:{pw}@db.vzuwvsmlyigjtsearxym.supabase.co:5432/postgres"

SECTION_NAME = "WALLPAPERS"
COMPONENT = {
    "name": "ParallaxWallpapersPage",
    "file_path": "lib/features/parallax_wallpapers/presentation/pages/parallax_wallpapers_page.dart",
    "description": "Pantalla 3D - TILT (parallax wallpapers grid + editorial header)",
}

STRINGS = [
    {
        "key": "wallpapers.tilt_3d.badge_count_label",
        "es": "piezas curadas",
        "en": "curated pieces",
    },
    {
        "key": "wallpapers.tilt_3d.title_part1",
        "es": "Profundidad",
        "en": "Curated",
    },
    {
        "key": "wallpapers.tilt_3d.title_part2",
        "es": "curada.",
        "en": "depth.",
    },
    {
        "key": "wallpapers.tilt_3d.subtitle",
        "es": "el equipo de Pixora elige - semanal",
        "en": "Pixora's team picks - weekly",
    },
]


def main():
    conn = psycopg2.connect(DSN, connect_timeout=15)
    cur = conn.cursor()

    # Upsert section
    cur.execute(
        """INSERT INTO app_sections (name, order_index) VALUES (%s, %s)
           ON CONFLICT (name) DO UPDATE SET order_index = EXCLUDED.order_index
           RETURNING id""",
        (SECTION_NAME, 1),
    )
    section_id = cur.fetchone()[0]
    print(f"section_id={section_id} ({SECTION_NAME})")

    # Upsert component
    cur.execute(
        """INSERT INTO app_components (section_id, name, file_path, description)
           VALUES (%s, %s, %s, %s)
           ON CONFLICT (section_id, name) DO UPDATE
             SET file_path = EXCLUDED.file_path,
                 description = EXCLUDED.description
           RETURNING id""",
        (section_id, COMPONENT["name"], COMPONENT["file_path"], COMPONENT["description"]),
    )
    component_id = cur.fetchone()[0]
    print(f"component_id={component_id} ({COMPONENT['name']})")

    # Upsert strings
    for s in STRINGS:
        cur.execute(
            """INSERT INTO app_strings (component_id, key, es, en)
               VALUES (%s, %s, %s, %s)
               ON CONFLICT (key) DO UPDATE
                 SET es = EXCLUDED.es, en = EXCLUDED.en, component_id = EXCLUDED.component_id""",
            (component_id, s["key"], s["es"], s["en"]),
        )
        print(f"  string {s['key']:40} ES={s['es'][:30]!r}")

    conn.commit()
    cur.close()
    conn.close()
    print("OK - seed applied")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the seed**

```bash
python tools/wallpapers/_seed_text_cms.py
```

Expected output:
```
section_id=1 (WALLPAPERS)
component_id=1 (ParallaxWallpapersPage)
  string wallpapers.tilt_3d.badge_count_label    ES='piezas curadas'
  string wallpapers.tilt_3d.title_part1          ES='Profundidad'
  string wallpapers.tilt_3d.title_part2          ES='curada.'
  string wallpapers.tilt_3d.subtitle             ES='el equipo de Pixora elige - se'
OK - seed applied
```

- [ ] **Step 3: Commit the seed script**

```bash
git add tools/wallpapers/_seed_text_cms.py
git commit -m "feat(text-cms): seed 4 smoke-test strings for 3D TILT section"
```

**Acceptance:** running the script a second time prints the same lines without errors (idempotent). The seed script is committed and available for re-run.

---

## Task 4: Backend endpoints in `wp_admin_server.py`

**Files:**
- Modify: `tools/wallpapers/wp_admin_server.py`

**Pattern reference:** the existing file uses a single `BaseHTTPRequestHandler` subclass with `do_GET` and `do_POST` methods that route by path. Read lines 100-200 (the existing handler) to match the style. Add new branches to the existing routing — do not create a new server file.

- [ ] **Step 1: Add CATALOG-style constants near the top (~line 70)**

Find the existing `CATALOGS = {...}` dict (around line 62) and add below it:

```python
# Text CMS — Phase 1 endpoints (2026-05-18)
# Reads/writes go through this server (which holds service_role).
# Plan: docs/superpowers/plans/2026-05-17-text-cms-phase1.md
TEXT_CMS_FCM_TOPIC = 'text_cms_update'  # used by Task 11 (FCM push)
```

- [ ] **Step 2: Add helper for Supabase REST calls (if not already present)**

Search the file for `_supabase_request` or similar helper. If a helper exists, reuse it. If not, add (near the existing helpers, around line 90):

```python
def _supabase_rest(method: str, table_path: str, body=None, query: str = "") -> tuple[int, dict | list]:
    """Generic Supabase REST helper using service_role.
    Returns (status_code, parsed_body)."""
    url = f"{SUPABASE_REST}/{table_path}"
    if query:
        url += f"?{query}"
    req = urllib.request.Request(
        url,
        method=method,
        headers={
            "apikey": SERVICE_KEY,
            "Authorization": f"Bearer {SERVICE_KEY}",
            "Content-Type": "application/json",
            "Prefer": "return=representation,resolution=merge-duplicates",
        },
        data=json.dumps(body).encode("utf-8") if body is not None else None,
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = resp.read().decode("utf-8") if resp.length != 0 else "null"
            parsed = json.loads(data) if data and data != "null" else None
            return resp.status, parsed
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode("utf-8", errors="replace")}
```

- [ ] **Step 3: Add the 5 endpoints to the request handler**

Find the existing `do_GET` method in the handler class. Locate where existing routes are dispatched (likely `if self.path.startswith('/api/...'): ...`). Add the following handler methods and route them.

First add the helper methods inside the handler class (place after the existing `_send_json` or similar):

```python
def _handle_strings_tree(self):
    """GET /api/strings/tree — returns nested [{section, components: [...]}, ...] for admin UI."""
    # 1. sections
    s_status, sections = _supabase_rest("GET", "app_sections", query="select=id,name,order_index&order=order_index.asc,name.asc")
    if s_status != 200:
        return self._send_json(500, sections)
    # 2. components
    c_status, components = _supabase_rest("GET", "app_components", query="select=id,section_id,name,file_path,description&order=name.asc")
    if c_status != 200:
        return self._send_json(500, components)
    # 3. strings
    st_status, strings = _supabase_rest("GET", "app_strings", query="select=id,component_id,key,es,en,updated_at&order=key.asc")
    if st_status != 200:
        return self._send_json(500, strings)
    # Build tree
    comp_by_section = {}
    for c in components or []:
        comp_by_section.setdefault(c["section_id"], []).append({**c, "strings": []})
    strings_by_component = {}
    for s in strings or []:
        strings_by_component.setdefault(s["component_id"], []).append(s)
    for sid, comps in comp_by_section.items():
        for c in comps:
            c["strings"] = strings_by_component.get(c["id"], [])
    tree = []
    for sec in sections or []:
        tree.append({
            "id": sec["id"],
            "name": sec["name"],
            "order_index": sec["order_index"],
            "components": comp_by_section.get(sec["id"], []),
        })
    self._send_json(200, tree)


def _handle_strings_upsert(self, body: dict):
    """POST /api/strings/upsert — body: {key, es, en, component_id}."""
    required = {"key", "es", "en", "component_id"}
    if not required.issubset(body.keys()):
        return self._send_json(400, {"error": f"missing fields: {required - body.keys()}"})
    status, resp = _supabase_rest(
        "POST", "app_strings",
        body={"key": body["key"], "es": body["es"], "en": body["en"], "component_id": body["component_id"]},
        query="on_conflict=key",
    )
    if status not in (200, 201):
        return self._send_json(status, resp)
    # Phase 1: no FCM push yet (deferred to Task 11). Just return updated row.
    self._send_json(200, {"ok": True, "row": resp[0] if isinstance(resp, list) else resp})


def _handle_strings_bulk_upsert(self, body: list):
    """POST /api/strings/bulk-upsert — body: [{key, es, en, component_id}, ...]."""
    if not isinstance(body, list) or not body:
        return self._send_json(400, {"error": "body must be a non-empty array"})
    status, resp = _supabase_rest("POST", "app_strings", body=body, query="on_conflict=key")
    if status not in (200, 201):
        return self._send_json(status, resp)
    self._send_json(200, {"ok": True, "count": len(body), "rows": resp})


def _handle_strings_seed(self, body: list):
    """POST /api/strings/seed — body: [{section, component, file_path, key, es, en}, ...].
    Creates sections/components on demand. Used for mass migration in Phase 2+."""
    if not isinstance(body, list) or not body:
        return self._send_json(400, {"error": "body must be a non-empty array"})
    section_ids = {}
    component_ids = {}
    sections_created = 0
    components_created = 0
    strings_upserted = 0
    for row in body:
        # section
        sec_name = row.get("section")
        if not sec_name:
            return self._send_json(400, {"error": f"missing 'section' in {row}"})
        if sec_name not in section_ids:
            st, r = _supabase_rest("POST", "app_sections",
                body={"name": sec_name, "order_index": 0}, query="on_conflict=name")
            if st not in (200, 201):
                return self._send_json(st, r)
            section_ids[sec_name] = r[0]["id"] if isinstance(r, list) else r["id"]
            sections_created += 1
        # component
        comp_name = row.get("component")
        comp_key = f"{sec_name}/{comp_name}"
        if not comp_name:
            return self._send_json(400, {"error": f"missing 'component' in {row}"})
        if comp_key not in component_ids:
            st, r = _supabase_rest("POST", "app_components",
                body={
                    "section_id": section_ids[sec_name],
                    "name": comp_name,
                    "file_path": row.get("file_path"),
                    "description": row.get("description"),
                },
                query="on_conflict=section_id,name")
            if st not in (200, 201):
                return self._send_json(st, r)
            component_ids[comp_key] = r[0]["id"] if isinstance(r, list) else r["id"]
            components_created += 1
        # string
        st, r = _supabase_rest("POST", "app_strings",
            body={"component_id": component_ids[comp_key], "key": row["key"], "es": row["es"], "en": row["en"]},
            query="on_conflict=key")
        if st not in (200, 201):
            return self._send_json(st, r)
        strings_upserted += 1
    self._send_json(200, {
        "ok": True,
        "sections_seen": len(section_ids),
        "components_seen": len(component_ids),
        "strings_upserted": strings_upserted,
    })


def _handle_strings_public(self):
    """GET /api/strings/public — flat [{key, es, en}, ...] for Flutter client.
    No metadata, ready to cache."""
    status, rows = _supabase_rest("GET", "app_strings", query="select=key,es,en")
    if status != 200:
        return self._send_json(status, rows)
    self._send_json(200, rows)
```

Now wire them into `do_GET` and `do_POST`. Inside `do_GET`, before the catch-all `else`:

```python
if self.path == '/api/strings/tree':
    return self._handle_strings_tree()
if self.path == '/api/strings/public':
    return self._handle_strings_public()
```

Inside `do_POST`, before the catch-all `else`:

```python
if self.path == '/api/strings/upsert':
    body = self._read_json_body()
    return self._handle_strings_upsert(body)
if self.path == '/api/strings/bulk-upsert':
    body = self._read_json_body()
    return self._handle_strings_bulk_upsert(body)
if self.path == '/api/strings/seed':
    body = self._read_json_body()
    return self._handle_strings_seed(body)
```

If `_read_json_body` doesn't exist in the handler, add this helper method:

```python
def _read_json_body(self):
    length = int(self.headers.get('Content-Length', 0))
    if length == 0:
        return None
    raw = self.rfile.read(length).decode('utf-8')
    return json.loads(raw) if raw else None
```

- [ ] **Step 4: Restart the admin server**

The server is likely already running from a previous session. 🧑‍💻 **Eduardo manually:** kill the existing process (close the terminal window where it runs, or check `tasklist | findstr python` and `taskkill /PID <pid>`), then re-launch:

```powershell
python tools/wallpapers/wp_admin_server.py
```

(Or double-click `tools/wallpapers/launch_admin_silent.vbs` if that's the usual launcher.)

- [ ] **Step 5: Commit backend changes**

```bash
git add tools/wallpapers/wp_admin_server.py
git commit -m "feat(text-cms): add 5 backend endpoints for string read/write"
```

**Acceptance:** server starts without errors, no crash on import.

---

## Task 5: Smoke-test backend endpoints

**Files:** none modified (verification only)

- [ ] **Step 1: Verify `/api/strings/tree` returns the seed**

```bash
curl -s http://127.0.0.1:5757/api/strings/tree
```

Expected output (formatted):
```json
[{
  "id": 1, "name": "WALLPAPERS", "order_index": 1,
  "components": [{
    "id": 1, "section_id": 1, "name": "ParallaxWallpapersPage",
    "file_path": "lib/features/parallax_wallpapers/presentation/pages/parallax_wallpapers_page.dart",
    "description": "Pantalla 3D - TILT (parallax wallpapers grid + editorial header)",
    "strings": [
      {"id": 1, "key": "wallpapers.tilt_3d.badge_count_label", "es": "piezas curadas", "en": "curated pieces", ...},
      {"id": 2, "key": "wallpapers.tilt_3d.title_part1",        "es": "Profundidad",    "en": "Curated", ...},
      {"id": 3, "key": "wallpapers.tilt_3d.title_part2",        "es": "curada.",        "en": "depth.", ...},
      {"id": 4, "key": "wallpapers.tilt_3d.subtitle",           "es": "el equipo...",   "en": "Pixora's...", ...}
    ]
  }]
}]
```

- [ ] **Step 2: Verify `/api/strings/public`**

```bash
curl -s http://127.0.0.1:5757/api/strings/public
```

Expected: flat array of 4 `{key, es, en}` objects.

- [ ] **Step 3: Verify upsert**

```bash
curl -s -X POST http://127.0.0.1:5757/api/strings/upsert \
  -H "Content-Type: application/json" \
  -d '{"key":"wallpapers.tilt_3d.subtitle","es":"PRUEBA","en":"TEST","component_id":1}'
```

Expected: `{"ok": true, "row": {...}}`. Then re-run `/api/strings/public` — `subtitle` should show `"es": "PRUEBA"`.

- [ ] **Step 4: Restore the original subtitle**

```bash
curl -s -X POST http://127.0.0.1:5757/api/strings/upsert \
  -H "Content-Type: application/json" \
  -d '{"key":"wallpapers.tilt_3d.subtitle","es":"el equipo de Pixora elige - semanal","en":"Pixora'\''s team picks - weekly","component_id":1}'
```

Verify with `curl /api/strings/public` that `subtitle.es` is back to original.

**Acceptance:** all 4 endpoints respond correctly; upsert + re-fetch shows the new value; rollback works.

---

## Task 6: Create `AppStringsService` Flutter singleton

**Files:**
- Create: `lib/core/services/app_strings_service.dart`

**Pattern reference:** `lib/core/services/ad_service.dart` lines 19-92 for the singleton + lazy init pattern.

- [ ] **Step 1: Create the service file**

Write to `lib/core/services/app_strings_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../constants/supabase_config.dart';

/// Reads CMS-controlled UI strings (edited via pixora-admin) and caches them
/// in Hive for offline use. Falls back silently — if the cache is empty or
/// the network is down, [get] returns null and callers use their hardcoded
/// fallback (see [LocaleHelper.fromCms]).
///
/// Lifecycle:
/// - [initialize] opens the Hive box, fetches fresh data if cache is empty
///   or stale (TTL 1h), and subscribes to FCM topic 'text_cms_update' so
///   admin edits invalidate the cache live.
/// - [get] is synchronous: returns the cached {es, en} for a key, or null.
/// - [refresh] forces a fresh fetch (used by FCM handler or manual reload).
class AppStringsService extends ChangeNotifier {
  AppStringsService._();
  static final AppStringsService instance = AppStringsService._();

  static const String _boxName = 'app_strings_cache';
  static const String _lastFetchKey = '__last_fetch_iso__';
  static const Duration _ttl = Duration(hours: 1);

  Box<dynamic>? _box;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
      if (_box!.isEmpty || _isStale()) {
        await refresh();
      } else {
        debugPrint('[AppStringsService] Loaded from cache (${_box!.length - 1} keys)');
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[AppStringsService] init failed: $e');
      // Non-fatal: fromCms() will fall back to hardcoded strings.
    }
  }

  bool _isStale() {
    final iso = _box?.get(_lastFetchKey) as String?;
    if (iso == null) return true;
    final last = DateTime.tryParse(iso);
    if (last == null) return true;
    return DateTime.now().difference(last) > _ttl;
  }

  /// Synchronous read for [LocaleHelper.fromCms]. Returns null if absent.
  Map<String, String>? get(String key) {
    if (_box == null) return null;
    final raw = _box!.get(key);
    if (raw is! Map) return null;
    final es = raw['es'];
    final en = raw['en'];
    if (es is! String || en is! String) return null;
    return {'es': es, 'en': en};
  }

  /// Force-refetch from Supabase. Called by FCM handler (Task 11) or manually.
  Future<void> refresh() async {
    if (_box == null) {
      debugPrint('[AppStringsService] refresh skipped: box not open');
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('${SupabaseConfig.projectUrl}/rest/v1/app_strings?select=key,es,en'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint('[AppStringsService] refresh HTTP ${res.statusCode}: ${res.body}');
        return;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      // Preserve last_fetch key while clearing strings
      await _box!.clear();
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        await _box!.put(m['key'] as String, {'es': m['es'], 'en': m['en']});
      }
      await _box!.put(_lastFetchKey, DateTime.now().toIso8601String());
      debugPrint('[AppStringsService] Refreshed ${list.length} keys from Supabase');
      notifyListeners();
    } catch (e) {
      debugPrint('[AppStringsService] refresh failed: $e');
    }
  }
}
```

- [ ] **Step 2: Verify it analyzes clean**

```bash
flutter analyze lib/core/services/app_strings_service.dart
```

Expected: `No issues found!` (or only style hints, no errors).

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/app_strings_service.dart
git commit -m "feat(text-cms): add AppStringsService singleton with Hive cache"
```

**Acceptance:** file compiles; analyzer reports 0 errors.

---

## Task 7: Extend `LocaleHelper` with `fromCms()`

**Files:**
- Modify: `lib/core/utils/locale_helper.dart`

- [ ] **Step 1: Add `fromCms()` method**

The current file has 23 lines. Add the new method to the `LocaleHelper` class, after `isSpanishContext` (line 22). The new file should be:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../services/app_strings_service.dart';

/// Tiny helper for picking ES vs EN strings without a full l10n setup.
/// Reads the device locale via `Platform.localeName` (e.g. "es_MX", "en_US").
class LocaleHelper {
  LocaleHelper._();

  static bool get isSpanish {
    final name = Platform.localeName.toLowerCase();
    return name.startsWith('es');
  }

  static String pick({required String es, required String en}) =>
      isSpanish ? es : en;

  static bool isSpanishContext(BuildContext context) {
    final l = Localizations.maybeLocaleOf(context);
    if (l != null) return l.languageCode == 'es';
    return isSpanish;
  }

  /// Reads a CMS-controlled string by [key]. If the key isn't in the CMS
  /// cache (offline, first launch, or never seeded), returns the hardcoded
  /// fallback for the current locale. Safe to use anywhere [pick] is used.
  ///
  /// Migrate gradually: replace `LocaleHelper.pick(es:, en:)` with
  /// `LocaleHelper.fromCms('key.path', fallbackEs:, fallbackEn:)` for any
  /// string that should be editable from pixora-admin.
  static String fromCms(
    String key, {
    required String fallbackEs,
    required String fallbackEn,
  }) {
    final remote = AppStringsService.instance.get(key);
    final lang = isSpanish ? 'es' : 'en';
    final fallback = isSpanish ? fallbackEs : fallbackEn;
    if (remote == null) return fallback;
    final value = remote[lang];
    if (value == null || value.isEmpty) return fallback;
    return value;
  }
}
```

- [ ] **Step 2: Verify analyzer**

```bash
flutter analyze lib/core/utils/locale_helper.dart
```

Expected: `No issues found!`.

- [ ] **Step 3: Commit**

```bash
git add lib/core/utils/locale_helper.dart
git commit -m "feat(text-cms): add LocaleHelper.fromCms() with hardcoded fallback"
```

**Acceptance:** `pick()` and `isSpanishContext()` unchanged; new `fromCms()` available.

---

## Task 8: Wire `AppStringsService.initialize()` in `main.dart`

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add the import**

At the top of `lib/main.dart`, near the other `core/services/` imports (around line 10-22), add:

```dart
import 'core/services/app_strings_service.dart';
```

Place it alphabetically — right after `import 'core/services/analytics_service.dart';`.

- [ ] **Step 2: Add the init call**

Locate line 111 in `lib/main.dart`:
```dart
    unawaited(PushNotificationService.instance.init());
    AdService.instance.initialize();
```

Insert between these two lines (so init order is: PushNotification → AppStrings → AdService):

```dart
    // Text CMS — fetch admin-editable strings from Supabase, cache in Hive.
    // Non-blocking: if it fails, LocaleHelper.fromCms() falls back to
    // hardcoded strings in each widget.
    unawaited(AppStringsService.instance.initialize());
```

The block becomes:
```dart
    unawaited(PushNotificationService.instance.init());
    // Text CMS — fetch admin-editable strings from Supabase, cache in Hive.
    // Non-blocking: if it fails, LocaleHelper.fromCms() falls back to
    // hardcoded strings in each widget.
    unawaited(AppStringsService.instance.initialize());
    AdService.instance.initialize();
```

- [ ] **Step 3: Verify analyzer**

```bash
flutter analyze lib/main.dart
```

Expected: `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat(text-cms): initialize AppStringsService on app startup"
```

**Acceptance:** main.dart compiles, no init order issues.

---

## Task 9: Migrate the 4 strings in `parallax_wallpapers_page.dart`

**Files:**
- Modify: `lib/features/parallax_wallpapers/presentation/pages/parallax_wallpapers_page.dart` (lines 78, 91, 106, 122)

- [ ] **Step 1: Add `LocaleHelper` import if missing**

At the top of the file, check if there's an import of `LocaleHelper`. If not, add (place alphabetically among other imports):

```dart
import '../../../../core/utils/locale_helper.dart';
```

- [ ] **Step 2: Migrate string 1 — badge count label (line 78)**

Find:
```dart
                  Text(
                    '${(rest.length + 1).toString().padLeft(2, '0')} piezas curadas',
                    style: TextStyle(
```

Replace with:
```dart
                  Text(
                    '${(rest.length + 1).toString().padLeft(2, '0')} ${LocaleHelper.fromCms(
                      'wallpapers.tilt_3d.badge_count_label',
                      fallbackEs: 'piezas curadas',
                      fallbackEn: 'curated pieces',
                    )}',
                    style: TextStyle(
```

- [ ] **Step 3: Migrate strings 2 & 3 — title parts (lines 91 & 106)**

Find the `Text.rich` block (lines 88-119). Replace `text: 'Profundidad\n',` with:
```dart
                      text: '${LocaleHelper.fromCms(
                        'wallpapers.tilt_3d.title_part1',
                        fallbackEs: 'Profundidad',
                        fallbackEn: 'Curated',
                      )}\n',
```

Then replace `text: 'curada.'` (inside `_HoloShimmerText`) with:
```dart
                      child: _HoloShimmerText(
                        text: LocaleHelper.fromCms(
                          'wallpapers.tilt_3d.title_part2',
                          fallbackEs: 'curada.',
                          fallbackEn: 'depth.',
                        ),
                        style: TextStyle(
```

- [ ] **Step 4: Migrate string 4 — subtitle (line 122)**

Find:
```dart
                Text(
                  'el equipo de Pixora elige · semanal',
                  style: TextStyle(
```

Replace with:
```dart
                Text(
                  LocaleHelper.fromCms(
                    'wallpapers.tilt_3d.subtitle',
                    fallbackEs: 'el equipo de Pixora elige · semanal',
                    fallbackEn: "Pixora's team picks · weekly",
                  ),
                  style: TextStyle(
```

- [ ] **Step 5: Analyzer check**

```bash
flutter analyze lib/features/parallax_wallpapers/presentation/pages/parallax_wallpapers_page.dart
```

Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/parallax_wallpapers/presentation/pages/parallax_wallpapers_page.dart
git commit -m "feat(text-cms): migrate 4 strings of 3D TILT to LocaleHelper.fromCms"
```

**Acceptance:** the 4 strings now go through `fromCms` with their hardcoded fallbacks preserving the current text.

---

## Task 10: WYSIWYG `TEXTOS` tab in `dashboard/index.html`

**Files:**
- Modify: `tools/wallpapers/dashboard/index.html`

This is the biggest single task. The dashboard is 127KB of vanilla JS — read the existing tabs structure first (search for the existing tab nav, likely `<nav class="tabs">` or similar around the top of `<body>`) before editing.

- [ ] **Step 1: Add `TEXTOS` to the tab navigation**

Find the existing tab nav (search for `RESUMEN`, `WALLPAPERS`, `INGRESOS`, `USUARIOS`, `EVENTOS`, `ENGAGEMENT`). After the `ENGAGEMENT` `<button>` (or whatever element type the existing tabs use), add:

```html
<button class="tab" data-tab="textos" onclick="showTab('textos')">
  ✏️ TEXTOS
</button>
```

(Match the exact class names and event handler convention used by the other tabs — they likely use `class="tab"` and either `onclick` or `data-*` attributes. Copy the pattern of the `ENGAGEMENT` button.)

- [ ] **Step 2: Add the panel container**

Find the existing tab panels (likely `<section id="resumen-panel">`, etc.). After the engagement panel, add:

```html
<section id="textos-panel" class="tab-panel" style="display:none;">
  <header class="textos-header">
    <h2>✏️ Editor de Textos · WYSIWYG</h2>
    <div class="textos-controls">
      <label>Sección:
        <select id="textos-section-select"></select>
      </label>
      <label>Componente:
        <select id="textos-component-select"></select>
      </label>
      <span class="textos-pending" id="textos-pending-count">0 cambios</span>
      <button id="textos-save-all" class="primary" disabled>💾 Guardar todos</button>
    </div>
  </header>
  <div id="textos-wysiwyg" class="textos-wysiwyg"></div>
</section>

<!-- Edit modal -->
<div id="textos-edit-modal" class="modal" style="display:none;">
  <div class="modal-content">
    <header><strong id="textos-modal-key">key.path</strong></header>
    <label>Español (MX)
      <textarea id="textos-modal-es" rows="3"></textarea>
    </label>
    <label>English
      <textarea id="textos-modal-en" rows="3"></textarea>
    </label>
    <footer>
      <button onclick="cerrarTextosModal()">Cancelar</button>
      <button class="primary" onclick="guardarTextosModal()">Guardar (Ctrl+Enter)</button>
    </footer>
  </div>
</div>
```

- [ ] **Step 3: Add minimal CSS**

Find the existing `<style>` block. Add at the end:

```css
/* === TEXTOS tab === */
.textos-header { padding: 12px 20px; border-bottom: 1px solid #2a2a3a; display:flex; flex-direction:column; gap:8px; }
.textos-controls { display:flex; gap:12px; align-items:center; flex-wrap:wrap; }
.textos-controls label { display:flex; gap:6px; align-items:center; font-size:13px; }
.textos-controls select { padding:6px 10px; background:#1a1a28; color:#eee; border:1px solid #444; border-radius:6px; }
.textos-pending { font-size:12px; color:#888; }
.textos-pending.has-changes { color:#F5D676; font-weight:bold; }
#textos-save-all { padding:8px 14px; background:#444; border:none; color:#888; border-radius:6px; cursor:not-allowed; }
#textos-save-all:not([disabled]) { background:linear-gradient(90deg,#E0B47A,#6EE7B7); color:#000; cursor:pointer; }
.textos-wysiwyg { padding: 24px; min-height: 60vh; background: #0a0a14; }
.textos-wysiwyg .preview-card { background: #14141F; border-radius: 12px; padding: 24px; max-width: 420px; margin: 0 auto; }
.editable-text { display:inline-block; padding:2px 4px; border:1px dashed transparent; cursor:pointer; border-radius:4px; transition:all .15s; }
.editable-text:hover { border-color:#E0B47A; background:rgba(224,180,122,0.08); }
.editable-text.modified { border-color:#6EE7B7; background:rgba(110,231,183,0.12); }
/* Modal */
.modal { position:fixed; inset:0; background:rgba(0,0,0,0.7); display:flex; align-items:center; justify-content:center; z-index:1000; }
.modal-content { background:#14141F; padding:24px; border-radius:12px; min-width:400px; max-width:600px; display:flex; flex-direction:column; gap:12px; }
.modal-content label { display:flex; flex-direction:column; gap:4px; font-size:13px; color:#aaa; }
.modal-content textarea { padding:8px; background:#0a0a14; color:#eee; border:1px solid #333; border-radius:6px; font-family:inherit; font-size:14px; resize:vertical; }
.modal-content footer { display:flex; gap:8px; justify-content:flex-end; }
.modal-content button { padding:8px 14px; border:none; border-radius:6px; cursor:pointer; }
.modal-content button.primary { background:linear-gradient(90deg,#E0B47A,#6EE7B7); color:#000; font-weight:bold; }
```

- [ ] **Step 4: Add the JavaScript module**

Find the existing `<script>` block (or where the existing tabs' JS lives). Add at the end of that block:

```javascript
// === TEXTOS tab — Text CMS editor ===
const TextosCMS = {
  tree: null,
  pendingChanges: new Map(),  // key -> {es, en, component_id}
  currentSection: null,
  currentComponent: null,
  modalKey: null,

  async load() {
    const res = await fetch('/api/strings/tree');
    if (!res.ok) {
      alert('Error cargando strings: ' + res.status);
      return;
    }
    this.tree = await res.json();
    this.renderSelectors();
  },

  renderSelectors() {
    const secSel = document.getElementById('textos-section-select');
    secSel.innerHTML = this.tree.map(s =>
      `<option value="${s.id}">${s.name} (${s.components.length})</option>`
    ).join('');
    secSel.onchange = () => this.selectSection(parseInt(secSel.value, 10));
    if (this.tree.length) this.selectSection(this.tree[0].id);
  },

  selectSection(sectionId) {
    this.currentSection = this.tree.find(s => s.id === sectionId);
    const compSel = document.getElementById('textos-component-select');
    compSel.innerHTML = this.currentSection.components.map(c =>
      `<option value="${c.id}">${c.name} (${c.strings.length})</option>`
    ).join('');
    compSel.onchange = () => this.selectComponent(parseInt(compSel.value, 10));
    if (this.currentSection.components.length) {
      this.selectComponent(this.currentSection.components[0].id);
    }
  },

  selectComponent(componentId) {
    this.currentComponent = this.currentSection.components.find(c => c.id === componentId);
    this.renderWysiwyg();
  },

  // Look up a string by key in the current component, with pending changes applied.
  stringFor(key, fallback) {
    const pending = this.pendingChanges.get(key);
    if (pending) return pending.es;
    const s = this.currentComponent.strings.find(x => x.key === key);
    return s ? s.es : fallback;
  },

  renderWysiwyg() {
    const el = document.getElementById('textos-wysiwyg');
    if (this.currentComponent.name === 'ParallaxWallpapersPage') {
      el.innerHTML = this.renderParallaxWallpapersPagePreview();
    } else {
      el.innerHTML = `<p style="color:#888;text-align:center;padding:40px;">WYSIWYG preview no implementado para "${this.currentComponent.name}" todavía. Strings sin preview visual:</p>` +
        '<ul style="max-width:600px;margin:0 auto;color:#ccc;">' +
        this.currentComponent.strings.map(s =>
          `<li><code>${s.key}</code>: <span class="editable-text${this.pendingChanges.has(s.key)?' modified':''}" onclick="TextosCMS.openModal('${s.key}')">${this.stringFor(s.key, s.es)}</span></li>`
        ).join('') + '</ul>';
    }
    this.refreshPendingBadge();
  },

  // Hardcoded WYSIWYG for the ParallaxWallpapersPage (3D · TILT).
  // Approximates real Pixora fonts + foil color. Renders the editorial header.
  renderParallaxWallpapersPagePreview() {
    const badge = this.stringFor('wallpapers.tilt_3d.badge_count_label', 'piezas curadas');
    const t1 = this.stringFor('wallpapers.tilt_3d.title_part1', 'Profundidad');
    const t2 = this.stringFor('wallpapers.tilt_3d.title_part2', 'curada.');
    const sub = this.stringFor('wallpapers.tilt_3d.subtitle', 'el equipo de Pixora elige · semanal');
    const cls = k => 'editable-text' + (this.pendingChanges.has(k) ? ' modified' : '');
    return `
      <div class="preview-card" style="font-family: 'Inter', sans-serif; color:#eee;">
        <div style="display:flex; gap:8px; align-items:center; margin-bottom:12px;">
          <span style="padding:3px 10px; border:1px solid #E0B47A; border-radius:14px; font-size:10px; letter-spacing:1.6px; color:#E0B47A;">3D · TILT</span>
          <span class="${cls('wallpapers.tilt_3d.badge_count_label')}"
            onclick="TextosCMS.openModal('wallpapers.tilt_3d.badge_count_label')"
            style="font-family:'JetBrains Mono',monospace; font-size:10px; letter-spacing:1.6px; color:#888;">06 ${badge}</span>
        </div>
        <div style="font-family:'Fraunces',serif; font-style:italic; font-weight:300; font-size:42px; line-height:0.96; letter-spacing:-1.2px; color:#fff;">
          <span class="${cls('wallpapers.tilt_3d.title_part1')}"
            onclick="TextosCMS.openModal('wallpapers.tilt_3d.title_part1')">${t1}</span><br/>
          <span class="${cls('wallpapers.tilt_3d.title_part2')}"
            onclick="TextosCMS.openModal('wallpapers.tilt_3d.title_part2')"
            style="background:linear-gradient(90deg,#E0B47A,#F4D6B8,#FFFFFF,#6EE7B7); -webkit-background-clip:text; background-clip:text; color:transparent;">${t2}</span>
        </div>
        <div style="margin-top:8px;">
          <span class="${cls('wallpapers.tilt_3d.subtitle')}"
            onclick="TextosCMS.openModal('wallpapers.tilt_3d.subtitle')"
            style="font-family:'JetBrains Mono',monospace; font-size:10px; letter-spacing:1.4px; color:#888;">${sub}</span>
        </div>
      </div>
    `;
  },

  openModal(key) {
    const s = this.currentComponent.strings.find(x => x.key === key);
    if (!s) return;
    const pending = this.pendingChanges.get(key);
    this.modalKey = key;
    document.getElementById('textos-modal-key').textContent = key;
    document.getElementById('textos-modal-es').value = pending ? pending.es : s.es;
    document.getElementById('textos-modal-en').value = pending ? pending.en : s.en;
    document.getElementById('textos-edit-modal').style.display = 'flex';
    document.getElementById('textos-modal-es').focus();
  },

  closeModal() {
    document.getElementById('textos-edit-modal').style.display = 'none';
    this.modalKey = null;
  },

  saveModal() {
    if (!this.modalKey) return;
    const es = document.getElementById('textos-modal-es').value;
    const en = document.getElementById('textos-modal-en').value;
    const s = this.currentComponent.strings.find(x => x.key === this.modalKey);
    if (s.es === es && s.en === en) {
      this.pendingChanges.delete(this.modalKey);
    } else {
      this.pendingChanges.set(this.modalKey, { es, en, component_id: this.currentComponent.id });
    }
    this.closeModal();
    this.renderWysiwyg();
  },

  refreshPendingBadge() {
    const span = document.getElementById('textos-pending-count');
    const btn = document.getElementById('textos-save-all');
    const n = this.pendingChanges.size;
    span.textContent = n === 1 ? '1 cambio' : `${n} cambios`;
    span.classList.toggle('has-changes', n > 0);
    if (n > 0) btn.removeAttribute('disabled'); else btn.setAttribute('disabled', '');
  },

  async saveAll() {
    if (this.pendingChanges.size === 0) return;
    const body = Array.from(this.pendingChanges.entries()).map(([key, val]) => ({
      key, es: val.es, en: val.en, component_id: val.component_id,
    }));
    const btn = document.getElementById('textos-save-all');
    btn.textContent = 'Guardando…';
    btn.setAttribute('disabled', '');
    try {
      const res = await fetch('/api/strings/bulk-upsert', {
        method: 'POST',
        headers: {'Content-Type':'application/json'},
        body: JSON.stringify(body),
      });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      this.pendingChanges.clear();
      await this.load();  // re-fetch tree
      btn.textContent = '✅ Guardado';
      setTimeout(() => { btn.textContent = '💾 Guardar todos'; }, 1500);
    } catch (e) {
      btn.textContent = '❌ Error';
      alert('Error guardando: ' + e.message);
      setTimeout(() => { btn.textContent = '💾 Guardar todos'; btn.removeAttribute('disabled'); }, 2000);
    }
  },
};

// Global handlers wired to onclick attributes
function cerrarTextosModal() { TextosCMS.closeModal(); }
function guardarTextosModal() { TextosCMS.saveModal(); }

// Wire bulk-save button
document.addEventListener('DOMContentLoaded', () => {
  const btn = document.getElementById('textos-save-all');
  if (btn) btn.onclick = () => TextosCMS.saveAll();
  // Ctrl+Enter in modal saves
  document.addEventListener('keydown', (e) => {
    const modal = document.getElementById('textos-edit-modal');
    if (modal && modal.style.display === 'flex' && e.ctrlKey && e.key === 'Enter') {
      TextosCMS.saveModal();
    }
    if (modal && modal.style.display === 'flex' && e.key === 'Escape') {
      TextosCMS.closeModal();
    }
  });
});
```

- [ ] **Step 5: Wire `showTab` to load TEXTOS data lazily**

Find the existing `showTab` function (or whatever switches tabs). Add at the bottom of its body:

```javascript
if (tabName === 'textos' && !TextosCMS.tree) {
  TextosCMS.load();
}
```

(Match the parameter name your existing `showTab` uses — it might be called `name`, `tabId`, etc.)

- [ ] **Step 6: 🧑‍💻 Manual test in browser**

Eduardo manually:
1. Refresh `http://127.0.0.1:5757` in your browser (Ctrl+F5 to bypass cache).
2. Click the new `✏️ TEXTOS` tab.
3. Verify: section dropdown shows `WALLPAPERS (1)`, component shows `ParallaxWallpapersPage (4)`.
4. Verify: the WYSIWYG card renders with `Profundidad` + `curada.` (foil gradient) + the badge + subtitle.
5. Click on "Profundidad" → modal opens with `ES: Profundidad`, `EN: Curated`.
6. Change ES to `Hondura` and click Guardar (or Ctrl+Enter).
7. Verify: the card now shows `Hondura` with a green-mint border (modified indicator). Pending counter shows `1 cambio`.
8. Click `💾 Guardar todos` → button shows `✅ Guardado`. Pending counter resets to 0.
9. Re-curl `/api/strings/public` from terminal to confirm `title_part1` is now `Hondura`.
10. Restore the original via the same flow: click `Hondura` → set ES back to `Profundidad` → save all.

- [ ] **Step 7: Commit frontend**

```bash
git add tools/wallpapers/dashboard/index.html
git commit -m "feat(text-cms): add TEXTOS tab with WYSIWYG editor for 3D TILT"
```

**Acceptance:** the tab loads, the WYSIWYG renders the 4 strings using Pixora-like fonts/foil, edits trigger pending state, bulk-save POSTs to backend.

---

## Task 11 (OPTIONAL): FCM push on bulk-save

Skip this task for the initial smoke test. The Flutter app picks up changes on next cold-start (TTL 1h or first launch). Add this later when you want live updates without manual restart.

**Files:**
- Create: `tools/wallpapers/_fcm_push.py` (helper using FCM HTTP v1 API + service account)
- Modify: `tools/wallpapers/wp_admin_server.py` (call `_fcm_push` after `_handle_strings_upsert` and `_handle_strings_bulk_upsert`)
- Modify: `lib/core/services/push_notification_service.dart` to subscribe to `text_cms_update` topic
- Modify: `lib/core/services/app_strings_service.dart` to expose `refresh()` to be called from FCM handler

**Pre-requisite:** Firebase service account JSON saved at `G:/Mi unidad/pixoraIA_admin/admin/cloudconsole/pixora-firebase-admin.json` (or similar path). If Eduardo doesn't have this yet, he needs to generate it from Firebase Console → Project Settings → Service Accounts → "Generate new private key".

Detailed steps for this task will be written in a follow-up plan (`2026-05-XX-text-cms-fcm-push.md`) when Eduardo decides to enable live updates.

---

## Task 12: End-to-end smoke test on device

**Files:** none modified (verification only)

- [ ] **Step 1: Build debug APK**

```bash
flutter build apk --debug
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (~120 MB).

If build fails on `app_strings_service.dart`, check that `http` package is declared in `pubspec.yaml`. It already is (used by other services), but if not, add and re-run `flutter pub get`.

- [ ] **Step 2: Install on Samsung**

```bash
adb -s RF8X903KZ3K install -r build/app/outputs/flutter-apk/app-debug.apk
```

If `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (release signature conflict), recover:
```bash
adb -s RF8X903KZ3K uninstall com.orbix.pixora
adb -s RF8X903KZ3K install build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 3: Clear logcat, launch, monitor**

```bash
adb -s RF8X903KZ3K logcat -c
adb -s RF8X903KZ3K shell am start -n com.orbix.pixora/.MainActivity
```

Wait 6 seconds for cold-start. Then:
```bash
adb -s RF8X903KZ3K logcat -d | grep -E "AppStringsService|FATAL|flutter|Pixora" | head -40
```

Expected log lines:
```
[AppStringsService] Refreshed 4 keys from Supabase
```

Or (if cache was already populated from a previous run):
```
[AppStringsService] Loaded from cache (4 keys)
```

🧑‍💻 **Eduardo manually verifies on device:**
1. Open the app, navigate to the bottom-nav tab that opens the 3D · TILT section (`parallax_wallpapers`).
2. Confirm the screen shows "Profundidad / curada." + "06 piezas curadas" + "el equipo de Pixora elige · semanal" — exactly as before (because the seed data matches the hardcoded strings). This proves the CMS is reading from Supabase, not falling back.

- [ ] **Step 4: Live-edit smoke test**

🧑‍💻 **Eduardo manually:**
1. Go to `http://127.0.0.1:5757` → TEXTOS tab.
2. Click on the title "Profundidad" → change ES to `Honduras del 3D`.
3. Click Guardar then Guardar todos.
4. On the Samsung, force-stop the app:
   ```bash
   adb -s RF8X903KZ3K shell am force-stop com.orbix.pixora
   ```
5. Re-open Pixora on the device. Navigate to 3D · TILT.
6. **Expected:** the title now reads "Honduras del 3D / curada." instead of "Profundidad / curada.".
7. ✅ **Smoke test passed** if you see the new text without a rebuild/install.

- [ ] **Step 5: Restore original text**

🧑‍💻 **Eduardo manually:**
1. In pixora-admin TEXTOS tab, click "Honduras del 3D" → change back to `Profundidad`.
2. Guardar todos.
3. (Optional) force-stop + relaunch app to verify rollback.

- [ ] **Step 6: Cleanup verification scripts (none should remain)**

```bash
ls tools/_*.py 2>/dev/null
```

Should output nothing — the inspection script from Task 2 was already removed. The `tools/wallpapers/_seed_text_cms.py` stays (committed in Task 3).

- [ ] **Step 7: Update master doc**

Run the `pixora-master-doc-append` skill (or manually use `python-docx`) to append a §7.Z sub-section documenting that Phase 1 of the Text CMS is live, with: 4 strings migrated, 3 tables in Supabase, tab `TEXTOS` available in pixora-admin, FCM push deferred to Phase 1.5.

- [ ] **Step 8: Push everything**

```bash
git log --oneline -10  # review the new commits
git push origin play-store-estable
```

🧑‍💻 **Eduardo confirms push.**

**Acceptance:** end-to-end flow works — admin edits text, app picks it up after restart, no rebuild required.

---

## Out of scope (do NOT implement in this plan)

- FCM push on bulk-save → Task 11 above (deferred)
- Mapping the remaining ~13 Flutter features (AI Create, 3D · TILT detail, Cultura, etc.) → Phase 2 (separate session)
- Curating which strings are editable across all components → Phase 3
- Mass-migrating the ~500 strings → Phase 4
- History/audit log of edits → v2
- Markdown/HTML in strings → v2
- Placeholder substitution (e.g. `'{name}, bienvenido'`) → v2
- Auth on pixora-admin → never (local-only)

---

## Self-review checklist (filled by the author of this plan)

- ✅ **Spec coverage:** All spec sections (schema, cache, naming, smoke test, UX) map to a task. FCM push from spec is captured as optional Task 11 with reason for deferral.
- ✅ **Placeholder scan:** No TBD/TODO/fill-in-later. Each step has exact code or exact command.
- ✅ **Type consistency:** Key names (`wallpapers.tilt_3d.*`), method names (`fromCms`, `initialize`, `refresh`, `get`), table names (`app_sections`, `app_components`, `app_strings`) all consistent across tasks.
- ✅ **No TDD-flavored tests:** Pixora has no test suite, plan uses analyzer + manual device verification per CLAUDE.md.
- ✅ **Manual steps flagged:** 🧑‍💻 markers on every step where Eduardo must act (server restart, browser refresh, device testing).
- ✅ **Existing patterns referenced:** `AdService` for singleton, `_interstitialAdUnitId` style for constants, `apply_migration.py` for DB changes, existing tab structure in dashboard.

**Plan complete.**
