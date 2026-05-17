# Pixora Admin Text CMS — Design Spec

**Date:** 2026-05-17
**Status:** Approved (pending user review)
**Author:** Eduardo + Claude (brainstorm session 2026-05-17)
**Implementation plan:** TBD (will be generated next via `writing-plans` skill)

---

## Goal

Allow Eduardo to edit the visible copy (button labels, headers, modal text, hero banner strings) of the Pixora Flutter app from the local pixora-admin dashboard (`http://127.0.0.1:5757`) without recompiling the APK or shipping a new Play Store release.

## Problem

Pixora's UI strings are hardcoded in Dart widgets. Many were shipped under time pressure without a copywriter, resulting in copy that "sounds like a developer wrote it" (e.g. `Profundidad curada`, `el equipo de Pixora elige · semanal`, `06 piezas curadas` in the 3D · TILT section). Every cosmetic copy change today requires: edit Dart → flutter build → AAB → Play Store review (3-7 days). This is too much friction for what should be quick wording tweaks.

## Non-goals (v1)

- ❌ Editing strings inside the Flutter app itself (admin UI lives outside the APK — see memory `feedback_no_admin_ui_in_app`)
- ❌ History / audit log of changes (deferred to v2)
- ❌ Authentication on pixora-admin (stays local, 127.0.0.1 only, no login)
- ❌ Markdown / HTML rendering in strings (plain text only)
- ❌ Strings with dynamic placeholders (`'{name}, bienvenido'`) — deferred to v2
- ❌ Per-app-version string overrides (no `min_version` / `deprecated_in_version` columns)
- ❌ Migrating all ~500 strings at once (v1 = smoke test with 3 strings)
- ❌ Replacing `LocaleHelper.pick()` (coexists, no breaking change)

## Stack

| Layer | Tech | Location |
|---|---|---|
| Backend | Python HTTP (extend existing) | `tools/wallpapers/wp_admin_server.py` |
| Frontend | Vanilla JavaScript (consistent with existing dashboard) | `tools/wallpapers/dashboard/index.html` |
| Database | Supabase Postgres (3 new tables) | New migration `supabase/migrations/` |
| Push | Firebase Cloud Messaging (new topic) | Existing FCM infra (memory `tech_fcm_topic_broadcast`) |
| Flutter helper | Extend existing `LocaleHelper` | `lib/core/utils/locale_helper.dart` |
| Client cache | Hive box | `lib/core/services/app_strings_service.dart` (new singleton) |

---

## Locked decisions

### D1 — Schema: Multi-tabla normalizada

Three tables with foreign keys: `app_sections` → `app_components` → `app_strings`.

**Rationale (user choice):** structured, supports future reporting (count strings per component, per section), `file_path` column on `app_components` is useful for traceability, `order_index` on `app_sections` allows custom UI ordering.

### D2 — Cache strategy: Hive TTL 1h + FCM push instant invalidation

- Client caches all strings in a Hive box (`app_strings_cache`).
- TTL of 1 hour as the fallback heartbeat — even if FCM fails, cache refreshes hourly when the app is used.
- Admin save triggers FCM push to topic `text_cms_update` → client invalidates cache → re-fetches.
- Latency for users with app open: ~5–30 seconds.
- Latency for users with app closed: applies at next cold-start (or sooner if TTL expired during background).

**Rationale:** FCM is already wired (memory `tech_fcm_topic_broadcast` confirms topic `new_content` works end-to-end). Adding another topic is trivial. TTL alone would be too slow for typo fixes; ETag polling adds complexity without solving the "user mid-session" case.

### D3 — Naming convention: Dot-notation (`section.component.string_name`)

Examples:
- `arcano.onboarding.welcome_title`
- `wallpapers.preview_3d.title`
- `home.banner.featured_label`
- `settings.account.delete_confirm_title`

**Rationale:** industry standard for i18n (i18next, Rails I18n, Android `strings.xml` namespacing convention). Human-readable, hierarchical, filterable. Eduardo confirmed preference.

### D4 — Smoke test scope: 3 strings of `WallpaperPreviewPage` (3D · TILT)

First end-to-end test migrates only:
- `wallpapers.preview_3d.title` → `Profundidad curada` / `Curated depth`
- `wallpapers.preview_3d.subtitle` → `el equipo de Pixora elige · semanal` / ...
- `wallpapers.preview_3d.badge_count` → `06 piezas curadas` / ...

Once these flow end-to-end (admin edit → FCM push → Flutter updates), proceed with mass migration in subsequent sessions (Phase 2+).

