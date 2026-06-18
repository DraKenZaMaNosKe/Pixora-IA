"""
Pixora Admin Dashboard — local web server with live data.

Runs locally on YOUR PC (never goes to the cloud, never inside Pixora app).
Serves a beautiful HTML+JS dashboard that fetches live data from Supabase
through this proxy (which adds the service_role key from KEYS_LOCAL.md).

Usage:
    python tools/wallpapers/wp_admin_server.py
    # opens http://localhost:8765 in your browser

Press Ctrl+C to stop.
"""
from __future__ import annotations
import json, os, re, sys, urllib.request, urllib.parse, urllib.error, webbrowser
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from threading import Timer


def datetime_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

if sys.platform == "win32":
    # Under pythonw.exe stdout/stderr can be None; HTTPServer's log_message
    # writes to stderr and would crash the request handler the first time it
    # logs. Redirect to a real log file next to this script so diagnostics
    # survive even when launched silently from the desktop shortcut.
    _LOG_FILE = Path(__file__).parent / "admin_server.log"
    if sys.stdout is None or sys.stderr is None:
        try:
            _log_handle = open(_LOG_FILE, "a", encoding="utf-8", buffering=1)
            if sys.stdout is None:
                sys.stdout = _log_handle
            if sys.stderr is None:
                sys.stderr = _log_handle
        except Exception:
            # Fallback: discard if the log file is not writable for any reason.
            if sys.stdout is None:
                sys.stdout = open(os.devnull, "w", encoding="utf-8")
            if sys.stderr is None:
                sys.stderr = open(os.devnull, "w", encoding="utf-8")
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

PORT = 5757  # uncommon high port to avoid Windows reservations / Pixora design tools
KEYS_PATH = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
DASHBOARD_HTML = Path(__file__).parent / "dashboard" / "index.html"
PROJECT_REF = "vzuwvsmlyigjtsearxym"
SUPABASE_REST = f"https://{PROJECT_REF}.supabase.co/rest/v1"
SUPABASE_STORAGE = f"https://{PROJECT_REF}.supabase.co/storage/v1"

# Catalog files in Supabase Storage. Each entry maps a kind to its
# (bucket, file, items_key) — items_key is the top-level array name inside
# the JSON ("wallpapers", "stories", "ringtones", "scenes", ...).
# The dashboard CRUD edits these JSONs in place via the server (server
# holds SERVICE_KEY, browser never sees it).
CATALOGS = {
    "live":      ("wallpaper-videos", "live_wallpaper_catalog.json", "wallpapers"),
    "static":    ("wallpaper-images", "dynamic_catalog.json",        "wallpapers"),
    "stories":   ("wallpaper-images", "stories_catalog.json",        "stories"),
    # Real schemas verified 2026-06-16: day_cycle JSON uses 'themes' (each
    # theme = one daycycle the app tracks as 'daycycle_<id>'); ringtones
    # JSON uses 'packs' (each pack = one tone_pack_<id> tracked entity).
    # Previous keys ('scenes'/'ringtones') silently returned 0 items so
    # these sections were invisible in the dashboard grid.
    "day_cycle": ("wallpaper-images", "day_cycle_catalog.json",      "themes"),
    "ringtones": ("wallpaper-images", "ringtones_catalog.json",      "packs"),
}

# Text CMS — Phase 1 endpoints (2026-05-18)
# Reads/writes go through this server (which holds service_role).
# Plan: docs/superpowers/plans/2026-05-17-text-cms-phase1.md
TEXT_CMS_FCM_TOPIC = 'text_cms_update'  # used by _fcm_push.send_text_cms_update()

# FCM push helper (sibling module). Soft import — server still runs if the
# helper is broken or the service account JSON is missing. send_text_cms_update()
# returns False in those cases and we silently degrade to TTL-based refresh.
try:
    from _fcm_push import send_text_cms_update as _fcm_push_text_cms_update
    from _fcm_push import send_catalog_invalidate as _fcm_push_catalog_invalidate
    from _fcm_push import VALID_CATALOG_SCOPES as _FCM_VALID_SCOPES
except Exception as _fcm_err:
    print(f"[wp_admin_server] FCM push helper unavailable: {_fcm_err}")
    def _fcm_push_text_cms_update():
        return False
    def _fcm_push_catalog_invalidate(scope: str):
        return False
    _FCM_VALID_SCOPES = set()


# ─── Get service key once at startup ──────────────────────────────────────────
def get_service_key() -> str:
    content = KEYS_PATH.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", content)
    if not m:
        raise SystemExit("Service Role Key not found in KEYS_LOCAL.md")
    return m.group(1)


SERVICE_KEY = get_service_key()


def _supabase_rest(method: str, table_path: str, body=None, query: str = "") -> tuple:
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