**Rationale:** YAGNI — if the pipeline works for 3 strings, it works for 500. Reduces risk of discovering infra bugs after migrating hundreds.

### D5 — Admin UX: WYSIWYG-style "estilo Pixora" with click-to-edit

- New tab `TEXTOS` in pixora-admin.
- Sidebar selectors: Section dropdown → Component dropdown.
- Main panel: renders the selected component **pixel-close to how it looks in the real app** (using the same Google Fonts — Fraunces, Cinzel, JetBrains Mono, Inter — and approximate foil gradients).
- Each editable text shows a subtle hover border. Click opens a modal editor with ES + EN textareas side-by-side, save/cancel buttons, and live preview.
- "Pending changes" counter at top. Bulk save button triggers FCM push.

**Rationale:** Eduardo explicitly chose the most visual / interactive option. JavaScript vanilla (no React/Vue) keeps it consistent with the rest of the dashboard.

---

## Architecture

### Database schema (Supabase)

```sql
-- Migration: supabase/migrations/20260518_001_text_cms.sql

CREATE TABLE app_sections (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,        -- 'ARCANO', 'WALLPAPERS', 'HOME', ...
  order_index INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE app_components (
  id           SERIAL PRIMARY KEY,
  section_id   INT NOT NULL REFERENCES app_sections(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,              -- 'WallpaperPreviewPage', 'OnboardingSheet', ...
  file_path    TEXT,                       -- 'lib/features/wallpapers/.../wallpaper_preview_page.dart'
  description  TEXT,                       -- 'Detalle Trading Card Holo'
  created_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE(section_id, name)
);

CREATE TABLE app_strings (
  id            SERIAL PRIMARY KEY,
  component_id  INT NOT NULL REFERENCES app_components(id) ON DELETE CASCADE,
  key           TEXT NOT NULL UNIQUE,      -- 'wallpapers.preview_3d.title'
  es            TEXT NOT NULL,             -- 'Profundidad curada'
  en            TEXT NOT NULL,             -- 'Curated depth'
  updated_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_app_strings_component_id ON app_strings(component_id);
CREATE INDEX idx_app_strings_key ON app_strings(key);

-- RLS
ALTER TABLE app_sections   ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_strings    ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon can read sections"   ON app_sections   FOR SELECT TO anon USING (true);
CREATE POLICY "anon can read components" ON app_components FOR SELECT TO anon USING (true);
CREATE POLICY "anon can read strings"    ON app_strings    FOR SELECT TO anon USING (true);
-- No INSERT/UPDATE/DELETE policies → only service_role passes.

-- Trigger to bump updated_at on UPDATE
CREATE OR REPLACE FUNCTION bump_app_strings_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_app_strings_updated_at
BEFORE UPDATE ON app_strings
FOR EACH ROW EXECUTE FUNCTION bump_app_strings_updated_at();
```

### Backend endpoints (extend `wp_admin_server.py`)

| Method | Endpoint | Body | Returns | Purpose |
|---|---|---|---|---|
| `GET` | `/api/strings/tree` | — | `[{section, components: [{name, file_path, strings: [{key, es, en, updated_at}]}]}]` | Full tree for admin sidebar + main panel |
| `POST` | `/api/strings/upsert` | `{key, es, en, component_id}` | `{ok: true, updated_at}` | Single string upsert + FCM trigger |
| `POST` | `/api/strings/bulk-upsert` | `[{key, es, en, component_id}, ...]` | `{ok: true, count, updated_at}` | Bulk save (multi-edit) + single FCM trigger |
| `POST` | `/api/strings/seed` | `[{section, component, file_path, key, es, en}, ...]` | `{ok: true, sections_created, components_created, strings_created}` | One-shot bulk seed for migrations |
| `GET` | `/api/strings/public` | — | `[{key, es, en}, ...]` | Flat list for Flutter client (no admin metadata) |

FCM push payload (sent after any upsert/bulk-upsert):
```json
{
  "topic": "text_cms_update",
  "data": { "type": "text_cms_invalidate", "ts": "2026-05-17T22:30:00Z" }
}
```
Data-only message (no notification UI). Flutter handles in background isolate.

### Frontend: tab `TEXTOS` UX

Layout:
```
┌──────────────────────────────────────────────────────────────────────┐
│  RESUMEN  WALLPAPERS  INGRESOS  USUARIOS  EVENTOS  ENGAGEMENT  TEXTOS│
├──────────────────────────────────────────────────────────────────────┤
│  Sección: [ ARCANO ▾ ]  Componente: [ OnboardingSheet ▾ ]            │
│  Cambios pendientes: 0    [💾 Guardar todos]   [📡 FCM topic ready]   │
├──────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ [Render pixel-close del componente seleccionado]               │  │
│  │                                                                 │  │
│  │   PIXORA · ONBOARDING                                          │  │
│  │   ┌─Bienvenido.───────────────────────────┐ ✏️ ← hover border  │  │
│  │   └────────────────────────────────────────┘                   │  │
│  │   ┌─Dos datos para abrir tu mundo...─────┐ ✏️                  │  │
│  │   └────────────────────────────────────────┘                   │  │
│  │   NOMBRE                                                       │  │
│  │   _____________________________________                        │  │
│  │   ┌─Completa los datos────────────────────┐ ✏️                 │  │
│  │   └────────────────────────────────────────┘                   │  │
│  │                                                                 │  │
│  │  (renders with real Pixora fonts — Fraunces italic for title,  │  │
│  │   Inter for body, foil gradient color on key elements)         │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

Click on any editable text → modal:
```
┌─────────────────────────────────────────┐
│  Editar:  arcano.onboarding.welcome_title
│  ──────────────────────────────────────  │
│  ES (Español MX)                         │
│  ┌────────────────────────────────────┐ │
│  │ Bienvenido.                        │ │
│  └────────────────────────────────────┘ │
│  EN (English)                            │
│  ┌────────────────────────────────────┐ │
│  │ Welcome.                           │ │
│  └────────────────────────────────────┘ │
│  Vista previa: Bienvenido.               │
│  [ Cancelar ]  [ Guardar (Ctrl+Enter) ] │
└─────────────────────────────────────────┘
```

Save updates local UI state with a "modified" indicator (foil color border). Bulk save flushes all pending changes via `POST /api/strings/bulk-upsert`.

### Flutter integration

**`lib/core/utils/locale_helper.dart`** — extend with new method:

```dart
class LocaleHelper {
  // EXISTING - unchanged
  static bool get isSpanish => /* … */;
  static String pick({required String es, required String en}) => isSpanish ? es : en;

  // NEW - reads CMS, falls back to hardcoded
  static String fromCms(
    String key, {
    required String fallbackEs,
    required String fallbackEn,
  }) {
    final remote = AppStringsService.instance.get(key);
    final lang = isSpanish ? 'es' : 'en';
    if (remote != null && remote[lang] != null && remote[lang]!.isNotEmpty) {
      return remote[lang]!;
    }
    return isSpanish ? fallbackEs : fallbackEn;
  }
}
```

**`lib/core/services/app_strings_service.dart`** — new singleton:

```dart
class AppStringsService extends ChangeNotifier {
  AppStringsService._();
  static final instance = AppStringsService._();

  Box<Map<String, dynamic>>? _box;
  DateTime? _lastFetch;
  static const Duration _ttl = Duration(hours: 1);

  Future<void> initialize() async {
    _box = await Hive.openBox<Map<String, dynamic>>('app_strings_cache');
    if (_box!.isEmpty || _isStale()) {
      await _fetchAndCache();
    }
    _subscribeFcm();
  }

  Map<String, String>? get(String key) {
    final raw = _box?.get(key);
    if (raw == null) return null;
    return {'es': raw['es'] as String? ?? '', 'en': raw['en'] as String? ?? ''};
  }

  bool _isStale() {
    if (_lastFetch == null) return true;
    return DateTime.now().difference(_lastFetch!) > _ttl;
  }