# ─── HTTP handler ─────────────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # quieter logs
        if "/api/" in args[0] if args else False:
            return
        sys.stderr.write(f"  {self.address_string()} - {fmt % args}\n")

    def _send(self, status: int, ctype: str, body: bytes, extra_headers: dict | None = None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        # Default no-store; let callers override (e.g. sprite frames get cached
        # to avoid re-fetching the ZIP from Storage every editor render).
        if extra_headers and "Cache-Control" in extra_headers:
            self.send_header("Cache-Control", extra_headers["Cache-Control"])
        else:
            self.send_header("Cache-Control", "no-store")
        if extra_headers:
            for k, v in extra_headers.items():
                if k == "Cache-Control":
                    continue
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, obj, status: int = 200):
        body = json.dumps(obj).encode("utf-8")
        self._send(status, "application/json; charset=utf-8", body)

    def _read_json_body(self):
        length = int(self.headers.get('Content-Length', 0))
        if length == 0:
            return None
        raw = self.rfile.read(length).decode('utf-8')
        return json.loads(raw) if raw else None

    # ─── Text CMS handlers ────────────────────────────────────────
    def _handle_strings_tree(self):
        """GET /api/strings/tree — returns nested [{section, components: [...]}, ...] for admin UI."""
        # 1. sections
        s_status, sections = _supabase_rest("GET", "app_sections", query="select=id,name,order_index&order=order_index.asc,name.asc")
        if s_status != 200:
            return self._send_json(sections, s_status)
        # 2. components
        c_status, components = _supabase_rest("GET", "app_components", query="select=id,section_id,name,file_path,description&order=name.asc")
        if c_status != 200:
            return self._send_json(components, c_status)
        # 3. strings
        st_status, strings = _supabase_rest("GET", "app_strings", query="select=id,component_id,key,es,en,updated_at&order=key.asc")
        if st_status != 200:
            return self._send_json(strings, st_status)
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
        self._send_json(tree)

    def _handle_strings_upsert(self, body: dict):
        """POST /api/strings/upsert — body: {key, es, en, component_id}."""
        required = {"key", "es", "en", "component_id"}
        if not required.issubset(body.keys()):
            return self._send_json({"error": f"missing fields: {required - body.keys()}"}, 400)
        status, resp = _supabase_rest(
            "POST", "app_strings",
            body={"key": body["key"], "es": body["es"], "en": body["en"], "component_id": body["component_id"]},
            query="on_conflict=key",
        )
        if status not in (200, 201):
            return self._send_json(resp, status)
        # Fire FCM push so all subscribed clients invalidate their cache and
        # refetch immediately. Non-blocking: if push fails, clients still
        # refresh via TTL / resume hook / pull-to-refresh.
        pushed = _fcm_push_text_cms_update()
        self._send_json({"ok": True, "pushed": pushed, "row": resp[0] if isinstance(resp, list) else resp})

    def _handle_strings_bulk_upsert(self, body: list):
        """POST /api/strings/bulk-upsert — body: [{key, es, en, component_id}, ...]."""
        if not isinstance(body, list) or not body:
            return self._send_json({"error": "body must be a non-empty array"}, 400)
        status, resp = _supabase_rest("POST", "app_strings", body=body, query="on_conflict=key")
        if status not in (200, 201):
            return self._send_json(resp, status)
        pushed = _fcm_push_text_cms_update()
        self._send_json({"ok": True, "count": len(body), "pushed": pushed, "rows": resp})

    def _handle_strings_seed(self, body: list):
        """POST /api/strings/seed — body: [{section, component, file_path, key, es, en}, ...].
        Creates sections/components on demand. Used for mass migration in Phase 2+."""
        if not isinstance(body, list) or not body:
            return self._send_json({"error": "body must be a non-empty array"}, 400)
        section_ids = {}
        component_ids = {}
        sections_created = 0
        components_created = 0
        strings_upserted = 0
        for row in body:
            # section
            sec_name = row.get("section")
            if not sec_name:
                return self._send_json({"error": f"missing 'section' in {row}"}, 400)
            if sec_name not in section_ids:
                st, r = _supabase_rest("POST", "app_sections",
                    body={"name": sec_name, "order_index": 0}, query="on_conflict=name")
                if st not in (200, 201):
                    return self._send_json(r, st)
                section_ids[sec_name] = r[0]["id"] if isinstance(r, list) else r["id"]
                sections_created += 1
            # component
            comp_name = row.get("component")
            comp_key = f"{sec_name}/{comp_name}"
            if not comp_name:
                return self._send_json({"error": f"missing 'component' in {row}"}, 400)
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
                    return self._send_json(r, st)
                component_ids[comp_key] = r[0]["id"] if isinstance(r, list) else r["id"]
                components_created += 1
            # string
            st, r = _supabase_rest("POST", "app_strings",
                body={"component_id": component_ids[comp_key], "key": row["key"], "es": row["es"], "en": row["en"]},
                query="on_conflict=key")
            if st not in (200, 201):
                return self._send_json(r, st)
            strings_upserted += 1
        self._send_json({
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
            return self._send_json(rows, status)
        self._send_json(rows)

    # ─────────────────────────────────────────────────────────────
    # Catalog search — unified across all CATALOGS (Storage source).
    # Caches each catalog in-memory for 60s to avoid hammering Storage.
    # ─────────────────────────────────────────────────────────────
    _catalog_cache: dict = {}  # kind -> (timestamp, parsed_json)

    def _get_catalog(self, kind: str):
        """Return parsed catalog dict, with a 60s in-memory cache."""
        import time as _time
        now = _time.time()
        cached = Handler._catalog_cache.get(kind)
        if cached and (now - cached[0]) < 60:
            return cached[1]
        bucket, fname, _ = CATALOGS[kind]
        url = f"{SUPABASE_STORAGE}/object/public/{bucket}/{fname}"
        try:
            with urllib.request.urlopen(urllib.request.Request(url), timeout=15) as r:
                parsed = json.loads(r.read().decode("utf-8"))
            Handler._catalog_cache[kind] = (now, parsed)
            return parsed
        except Exception as e:
            print(f"[catalog-cache] fetch {kind} failed: {e}")
            return None

    # The app tracks stats with type-specific prefixes (see
    # wallpaper_stats_service.dart): a ringtone pack lives in catalog as
    # id='zelda_pack' but is tracked as 'tone_pack_zelda_pack'. The catalog
    # id stays the user-visible/editable one; stats_id is the key we use
    # when querying admin_content_breakdown / wallpaper_stats.
    _STATS_PREFIX = {
        "ringtones": "tone_pack_",
        "stories":   "story_",
        "day_cycle": "daycycle_",
        # 'live' and 'static' track the raw wallpaper id, no prefix.
    }

    def _normalize_item(self, item: dict, kind: str) -> dict:
        """Map catalog entry → unified card row matching what the grid expects."""
        bucket, _, items_key = CATALOGS[kind]
        prev = item.get("previewFile") or item.get("imageFile") or item.get("previewImage") or ""
        prev_url = f"{SUPABASE_STORAGE}/object/public/{bucket}/{prev}" if prev else ""
        raw_id = item.get("id") or ""
        prefix = self._STATS_PREFIX.get(kind, "")
        stats_id = f"{prefix}{raw_id}" if prefix and not raw_id.startswith(prefix) else raw_id
        return {
            "id": raw_id,
            "stats_id": stats_id,            # used internally for stats lookup
            "name": item.get("name") or raw_id,
            "category": item.get("category") or "",
            "description": item.get("description", ""),
            "tags": item.get("tags", []),
            "preview_url": prev_url,
            "kind": kind,                   # 'live' | 'static' | 'stories' | ...
            "sort_order": item.get("sortOrder", 0),
            "badge": item.get("badge"),
            "created_at": item.get("createdAt") or item.get("created_at"),
            # Stats — filled below from admin_content_breakdown if available
            "view_count": 0,
            "install_count": 0,
            "share_count": 0,
            "like_count": 0,
            "download_count": 0,
        }

    def _enrich_with_stats(self, items: list) -> None:
        """Batch-fetch stats + published flag from Postgres for the page."""
        if not items:
            return
        # Stats lookup uses the prefixed id (tone_pack_*, story_*, ...)
        # set up in _normalize_item; published lookup uses the raw id since
        # only wallpapers (without prefix) ever exist in the wallpapers table.
        stats_ids = [i.get("stats_id") or i["id"] for i in items if i.get("id")]
        raw_ids = [i["id"] for i in items if i.get("id")]
        if not stats_ids:
            return
        stats_csv = ",".join(urllib.parse.quote(x, safe="") for x in stats_ids)
        raw_csv   = ",".join(urllib.parse.quote(x, safe="") for x in raw_ids)
        stats, status = self._proxy(
            f"admin_content_breakdown?id=in.({stats_csv})&select=id,content_type,views,installs,shares,likes,downloads"
        )
        by_id_stats: dict = {}
        if status == 200 and isinstance(stats, list):
            by_id_stats = {row["id"]: row for row in stats}
        pub_rows, pub_status = self._proxy(
            f"wallpapers?id=in.({raw_csv})&select=id,published,daily_eligible,media_width,media_height"
        )
        by_id_pub: dict = {}
        if pub_status == 200 and isinstance(pub_rows, list):
            by_id_pub = {row["id"]: row for row in pub_rows}
        for it in items:
            sr = by_id_stats.get(it.get("stats_id") or it["id"])
            if sr:
                it["view_count"]     = sr.get("views", 0) or 0
                it["install_count"]  = sr.get("installs", 0) or 0
                it["share_count"]    = sr.get("shares", 0) or 0
                it["like_count"]     = sr.get("likes", 0) or 0
                it["download_count"] = sr.get("downloads", 0) or 0
            pr = by_id_pub.get(it["id"])
            # Defaultea a True si Postgres no tiene la fila (ej. LIVE wallpapers
            # solo viven en Storage, no en tabla wallpapers).
            it["published"] = (pr.get("published", True) if pr else True)
            it["daily_eligible"] = (pr.get("daily_eligible", False) if pr else False)
            # Fase 2 dimension-agnostic: media_width/height para que el
            # dashboard muestre dimensions reales + detecte panoramicos por
            # ratio (>=3:1) además del flag manual category=PANORAMIC.
            it["media_width"] = (pr.get("media_width") if pr else None)
            it["media_height"] = (pr.get("media_height") if pr else None)

    def _handle_catalog_search(self, query):
        q = (query.get("q", [""])[0] or "").lower().strip()
        cat = (query.get("category", [""])[0] or "").strip()
        kinds_param = query.get("kinds", [""])[0]
        # Default to ALL known catalog kinds so the grid surfaces every
        # content type Eduardo publishes (was just live+static before, which
        # left stories / ringtones / day_cycle invisible in the dashboard).
        kinds = (
            [k for k in kinds_param.split(",") if k]
            or list(CATALOGS.keys())
        )
        limit = int(query.get("limit", ["24"])[0])
        offset = int(query.get("offset", ["0"])[0])

        # 1. Aggregate items from each requested catalog
        all_items: list[dict] = []
        for kind in kinds:
            if kind not in CATALOGS:
                continue
            catalog = self._get_catalog(kind)
            if not catalog:
                continue
            _, _, items_key = CATALOGS[kind]
            for raw in catalog.get(items_key, []):
                all_items.append(self._normalize_item(raw, kind))

        # 2. Sort: newest first (createdAt desc), fallback sort_order desc
        def sort_key(it):
            return (it.get("created_at") or "", it.get("sort_order") or 0)
        all_items.sort(key=sort_key, reverse=True)

        # 3. Filter by query + category
        def matches(it):
            if cat and it.get("category", "").upper() != cat.upper():
                return False
            if q:
                blob = " ".join([
                    it.get("name", ""),
                    it.get("id", ""),
                    it.get("description", ""),
                    " ".join(it.get("tags", [])),
                    it.get("category", ""),
                ]).lower()
                if q not in blob:
                    return False
            return True
        filtered = [it for it in all_items if matches(it)]

        # 4. Paginate
        page = filtered[offset:offset + limit]

        # 5. Enrich with stats (best-effort; if it fails, page still renders)
        try:
            self._enrich_with_stats(page)
        except Exception as e:
            print(f"[catalog-search] enrich stats failed: {e}")

        return self._send_json({
            "rows": page,
            "total": len(filtered),
            "offset": offset,
            "limit": limit,
        })

    def _proxy(self, sub_path: str, method: str = "GET", body: bytes | None = None):
        url = f"{SUPABASE_REST}/{sub_path}"
        req = urllib.request.Request(url, data=body, method=method)
        req.add_header("apikey", SERVICE_KEY)
        req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
        if body is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode("utf-8") or "[]"), r.status
        except urllib.error.HTTPError as e:
            err_body = e.read().decode()
            try:
                return json.loads(err_body), e.code
            except Exception:
                return {"error": err_body[:500]}, e.code

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)

        if path in ("/", "/index.html"):
            try:
                body = DASHBOARD_HTML.read_bytes()
                return self._send(200, "text/html; charset=utf-8", body)
            except FileNotFoundError:
                return self._send(404, "text/plain", b"dashboard html not found")

        # Sprite editor — visual drag/resize tool for canvas_scene sprites
        if path == "/sprite-editor.html":
            try:
                body = (DASHBOARD_HTML.parent / "sprite-editor.html").read_bytes()
                return self._send(200, "text/html; charset=utf-8", body)
            except FileNotFoundError:
                return self._send(404, "text/plain", b"sprite-editor.html not found")

        # Sprite frame: downloads the sprite ZIP from Storage, extracts the
        # requested frame number, and serves it as PNG. Used by the editor
        # to render the actual sprite over the bg preview.
        if path == "/api/sprite-frame":
            mk = query.get("manifest_key", [""])[0]
            frame = int(query.get("frame", ["1"])[0])
            return self._serve_sprite_frame(mk, frame)

        # -- API routes --
        if path == "/api/stats":
            data, status = self._proxy("rpc/wp_stats", "POST", b"{}")
            return self._send_json(data, status)

        if path == "/api/daily":
            limit = int(query.get("days", ["30"])[0])
            data, status = self._proxy(f"admin_daily_activity?limit={limit}")
            return self._send_json(data, status)

        if path == "/api/top-users":
            limit = int(query.get("limit", ["20"])[0])
            data, status = self._proxy(f"admin_top_users_30d?limit={limit}")
            return self._send_json(data, status)

        if path == "/api/top-wallpapers":
            # Now backed by admin_content_breakdown so the ranking surfaces
            # ALL content types (was limited to rows in `wallpapers` table
            # before — left stories/tones/aura/daycycle invisible).
            # Optional ?content_type=wallpaper,ringtone,story... filters.
            limit = int(query.get("limit", ["50"])[0])
            order = query.get("order", ["views.desc"])[0]
            ct = query.get("content_type", [""])[0]
            extra = f"&content_type=in.({ct})" if ct else ""
            data, status = self._proxy(
                f"admin_content_breakdown?order={order}&limit={limit}{extra}"
            )
            return self._send_json(data, status)

        if path == "/api/recent-events":
            limit = int(query.get("limit", ["50"])[0])
            data, status = self._proxy(
                f"wallpaper_events?select=id,ts,device_id,user_id,wallpaper_id,event_type,app_version&order=ts.desc&limit={limit}"
            )
            return self._send_json(data, status)

        if path == "/api/wallpaper":
            # Uses admin_content_breakdown so the modal opens with stats
            # for ringtones/stories/aura/daycycle too (was breaking before
            # for any id that wasn't in the `wallpapers` table).
            wid = query.get("id", [""])[0]
            data, status = self._proxy(
                f"admin_content_breakdown?id=eq.{urllib.parse.quote(wid)}"
            )
            return self._send_json(data, status)

        if path == "/api/wallpaper-events":
            wid = query.get("id", [""])[0]
            limit = int(query.get("limit", ["100"])[0])
            data, status = self._proxy(
                f"wallpaper_events?wallpaper_id=eq.{urllib.parse.quote(wid)}&order=ts.desc&limit={limit}"
            )
            return self._send_json(data, status)

        if path == "/api/wallpaper-meta":
            # Wallpaper full info (preview_url, name, description) for modal
            wid = query.get("id", [""])[0]
            data, status = self._proxy(
                f"wallpapers_v?id=eq.{urllib.parse.quote(wid)}&select=*"
            )
            return self._send_json(data, status)

        if path == "/api/search":
            q = query.get("q", [""])[0]
            cat = query.get("category", [""])[0] or None
            limit = int(query.get("limit", ["24"])[0])
            offset = int(query.get("offset", ["0"])[0])
            params = {"p_query": q, "p_limit": limit, "p_offset": offset}
            if cat: params["p_category"] = cat
            data, status = self._proxy(
                "rpc/wp_search", "POST",
                json.dumps(params).encode("utf-8")
            )
            return self._send_json(data, status)

        # ─── Unified catalog search (LIVE + STATIC from Storage) ─
        # Reads the catalog JSONs (Storage) so admin sees TODO el contenido,
        # not only items with tracked events. Stats are enriched best-effort
        # from admin_wallpaper_breakdown for the items in the current page.
        if path == "/api/catalog-search":
            return self._handle_catalog_search(query)

        if path == "/api/user-history":
            ident = query.get("id", [""])[0]
            limit = int(query.get("limit", ["100"])[0])
            data, status = self._proxy(
                "rpc/admin_user_history", "POST",
                json.dumps({"p_identity": ident, "p_limit": limit}).encode()
            )
            return self._send_json(data, status)

        if path == "/api/user-detail":
            ident = query.get("id", [""])[0]
            data, status = self._proxy(
                "rpc/admin_user_detail", "POST",
                json.dumps({"p_identity": ident}).encode()
            )
            return self._send_json(data, status)

        if path == "/api/recompute-trending":
            data, status = self._proxy("rpc/wp_recompute_trending", "POST", b"{}")
            return self._send_json({"updated": data}, status)

        # ─── Ad analytics ──────────────────────────────────────────
        if path == "/api/ad-stats":
            data, status = self._proxy("rpc/wp_ad_stats", "POST", b"{}")
            return self._send_json(data, status)

        # eCPM rates per ad kind — now sourced from ad_network_rates table
        # (migrated 2026-06-05). Dashboard displays the actual rates instead
        # of the hardcoded text subtitle that used to drift from reality.
        if path == "/api/ad-rates":
            data, status = self._proxy(
                "ad_network_rates?select=ad_kind,ecpm_usd,region,updated_at&order=ad_kind"
            )
            return self._send_json(data, status)

        if path == "/api/ad-revenue-daily":
            limit = int(query.get("days", ["30"])[0])
            data, status = self._proxy(f"admin_ad_revenue_daily?limit={limit}")
            return self._send_json(data, status)

        if path == "/api/ad-top-users":
            limit = int(query.get("limit", ["20"])[0])
            data, status = self._proxy(f"admin_ad_users?limit={limit}&order=total_ads.desc")
            return self._send_json(data, status)

        if path == "/api/recent-ad-events":
            limit = int(query.get("limit", ["50"])[0])
            data, status = self._proxy(
                f"ad_events?select=id,ts,device_id,user_id,ad_kind,placement,wallpaper_id,shown,rewarded&order=ts.desc&limit={limit}"
            )
            return self._send_json(data, status)

        # ─── Per-wallpaper installers (modal) ─────────────────────
        if path == "/api/wallpaper-installers":
            wid = query.get("id", [""])[0]
            limit = int(query.get("limit", ["50"])[0])
            data, status = self._proxy(
                "rpc/admin_wallpaper_installers", "POST",
                json.dumps({"p_wallpaper_id": wid, "p_limit": limit}).encode()
            )
            return self._send_json(data, status)

        if path == "/api/wallpaper-audience":
            wid = query.get("id", [""])[0]
            limit = int(query.get("limit", ["100"])[0])
            data, status = self._proxy(
                "rpc/admin_wallpaper_audience", "POST",
                json.dumps({"p_wallpaper_id": wid, "p_limit": limit}).encode()
            )
            return self._send_json(data, status)

        # ─── User lookup (forensic, cross-table) ──────────────────
        # Given an email, find the auth.users row, then aggregate every
        # piece of activity we have for that user_id. Truth-telling
        # endpoint: never assume, always cross-check.
        if path == "/api/user-lookup":
            email = query.get("email", [""])[0].strip().lower()
            if not email:
                return self._send_json({"error": "email required"}, 400)
            # Step 1 — resolve user_id via Supabase Admin Auth API.
            auth_url = f"https://{PROJECT_REF}.supabase.co/auth/v1/admin/users?email={urllib.parse.quote(email)}"
            req = urllib.request.Request(auth_url)
            req.add_header("apikey", SERVICE_KEY)
            req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
            try:
                with urllib.request.urlopen(req, timeout=10) as r:
                    auth_data = json.loads(r.read().decode("utf-8") or "{}")
            except urllib.error.HTTPError as e:
                return self._send_json({"error": f"auth lookup failed: {e.code}"}, e.code)
            users = auth_data.get("users", [])
            if not users:
                return self._send_json({
                    "email": email,
                    "found": False,
                    "message": "no auth.users row matches this email"
                })
            u = users[0]
            uid = u["id"]
            # Step 2 — pull rows from each table the user could touch.
            def safe(path):
                d, s = self._proxy(path)
                return d if s == 200 else {"error": d, "status": s}
            uid_q = urllib.parse.quote(uid)
            subs = safe(f"user_subscriptions?user_id=eq.{uid_q}&select=*&order=started_at.desc")
            gens = safe(f"ia_generation_queue?user_id=eq.{uid_q}&select=id,prompt,status,result_url,created_at&order=created_at.desc&limit=50")
            favs = safe(f"user_favorites?user_id=eq.{uid_q}&select=wallpaper_id,created_at&order=created_at.desc&limit=100")
            dls  = safe(f"user_downloads?user_id=eq.{uid_q}&select=wallpaper_id,downloaded_at&order=downloaded_at.desc&limit=100")
            ads  = safe(f"ad_events?user_id=eq.{uid_q}&select=ts,ad_kind,placement,shown,rewarded&order=ts.desc&limit=20")
            wps  = safe(f"wallpaper_events?user_id=eq.{uid_q}&select=ts,event_type,wallpaper_id,app_version&order=ts.desc&limit=30")
            # Try app_events too (may not exist yet if migration not applied)
            apps = safe(f"app_events?user_id=eq.{uid_q}&select=ts,event_name,props&order=ts.desc&limit=50")
            return self._send_json({
                "email": email,
                "found": True,
                "user_id": uid,
                "created_at": u.get("created_at"),
                "last_sign_in_at": u.get("last_sign_in_at"),
                "user_metadata": u.get("user_metadata"),
                "subscriptions": subs,
                "ia_generations": gens,
                "favorites": favs,
                "downloads": dls,
                "recent_ad_events": ads,
                "recent_wallpaper_events": wps,
                "recent_app_events": apps,
            })

        # ─── Engagement (app_events analytics) ────────────────────
        if path == "/api/engagement/tabs":
            data, status = self._proxy("admin_tab_views_30d?order=views.desc")
            return self._send_json(data, status)

        if path == "/api/engagement/pitch-funnel":
            data, status = self._proxy("admin_pitch_funnel_30d")
            return self._send_json(data, status)

        if path == "/api/engagement/aura-tracks":
            limit = int(query.get("limit", ["20"])[0])
            data, status = self._proxy(
                f"admin_aura_top_tracks_30d?limit={limit}")
            return self._send_json(data, status)

        if path == "/api/engagement/event-followers":
            data, status = self._proxy(
                "admin_event_followers_30d?order=follows.desc.nullslast")
            return self._send_json(data, status)

        if path == "/api/engagement/tutorial":
            data, status = self._proxy("admin_tutorial_completion_30d")
            return self._send_json(data, status)

        if path == "/api/engagement/event-counts":
            data, status = self._proxy(
                "admin_app_event_counts_24h?order=events.desc&limit=30")
            return self._send_json(data, status)

        if path == "/api/engagement/daily":
            limit = int(query.get("days", ["30"])[0])
            data, status = self._proxy(
                f"admin_app_events_daily?limit={limit}")
            return self._send_json(data, status)

        if path == "/api/engagement/terms-acceptance":
            data, status = self._proxy("admin_terms_acceptance_30d")
            return self._send_json(data, status)

        # ─── Catalog CRUD (fetch JSON from Storage) ──────────────
        # GET /api/catalog/<kind>  →  returns the parsed JSON.
        if path.startswith("/api/catalog/"):
            kind = path.split("/api/catalog/", 1)[1].strip("/")
            if kind not in CATALOGS:
                return self._send_json({"error": f"unknown catalog: {kind}"}, 400)
            bucket, fname, _items_key = CATALOGS[kind]
            url = f"{SUPABASE_STORAGE}/object/public/{bucket}/{fname}"
            req = urllib.request.Request(url)
            try:
                with urllib.request.urlopen(req, timeout=15) as r:
                    body = r.read()
                return self._send(200, "application/json; charset=utf-8", body)
            except urllib.error.HTTPError as e:
                return self._send_json({"error": e.read().decode()[:300]}, e.code)
            except Exception as e:
                return self._send_json({"error": str(e)}, 500)

        # ─── Text CMS (Postgres-backed) ───────────────────────────
        if path == '/api/strings/tree':
            return self._handle_strings_tree()
        if path == '/api/strings/public':
            return self._handle_strings_public()

        return self._send(404, "text/plain", b"not found")

    # ─── Editable field map (catalog JSON key → Postgres column) ─
    # Solo aplica a la tabla `wallpapers` (static). LIVE no toca Postgres.
    _STATIC_FIELD_MAP = {
        "name": "name",
        "description": "description",
        "category": "category",
        "tags": "tags",
        "sortOrder": "sort_order",
        "badge": "badge",
        "glowColor": "glow_color",
        "published": "published",          # bool — false = oculto del app
        "dailyEligible": "daily_eligible", # bool — true = rota en Pixora Daily curado
        # Fase 2 dimension-agnostic: permitir editar dimensions manualmente
        # desde el dashboard si una imagen se midio mal (ej. timeout en backfill).
        "mediaWidth":  "media_width",
        "mediaHeight": "media_height",
    }

    def _update_static_postgres(self, wid: str, fields: dict) -> tuple[dict, int]:
        """PATCH una sola fila en `wallpapers` con los campos editables."""
        body = {}
        for json_key, pg_col in self._STATIC_FIELD_MAP.items():
            if json_key in fields:
                body[pg_col] = fields[json_key]
        if not body:
            return ({"warning": "no editable fields"}, 200)
        # `updated_at` lo actualiza un trigger en la tabla, no lo mandamos.
        url = f"{SUPABASE_REST}/wallpapers?id=eq.{urllib.parse.quote(wid)}"
        req = urllib.request.Request(
            url, data=json.dumps(body).encode("utf-8"), method="PATCH"
        )
        req.add_header("apikey", SERVICE_KEY)
        req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("Prefer", "return=representation")
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                return (json.loads(r.read() or b"[]"), r.status)
        except urllib.error.HTTPError as e:
            return ({"error": e.read().decode()[:300]}, e.code)

    # ───── Sprite editor helpers ──────────────────────────────
    # Strict allowlist for ids that get interpolated into Storage URLs.
    # Without this, a crafted scene_id like "../../foo" could overwrite or
    # read arbitrary objects in the Supabase bucket (SERVICE_KEY has full
    # rights). Internal-only admin doesn't excuse defense-in-depth — bots
    # scanning localhost ports are a real thing.
    _SAFE_ID_RE = re.compile(r"^[a-z0-9_]{1,64}$")
    # Manifest keys can be flat ("goku_genkidama_orb") OR namespaced
    # ("pokemon_cafe/chimenea", "aquarium/firefly/moth_a") — allow up to
    # 3 segments. No "..", no leading/trailing slash, no consecutive slashes.
    _SAFE_MANIFEST_RE = re.compile(r"^[a-z0-9_]{1,40}(/[a-z0-9_]{1,40}){0,2}$")

    def _serve_sprite_frame(self, manifest_key: str, frame_n: int):
        """
        Download the sprite ZIP from wallpaper-sprites bucket, extract the
        Nth PNG frame, serve it inline. Used by the visual editor to render
        the sprite's actual texture over the bg preview.
        """
        if not manifest_key or not self._SAFE_MANIFEST_RE.match(manifest_key):
            return self._send(400, "text/plain", b"invalid manifest_key")
        # Fetch sprite manifest entry to get the zip filename
        try:
            mf_url = f"{SUPABASE_STORAGE}/object/public/wallpaper-sprites/manifest.json"
            with urllib.request.urlopen(mf_url, timeout=15) as r:
                mf = json.loads(r.read())
        except Exception as e:
            return self._send(502, "text/plain", f"manifest fetch failed: {e}".encode())
        info = mf.get(manifest_key)
        if not info:
            return self._send(404, "text/plain", f"key {manifest_key} not in manifest".encode())
        zip_path = info.get("zip")
        if not zip_path:
            return self._send(500, "text/plain", b"manifest entry has no 'zip' field")
        try:
            zip_url = f"{SUPABASE_STORAGE}/object/public/wallpaper-sprites/{zip_path}"
            with urllib.request.urlopen(zip_url, timeout=30) as r:
                zip_bytes = r.read()
        except Exception as e:
            return self._send(502, "text/plain", f"zip fetch failed: {e}".encode())
        import io as _io, zipfile as _zf
        try:
            with _zf.ZipFile(_io.BytesIO(zip_bytes)) as zf:
                names = sorted([n for n in zf.namelist() if n.endswith(".png")])
                if not names:
                    return self._send(500, "text/plain", b"no png frames in zip")
                pick = names[max(0, min(frame_n - 1, len(names) - 1))]
                png = zf.read(pick)
        except Exception as e:
            return self._send(500, "text/plain", f"zip extract failed: {e}".encode())
        return self._send(200, "image/png", png, extra_headers={"Cache-Control": "public, max-age=3600"})

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path

        # Sprite editor save — update spec sprites array and FCM invalidate
        if path == "/api/save-scene-sprites":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)
            scene_id = payload.get("scene_id")
            new_sprites = payload.get("sprites")
            if not scene_id or not isinstance(new_sprites, list):
                return self._send_json({"error": "scene_id + sprites required"}, 400)
            # Validate scene_id against strict allowlist — prevents path
            # traversal that could overwrite arbitrary Storage objects
            # using the service_role key.
            if not self._SAFE_ID_RE.match(scene_id):
                return self._send_json({"error": "invalid scene_id format"}, 400)
            # Fetch current spec, replace sprites field, PUT back
            try:
                spec_url = f"{SUPABASE_STORAGE}/object/public/wallpaper-scenes/{scene_id}.json"
                with urllib.request.urlopen(spec_url, timeout=15) as r:
                    spec = json.loads(r.read())
            except Exception as e:
                return self._send_json({"error": f"spec fetch: {e}"}, 502)
            spec["sprites"] = new_sprites
            put_url = f"{SUPABASE_STORAGE}/object/wallpaper-scenes/{scene_id}.json"
            put_body = json.dumps(spec, indent=2, ensure_ascii=False).encode("utf-8")
            req = urllib.request.Request(put_url, data=put_body, method="PUT")
            req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
            req.add_header("Content-Type", "application/json")
            req.add_header("x-upsert", "true")
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    pass
            except Exception as e:
                return self._send_json({"error": f"spec save: {e}"}, 502)
            # FCM broadcast so devices pick up the new spec without a 6h wait
            fcm_ok = False
            try:
                fcm_ok = bool(_fcm_push_catalog_invalidate("wallpapers"))
            except Exception:
                pass
            return self._send_json({
                "ok": True,
                "scene_id": scene_id,
                "sprites_updated": len(new_sprites),
                "fcm": fcm_ok,
            })

        # ─── Single-wallpaper edit (Postgres + JSON sync) ────────
        # POST /api/wallpaper-edit
        # body: {kind: "static"|"live", id: "...", fields: {name, ...}}
        if path == "/api/wallpaper-edit":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)

            kind = payload.get("kind")
            wid = payload.get("id")
            fields = payload.get("fields", {})
            if kind not in CATALOGS or not wid:
                return self._send_json({"error": "kind/id missing"}, 400)
            if not isinstance(fields, dict) or not fields:
                return self._send_json({"error": "fields required"}, 400)

            result = {"kind": kind, "id": wid, "postgres": None, "storage": None}

            # 1) Si es static, UPDATE en Postgres (fuente primaria de la app)
            if kind == "static":
                pg_resp, pg_status = self._update_static_postgres(wid, fields)
                result["postgres"] = {"status": pg_status, "response": pg_resp}
                if pg_status >= 400:
                    return self._send_json(result, pg_status)

            # 2) Sincronizar el JSON en Storage (backup + LIVE primary)
            bucket, fname, items_key = CATALOGS[kind]
            # Re-fetch catalog desde Storage (bypass cache para tener latest)
            Handler._catalog_cache.pop(kind, None)
            cat = self._get_catalog(kind)
            if not cat:
                result["storage"] = {"error": "could not load catalog"}
                return self._send_json(result, 500)
            items = cat.get(items_key, [])
            idx = next((i for i, w in enumerate(items) if w.get("id") == wid), -1)
            if idx < 0:
                result["storage"] = {"error": f"id {wid} not in catalog"}
                return self._send_json(result, 404)
            # Apply fields
            for k, v in fields.items():
                items[idx][k] = v
            cat["lastUpdated"] = datetime_now_iso()
            # PUT back to Storage
            payload_bytes = json.dumps(cat, indent=2, ensure_ascii=False).encode("utf-8")
            url = f"{SUPABASE_STORAGE}/object/{bucket}/{fname}"
            req = urllib.request.Request(url, data=payload_bytes, method="PUT")
            req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
            req.add_header("Content-Type", "application/json")
            req.add_header("x-upsert", "true")
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    result["storage"] = {"status": r.status, "ok": True}
                Handler._catalog_cache.pop(kind, None)
            except urllib.error.HTTPError as e:
                result["storage"] = {"error": e.read().decode()[:300], "status": e.code}
                return self._send_json(result, e.code)

            # Auto-invalidate the matching client cache via FCM so users see
            # the edit on their next scroll. kind=='static' → 'wallpapers',
            # kind=='live' → 'live'. Soft failure: dashboard edit still
            # reported as successful even if the push couldn't be sent.
            invalidate_scope = 'wallpapers' if kind == 'static' else 'live'
            result["fcm_invalidate"] = {
                "scope": invalidate_scope,
                "pushed": _fcm_push_catalog_invalidate(invalidate_scope),
            }

            return self._send_json(result)

        # ─── Text CMS (Postgres-backed) ───────────────────────────
        if path == '/api/strings/upsert':
            body = self._read_json_body()
            return self._handle_strings_upsert(body)
        if path == '/api/strings/bulk-upsert':
            body = self._read_json_body()
            return self._handle_strings_bulk_upsert(body)
        if path == '/api/strings/seed':
            body = self._read_json_body()
            return self._handle_strings_seed(body)

        # ─── Catalog invalidate (FCM push) ────────────────────────
        # POST /api/fcm/catalog-invalidate?scope=wallpapers|live|stories|
        # day_cycle|ringtones|events|all
        # Forces every client subscribed to 'new_content' to drop the
        # matching service cache. Used both by the manual "Invalidar"
        # button in the dashboard and auto-fired after publish actions.
        if path == '/api/fcm/catalog-invalidate':
            qs = urllib.parse.urlparse(self.path).query
            params = urllib.parse.parse_qs(qs)
            scope = (params.get('scope') or ['all'])[0]
            if scope not in _FCM_VALID_SCOPES:
                return self._send_json(
                    {"error": f"invalid scope: {scope}", "valid": sorted(_FCM_VALID_SCOPES)}, 400)
            pushed = _fcm_push_catalog_invalidate(scope)
            return self._send_json({"scope": scope, "pushed": pushed})

        return self._send(404, "text/plain", b"not found")

    def do_PUT(self):
        path = urllib.parse.urlparse(self.path).path

        # ─── Catalog CRUD (upload JSON to Storage) ───────────────
        # PUT /api/catalog/<kind>  body=JSON  →  upserts to Storage.
        if path.startswith("/api/catalog/"):
            kind = path.split("/api/catalog/", 1)[1].strip("/")
            if kind not in CATALOGS:
                return self._send_json({"error": f"unknown catalog: {kind}"}, 400)
            bucket, fname, items_key = CATALOGS[kind]
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b""
            # Validate JSON before pushing — corrupt JSON in Storage breaks the app.
            try:
                parsed = json.loads(body.decode("utf-8"))
                if not isinstance(parsed, dict) or items_key not in parsed:
                    raise ValueError(f"catalog must contain top-level '{items_key}' array")
            except Exception as e:
                return self._send_json({"error": f"invalid JSON: {e}"}, 400)
            # Re-serialize with indentation (matches existing catalog style)
            payload = json.dumps(parsed, indent=2, ensure_ascii=False).encode("utf-8")
            url = f"{SUPABASE_STORAGE}/object/{bucket}/{fname}"
            req = urllib.request.Request(url, data=payload, method="PUT")
            req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
            req.add_header("Content-Type", "application/json")
            req.add_header("x-upsert", "true")
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    resp = r.read().decode("utf-8")
                # Invalida el cache in-memory para que el siguiente GET / search
                # traiga la versión nueva de Storage (si no, sirve stale por 60s).
                Handler._catalog_cache.pop(kind, None)
                # Auto-invalidate the matching client-side cache via FCM so
                # users see the new catalog on their next scroll. Mapping:
                # static→wallpapers, live→live, stories→stories,
                # day_cycle→day_cycle, ringtones→ringtones.
                scope_map = {"static": "wallpapers", "live": "live"}
                invalidate_scope = scope_map.get(kind, kind)
                pushed = _fcm_push_catalog_invalidate(invalidate_scope)
                return self._send_json({
                    "ok": True,
                    "bucket": bucket,
                    "file": fname,
                    "count": len(parsed.get(items_key, [])),
                    "storage_response": resp[:200],
                    "fcm_invalidate": {"scope": invalidate_scope, "pushed": pushed},
                })
            except urllib.error.HTTPError as e:
                return self._send_json({"error": e.read().decode()[:300]}, e.code)
            except Exception as e:
                return self._send_json({"error": str(e)}, 500)

        return self._send(404, "text/plain", b"not found")


def open_browser():
    # Use 127.0.0.1 explicitly — on Windows "localhost" can resolve to IPv6
    # (::1), and our server is bound to IPv4 only, which yields ERR_EMPTY_RESPONSE.
    webbrowser.open(f"http://127.0.0.1:{PORT}/")


def main():
    if not DASHBOARD_HTML.exists():
        print(f"FATAL: dashboard html missing at {DASHBOARD_HTML}")
        sys.exit(1)
    print(f"Pixora Admin Dashboard")
    print(f"  Serving:    http://127.0.0.1:{PORT}/")
    print(f"  Dashboard:  {DASHBOARD_HTML}")
    print(f"  Supabase:   {SUPABASE_REST}")
    print(f"  Press Ctrl+C to stop\n")
    Timer(0.6, open_browser).start()
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        server.server_close()


if __name__ == "__main__":
    main()