  Future<void> _fetchAndCache() async {
    final res = await http.get(Uri.parse('${SupabaseConfig.url}/rest/v1/app_strings?select=key,es,en'),
        headers: {'apikey': SupabaseConfig.anonKey});
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List;
      await _box!.clear();
      for (final item in list) {
        await _box!.put(item['key'] as String, {
          'es': item['es'],
          'en': item['en'],
        });
      }
      _lastFetch = DateTime.now();
      notifyListeners();
    }
  }

  void _subscribeFcm() {
    FirebaseMessaging.instance.subscribeToTopic('text_cms_update');
    FirebaseMessaging.onMessage.listen((msg) {
      if (msg.data['type'] == 'text_cms_invalidate') {
        _fetchAndCache();
      }
    });
  }
}
```

Wired in `main.dart` after `FCMService.instance.initialize()`.

---

## Migration usage (after v1 ships)

To migrate a hardcoded string to CMS-controlled:

**Before:**
```dart
Text(
  LocaleHelper.pick(es: 'Profundidad curada', en: 'Curated depth'),
  style: TextStyle(fontFamily: 'Fraunces', fontStyle: FontStyle.italic),
)
```

**After:**
```dart
Text(
  LocaleHelper.fromCms(
    'wallpapers.preview_3d.title',
    fallbackEs: 'Profundidad curada',
    fallbackEn: 'Curated depth',
  ),
  style: TextStyle(fontFamily: 'Fraunces', fontStyle: FontStyle.italic),
)
```

Plus one-time seed via `POST /api/strings/seed`. Done.

---

## End-to-end flow (smoke test acceptance)

```
1. Eduardo opens pixora-admin → TEXTOS tab
2. Selects: section=WALLPAPERS, component=WallpaperPreviewPage
3. WYSIWYG render shows the 3 strings: title, subtitle, badge
4. Clicks "Profundidad curada" → modal
5. Edits ES to "Lo más fino del 3D"
6. Clicks Guardar → modal closes, string shows foil border (pending)
7. Clicks "Guardar todos" → POST /api/strings/bulk-upsert → server upserts + FCM push
8. Eduardo's Samsung RF8X903KZ3K (Pixora open in 3D · TILT section):
   a. FirebaseMessaging.onMessage fires
   b. AppStringsService._fetchAndCache() runs
   c. notifyListeners() triggers widget rebuild
   d. Text updates from "Profundidad curada" to "Lo más fino del 3D"
9. ✅ Smoke test passed: edit → push → live update without APK rebuild
```

Acceptance criteria:
- [ ] Migration applied: 3 tables exist with correct RLS
- [ ] 3 seed strings inserted with correct keys
- [ ] WYSIWYG renders the 3 strings with approximate Pixora styling
- [ ] Click on any string opens edit modal
- [ ] Save in modal marks string as pending (visual indicator)
- [ ] Bulk save POSTs to `/api/strings/bulk-upsert`
- [ ] Server upserts to Postgres
- [ ] Server sends FCM to topic `text_cms_update`
- [ ] Flutter app (on device) receives FCM in <30s
- [ ] Cache invalidates, re-fetches, UI updates
- [ ] No app restart required

---

## Risks & dependencies

| Risk | Mitigation |
|---|---|
| FCM payload size limit (4KB) | Data-only message with timestamp; clients fetch via REST (not pushed in payload) |
| Hive box corruption on bad write | Fallback to hardcoded strings always works; cache is non-critical |
| Network failure during fetch | Use stale cache; retry on next FCM or TTL tick |
| `anon` key leaked via app | Already public; RLS prevents writes; service_role stays on server |
| Admin user (Eduardo) typos a string | v1 has no audit log; v2 will add. Workaround: edit again to revert |
| Performance: re-render entire app on FCM | `notifyListeners()` will rebuild widgets that use `AppStringsService` via `ListenableBuilder`. Widgets that read once on build won't update until next rebuild. For v1, accept this — most copy is in pages that rebuild often |
| FCM topic subscribe race on first app open | Subscribe in `initialize()` is awaited; if it fails, retry on next app start |

Dependencies:
- ✅ FCM already configured (memory `tech_fcm_topic_broadcast`)
- ✅ Supabase Postgres IPv4 add-on enabled (CLAUDE.md confirms)
- ✅ Hive already used in app (`CreditService`, etc.)
- ✅ `wp_admin_server.py` pattern established
- ✅ Component map v1.7.17 exists for reference

---

## Phase plan (v1 only — Phase 1)

This spec covers Phase 1 (smoke test). Subsequent phases out of scope:

**Phase 1 (this spec):** Infra + 3 strings working end-to-end.
**Phase 2 (future):** Complete component map for remaining ~13 features.
**Phase 3 (future):** Eduardo curates which strings are editable.
**Phase 4 (future):** Bulk migrate all editable strings (~500) via `POST /api/strings/seed` + Dart edits.
**Phase 5 (future):** v2 enhancements (history/audit, placeholders, WYSIWYG enhancements).

---

## Files to create / modify

**Create:**
- `supabase/migrations/20260518_001_text_cms.sql` (3 tables + RLS + trigger)
- `lib/core/services/app_strings_service.dart` (new singleton)
- `tools/wallpapers/_seed_text_cms.py` (one-shot script for 3 smoke-test strings)

**Modify:**
- `tools/wallpapers/wp_admin_server.py` (add 5 endpoints)
- `tools/wallpapers/dashboard/index.html` (add TEXTOS tab + WYSIWYG render + edit modal)
- `lib/core/utils/locale_helper.dart` (add `fromCms()` method)
- `lib/main.dart` (initialize `AppStringsService` after FCM)
- `lib/features/wallpapers/presentation/pages/wallpaper_preview_page.dart` (3 strings → `fromCms()`)
