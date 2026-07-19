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
from socketserver import ThreadingMixIn
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

PORT = int(os.environ.get("PIXORA_PORT", 5758))

# NOTA: El "Pixora Admin" (/) y el "Sprite Editor" (/sprite-editor.html) son el MISMO servidor.
# Usa UN solo launcher (preferiblemente "Pixora Sprite Editor" cuando vas a editar sprites).
# El launcher mata cualquier cosa en el puerto antes de levantar para evitar choques con otros servidores (outlier, etc.).
KEYS_PATH = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
DASHBOARD_DIR = Path(__file__).parent / "dashboard"
DASHBOARD_HTML = DASHBOARD_DIR / "index.html"
# Micro-cache for the live-presence endpoints (polled by the dashboard).
# {full_path: (epoch_ts, payload)} — 10s TTL caps Supabase load regardless
# of how many tabs poll.
_PRESENCE_CACHE = {}


def _device_alias(did):
    """Deterministic memorable label for an anonymous device_id, so the admin
    sees 'Tigre Solar' instead of 'hjy5bjwndv'. Stable per device."""
    _N = ["Puma", "Halcón", "Tigre", "Lobo", "Águila", "Zorro", "Búho",
          "León", "Cuervo", "Dragón", "Lince", "Jaguar", "Gato", "Coyote"]
    _A = ["Dorado", "Plateado", "Rojo", "Azul", "Solar", "Lunar", "Ágil",
          "Sabio", "Feroz", "Nocturno", "Veloz", "Sombrío", "Místico", "Real"]
    did = did or "x"
    h = sum(ord(c) * (i + 1) for i, c in enumerate(did))
    return f"{_N[h % len(_N)]} {_A[(h // 7) % len(_A)]}"
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
    from device_images import (
        ensure_pixora_inbox,
        list_device_images,
        pull_device_image,
        pull_device_preview,
    )
except Exception as _dev_img_err:
    print(f"[wp_admin_server] device_images unavailable: {_dev_img_err}")
    def ensure_pixora_inbox(serial=None):
        pass
    def list_device_images(serial=None, limit=48):
        return []
    def pull_device_image(device_path, serial=None, dest=None):
        raise RuntimeError("device_images module missing")
    def pull_device_preview(device_path, serial=None, max_side=720):
        raise RuntimeError("device_images module missing")

try:
    from device_surface import get_device_surface, list_devices
except Exception as _dev_surf_err:
    print(f"[wp_admin_server] device_surface unavailable: {_dev_surf_err}")
    def get_device_surface(serial=None):
        return type("DS", (), {
            "to_dict": lambda self: {
                "connected": False, "serial": None, "model": None,
                "width": 1080, "height": 2340, "density": None,
                "source": "fallback", "message": "device_surface module missing",
            },
        })()
    def list_devices():
        return []

try:
    from scene_layer_utils import (
        bump_layer_revisions,
        bump_layers_with_url_changes,
        fetch_scene_spec,
        import_image_to_scene,
        put_scene_spec,
        replace_scene_layer_asset,
    )
    from sprite_pack_utils import fetch_sprite_manifest, import_sprite_pack_to_scene
except Exception as _scene_utils_err:
    print(f"[wp_admin_server] scene_layer_utils unavailable: {_scene_utils_err}")
    def bump_layer_revisions(spec, keys=None):
        return []
    def bump_layers_with_url_changes(old_spec, new_layers):
        return []
    def fetch_scene_spec(scene_id, service_key=None):
        raise RuntimeError("scene_layer_utils not loaded")
    def put_scene_spec(scene_id, spec, service_key=None):
        raise RuntimeError("scene_layer_utils not loaded")
    def replace_scene_layer_asset(scene_id, layer_key, local_file, **kwargs):
        raise RuntimeError("scene_layer_utils not loaded")
    def import_image_to_scene(scene_id, local_file, action, **kwargs):
        raise RuntimeError("scene_layer_utils not loaded")
    def fetch_sprite_manifest(service_key=None):
        raise RuntimeError("sprite_pack_utils not loaded")
    def import_sprite_pack_to_scene(scene_id, zip_path, action, **kwargs):
        raise RuntimeError("sprite_pack_utils not loaded")

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
        # quieter logs — guard against non-str args (e.g. log_error passes an
        # HTTPStatus as args[0], which isn't iterable and crashed the logger).
        if args and isinstance(args[0], str) and "/api/" in args[0]:
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

        # 2a. Sort: newest first (createdAt desc), fallback sort_order desc
        def sort_key(it):
            return (it.get("created_at") or "", it.get("sort_order") or 0)
        all_items.sort(key=sort_key, reverse=True)

        # 2b. Interleave series so two cards from the same family don't sit
        # next to each other (Eduardo: "se ven pegaditos, parece error").
        # Series key = first 2 tokens of the id (e.g. "throotle_underwater_*"
        # all share family "throotle_underwater"). We split into series-bucket
        # queues sorted newest-first, then round-robin them. The most recent
        # ones still win first slots; only adjacent duplicates get shifted.
        from collections import defaultdict, deque
        buckets = defaultdict(deque)
        family_first_seen = {}  # preserve original order between families
        for i, it in enumerate(all_items):
            wid = it.get("id", "")
            parts = wid.split("_")
            family = "_".join(parts[:2]) if len(parts) >= 2 else wid
            if family not in family_first_seen:
                family_first_seen[family] = i
            buckets[family].append(it)
        # Round-robin across families, families ordered by their first item's
        # original position (preserves global newest-first ordering).
        ordered_families = sorted(buckets.keys(), key=family_first_seen.get)
        interleaved = []
        while any(buckets[f] for f in ordered_families):
            for f in ordered_families:
                if buckets[f]:
                    interleaved.append(buckets[f].popleft())
        all_items = interleaved

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

    def _compute_report_stats(self, all_rows: list) -> dict:
        """Resumen para el dashboard de moderación. Calcula a partir
        de un pull liviano (id, wallpaper_id, status, reported_at)."""
        from datetime import datetime, timedelta, timezone
        now = datetime.now(timezone.utc)
        h24 = now - timedelta(hours=24)
        pending = sum(1 for r in all_rows if r.get("status") == "pending")
        last_24h = 0
        for r in all_rows:
            try:
                ts = datetime.fromisoformat(str(r.get("reported_at")).replace("Z", "+00:00"))
                if ts >= h24:
                    last_24h += 1
            except Exception:
                pass
        unique_wallpapers = len({r.get("wallpaper_id") for r in all_rows if r.get("status") == "pending"})
        counts: dict[str, int] = {}
        for r in all_rows:
            if r.get("status") in ("pending", "reviewed"):
                wid = r.get("wallpaper_id")
                if wid:
                    counts[wid] = counts.get(wid, 0) + 1
        with_3_plus = sum(1 for v in counts.values() if v >= 3)
        return {
            "pending": pending,
            "last_24h": last_24h,
            "unique_wallpapers": unique_wallpapers,
            "with_3_plus": with_3_plus,
        }

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

        # Free Hour current config (reads free_hour_config.json from Storage).
        if path == "/api/free-hour":
            import time as _t
            url = (f"{SUPABASE_STORAGE}/object/public/wallpaper-images/"
                   f"free_hour_config.json?t={int(_t.time())}")
            try:
                with urllib.request.urlopen(url, timeout=10) as r:
                    cfg = json.loads(r.read().decode("utf-8"))
            except Exception:
                cfg = {"enabled": False, "duration_min": 7, "hour": 20,
                       "minute": 0, "notify": True}
            return self._send_json(cfg)

        # 2026-07-04 — Darkroom is the new default. The old dashboard
        # stays available at /legacy so we can still access Text CMS
        # and Reportes UI while those get migrated.
        if path in ("/", "/index.html"):
            try:
                body = (DASHBOARD_DIR / "darkroom.html").read_bytes()
                return self._send(200, "text/html; charset=utf-8", body)
            except FileNotFoundError:
                # Fallback to legacy if darkroom is missing
                try:
                    body = DASHBOARD_HTML.read_bytes()
                    return self._send(200, "text/html; charset=utf-8", body)
                except FileNotFoundError:
                    return self._send(404, "text/plain", b"no dashboard html found")

        if path == "/legacy":
            try:
                body = DASHBOARD_HTML.read_bytes()
                return self._send(200, "text/html; charset=utf-8", body)
            except FileNotFoundError:
                return self._send(404, "text/plain", b"legacy dashboard not found")

        # Sprite editor — visual drag/resize tool for canvas_scene sprites
        if path == "/sprite-editor.html":
            try:
                body = (DASHBOARD_DIR / "sprite-editor.html").read_bytes()
                return self._send(200, "text/html; charset=utf-8", body)
            except FileNotFoundError:
                return self._send(404, "text/plain", b"sprite-editor.html not found")

        # Darkroom rework — new admin UI for wallpaper management (2026-07-04)
        if path == "/darkroom.html":
            try:
                body = (DASHBOARD_DIR / "darkroom.html").read_bytes()
                return self._send(200, "text/html; charset=utf-8", body)
            except FileNotFoundError:
                return self._send(404, "text/plain", b"darkroom.html not found")

        # Darkroom image assets (safelight, parchment, hero background, etc.)
        # Serves anything under /img/ from dashboard/img/ with mime detection.
        if path.startswith("/img/") and not path.endswith("/"):
            fname = path[len("/img/"):]
            if "/" in fname or ".." in fname:
                return self._send(400, "text/plain", b"invalid asset path")
            asset = DASHBOARD_DIR / "img" / fname
            if not asset.is_file():
                return self._send(404, "text/plain", b"asset not found")
            ext = asset.suffix.lower()
            mime = {
                ".webp": "image/webp",
                ".png":  "image/png",
                ".jpg":  "image/jpeg",
                ".jpeg": "image/jpeg",
                ".svg":  "image/svg+xml",
                ".gif":  "image/gif",
            }.get(ext, "application/octet-stream")
            return self._send(200, mime, asset.read_bytes(),
                              extra_headers={"Cache-Control": "public, max-age=3600"})

        # Explicit support for editor support modules (ES modules loaded by sprite-editor.html)
        # These must be served from root because of how the HTML is loaded at /sprite-editor.html
        try:
            if path in ("/scene_coords.js", "/scene_coords.js/"):
                local = DASHBOARD_DIR / "scene_coords.js"
                if local.is_file():
                    return self._send(200, "text/javascript; charset=utf-8", local.read_bytes())
                else:
                    print(f"[editor] scene_coords.js missing at {local}")
                    return self._send(404, "text/plain", b"scene_coords.js not found")

            # Dashboard static assets (ES modules for sprite-editor, etc.)
            dash_asset = self._serve_dashboard_asset(path)
            if dash_asset is not None:
                return dash_asset
        except Exception as asset_err:
            print(f"[asset error] {path}: {asset_err}")
            try:
                self._send(500, "text/plain", f"Asset error: {asset_err}".encode())
            except:
                pass
            return

        # Sprite frame: downloads the sprite ZIP from Storage, extracts the
        # requested frame number, and serves it as PNG. Used by the editor
        # to render the actual sprite over the bg preview.
        if path == "/api/sprite-frame":
            mk = query.get("manifest_key", [""])[0]
            frame = int(query.get("frame", ["1"])[0])
            return self._serve_sprite_frame(mk, frame)

        # Connected Android device surface (adb wm size) for sprite editor WYSIWYG.
        if path == "/api/device-surface":
            serial = query.get("serial", [""])[0] or None
            try:
                info = get_device_surface(serial)
                payload = info.to_dict()
                payload["devices"] = list_devices()
                return self._send_json(payload)
            except Exception as e:
                return self._send_json({
                    "connected": False,
                    "serial": None,
                    "model": None,
                    "width": 1080,
                    "height": 2340,
                    "density": None,
                    "source": "fallback",
                    "message": str(e),
                    "devices": [],
                })

        if path == "/api/device-images":
            serial = query.get("serial", [""])[0] or None
            limit = min(80, max(1, int(query.get("limit", ["48"])[0])))
            try:
                ensure_pixora_inbox(serial)
                images = [img.to_dict() for img in list_device_images(serial, limit)]
                return self._send_json({
                    "ok": True,
                    "images": images,
                    "inbox": "/sdcard/Pixora/inbox",
                    "hint": "Guarda o comparte imágenes a Pixora/inbox en el cel",
                })
            except Exception as e:
                return self._send_json({"ok": False, "error": str(e), "images": []}, 502)

        if path == "/api/sprite-info":
            mk = query.get("manifest_key", [""])[0]
            if not mk or not self._SAFE_MANIFEST_RE.match(mk):
                return self._send_json({"error": "manifest_key required"}, 400)
            try:
                mf = fetch_sprite_manifest(SERVICE_KEY)
                info = mf.get(mk)
                if not info:
                    return self._send_json({"error": "not in manifest"}, 404)
                return self._send_json({
                    "manifest_key": mk,
                    "frames": info.get("frames", 0),
                    "zip": info.get("zip"),
                    "size": info.get("size"),
                })
            except Exception as e:
                return self._send_json({"error": str(e)}, 502)

        if path == "/api/device-image-preview":
            device_path = query.get("path", [""])[0]
            serial = query.get("serial", [""])[0] or None
            if not device_path or ".." in device_path:
                return self._send_json({"error": "path required"}, 400)
            try:
                preview = pull_device_preview(device_path, serial=serial)
                data = preview.read_bytes()
                ctype = "image/jpeg" if preview.suffix.lower() in (".jpg", ".jpeg") else "application/octet-stream"
                return self._send(200, ctype, data)
            except Exception as e:
                return self._send_json({"error": str(e)}, 502)

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

        # ─── ALL content directly from Postgres (bypass catalog JSON) ──
        # Reads the wallpapers table directly so we surface every row
        # regardless of whether its type has a matching catalog JSON in
        # Storage. Solves the "panoramicos invisibles" bug — panoramicos
        # live only in Postgres (no separate JSON), so admin never saw
        # them until now. Ordered created_at DESC so newest content is
        # always on top. Optional ?type=static,live,panoramic,canvas_scene
        # ─── List every canvas_scene, including hidden ones ────────
        # 2026-07-15. The editor cannot list scenes from catalog_index.json:
        # hiding a scene OMITS it from that file, so an admin who hid one
        # would have no way to find it again and unhide it. Source the list
        # from the wallpaper-scenes bucket instead, which always has them all.
        #
        # Cheap by construction: the index gives us published scenes and their
        # metadata for free, so we only fetch specs for the ones missing from
        # it (i.e. the hidden few).
        if path == "/api/scenes":
            list_url = f"{SUPABASE_STORAGE}/object/list/wallpaper-scenes"
            req = urllib.request.Request(
                list_url, data=json.dumps({"prefix": "", "limit": 1000}).encode(),
                method="POST")
            req.add_header("apikey", SERVICE_KEY)
            req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
            req.add_header("Content-Type", "application/json")
            try:
                with urllib.request.urlopen(req, timeout=25) as r:
                    files = json.loads(r.read())
            except Exception as e:
                return self._send_json({"error": f"bucket list: {e}"}, 502)
            ids = {f["name"][:-5] for f in files
                   if isinstance(f, dict) and str(f.get("name", "")).endswith(".json")}

            try:
                iurl = f"{SUPABASE_STORAGE}/object/public/wallpaper-images/catalog_index.json"
                with urllib.request.urlopen(iurl, timeout=20) as r:
                    idx = json.loads(r.read())
            except Exception as e:
                return self._send_json({"error": f"index fetch: {e}"}, 502)
            indexed = {i.get("id"): i for i in idx.get("items", [])
                       if i.get("type") == "canvas_scene"}

            # Not every spec lives in wallpaper-scenes/ — iah_egyptian_giza
            # sits in wallpaper-images/scenes/. Union both sides and trust each
            # entry's own spec_url rather than assuming a path.
            rows = []
            for sid in sorted(ids | set(indexed)):
                hit = indexed.get(sid)
                if hit:
                    rows.append({
                        "id": sid,
                        "title": hit.get("title", {}),
                        "type": hit.get("type"),
                        "tags": hit.get("tags", []),
                        "preview_url": hit.get("preview_url"),
                        "published": True,
                        "hidden_in": hit.get("hidden_in", []),
                        "spec_url": hit.get("spec_url"),
                        "orphan_spec": sid not in ids,
                    })
                    continue
                # Absent from the index → hidden. Read its spec for the label.
                try:
                    surl = f"{SUPABASE_STORAGE}/object/public/wallpaper-scenes/{sid}.json"
                    with urllib.request.urlopen(surl, timeout=15) as r:
                        spec = json.loads(r.read())
                except Exception:
                    spec = {}
                bg = spec.get("background", {}) or {}
                rows.append({
                    "id": sid,
                    "title": spec.get("title", {"en": sid}),
                    "type": spec.get("type", "canvas_scene"),
                    "tags": spec.get("tags", []),
                    "preview_url": bg.get("preview_url",
                        bg.get("url", "").replace(".webp", "_preview.webp")),
                    "published": spec.get("published") is not False,
                    "hidden_in": spec.get("hidden_in", []),
                    "spec_url": f"{SUPABASE_STORAGE}/object/public/wallpaper-scenes/{sid}.json",
                    "orphan_spec": False,
                })
            return self._send_json({
                "total": len(rows),
                "index_version": idx.get("version"),
                "rows": rows,
            })

        # filter, no pagination by default (infinite scroll on client).
        # 2026-07-04.
        if path == "/api/all-wallpapers":
            types_param = query.get("type", [""])[0].strip()
            limit = int(query.get("limit", ["500"])[0])
            offset = int(query.get("offset", ["0"])[0])
            search = query.get("q", [""])[0].strip().lower()

            # Build type filter
            type_filter = ""
            if types_param:
                type_list = ",".join(t.strip() for t in types_param.split(","))
                type_filter = f"&type=in.({type_list})"

            data, status = self._proxy(
                f"wallpapers?select=id,name,description,type,category,tags,"
                f"image_path,preview_path,glow_color,badge,featured,published,"
                f"daily_eligible,author_name,media_width,media_height,"
                f"created_at,updated_at,sort_order"
                f"&order=created_at.desc&limit={limit}&offset={offset}{type_filter}"
            )
            if status >= 400 or not isinstance(data, list):
                return self._send_json({"error": data}, status)

            # Enrich con URLs de preview + client-side search filter
            for w in data:
                if w.get("preview_path"):
                    w["preview_url"] = (
                        f"{SUPABASE_STORAGE}/object/public/"
                        f"wallpaper-images/{w['preview_path']}"
                    )
                if w.get("image_path"):
                    w["image_url"] = (
                        f"{SUPABASE_STORAGE}/object/public/"
                        f"wallpaper-images/{w['image_path']}"
                    )
            if search:
                data = [
                    w for w in data
                    if search in (w.get("name") or "").lower()
                    or search in (w.get("id") or "").lower()
                    or search in (w.get("description") or "").lower()
                    or any(search in (t or "").lower() for t in (w.get("tags") or []))
                ]
            return self._send_json({
                "total": len(data),
                "offset": offset,
                "limit": limit,
                "items": data,
            }, 200)

        # Note: /api/wallpaper-update-pg is a POST endpoint — it lives
        # in do_POST below, not here.

        # ═══ Presence + real usage tracking (F0, 2026-07-11) ═══════════
        # Supersedes /api/active-devices. Sources device_presence (heartbeat,
        # once F1 ships) with fallback to app_events/wallpaper_events (marked
        # estimated) so the panel works TODAY. 10s micro-cache for polling.
        if path in ("/api/live-devices", "/api/device-detail", "/api/usage-stats"):
            import time as _t
            ck = self.path
            hit = _PRESENCE_CACHE.get(ck)
            if hit and (_t.time() - hit[0]) < 10:
                return self._send_json(hit[1], 200)

            from datetime import datetime, timezone
            if path == "/api/live-devices":
                window = int(query.get("window_min", ["90"])[0])
                limit = int(query.get("limit", ["300"])[0])
                rows, _ = self._proxy(f"admin_live_devices?order=last_seen_at.desc&limit={limit}")
                rows = rows or []
                seen = {r["device_id"] for r in rows}
                est, _ = self._proxy(f"admin_presence_proxy?order=last_seen_at.desc&limit={limit}")
                for e in (est or []):
                    if e.get("device_id") and e["device_id"] not in seen:
                        e["estimated"] = True
                        e["active_wallpaper_id"] = e.get("est_wallpaper_id")
                        rows.append(e)

                # Resolve the wallpaper preview image for any device that carries
                # a wallpaper id but no preview yet. F1 devices with a REAL id
                # already get the image via the admin_live_devices join, but
                # estimated devices only carry est_wallpaper_id (no join), so
                # their card was blank. One batched lookup fills them in. `file:*`
                # fallback ids (pre-F1 wallpapers) have no catalog row → skipped.
                need_ids = set()
                for r in rows:
                    wid = r.get("active_wallpaper_id")
                    if wid and not str(wid).startswith("file:") \
                            and not r.get("wallpaper_preview"):
                        need_ids.add(str(wid))
                if need_ids:
                    id_list = ",".join(need_ids)
                    wps, _ = self._proxy(
                        f"wallpapers?id=in.({id_list})&select=id,name,preview_path")
                    wpmap = {w["id"]: w for w in (wps or [])}
                    for r in rows:
                        wid = r.get("active_wallpaper_id")
                        w = wpmap.get(wid) if wid else None
                        if w and not r.get("wallpaper_preview"):
                            if w.get("preview_path"):
                                r["wallpaper_preview"] = (
                                    f"{SUPABASE_STORAGE}/object/public/"
                                    f"wallpaper-images/{w['preview_path']}")
                            r["wallpaper_title"] = w.get("name") or r.get("wallpaper_title")

                now = datetime.now(timezone.utc)

                def _tier(last):
                    if not last:
                        return "offline"
                    try:
                        dt = datetime.fromisoformat(str(last).replace("Z", "+00:00"))
                    except Exception:
                        return "offline"
                    mins = (now - dt).total_seconds() / 60
                    if mins < 3:
                        return "online"
                    if mins < window:
                        return "alive"
                    if mins < 43200:  # 30 días
                        return "offline"
                    return "churned"

                # Human label: email if the device ever logged in, else a
                # deterministic memorable alias. (Phone MODEL comes with F1.)
                emails = {}
                erows, _ = self._proxy("admin_device_email?select=device_id,email&limit=2000")
                for e in (erows or []):
                    emails[e.get("device_id")] = e.get("email")
                counts = {}
                for r in rows:
                    r["tier"] = _tier(r.get("last_seen_at"))
                    counts[r["tier"]] = counts.get(r["tier"], 0) + 1
                    did = r.get("device_id", "")
                    r["email"] = emails.get(did)
                    r["label"] = emails.get(did) or _device_alias(did)
                payload = {"devices": rows, "counts": counts, "total": len(rows)}

            elif path == "/api/device-detail":
                did = query.get("device_id", [""])[0]
                if not did:
                    return self._send_json({"error": "device_id required"}, 400)
                pres, _ = self._proxy(f"admin_live_devices?device_id=eq.{did}")
                totals, _ = self._proxy(
                    f"usage_totals?device_id=eq.{did}&order=total_seconds.desc&limit=20")
                viewed, _ = self._proxy(
                    f"wallpaper_events?device_id=eq.{did}&event_type=eq.view"
                    f"&select=wallpaper_id,ts&order=ts.desc&limit=50")
                recent, _ = self._proxy(
                    f"app_events?device_id=eq.{did}&select=event_name,ts&order=ts.desc&limit=30")
                em, _ = self._proxy(f"admin_device_email?device_id=eq.{did}&select=email")
                presence = (pres[0] if pres else {})
                email = (em[0].get("email") if em else None)
                presence["email"] = email
                presence["label"] = email or _device_alias(did)
                payload = {
                    "presence": presence,
                    "usage_totals": totals or [],
                    "viewed": viewed or [],
                    "recent_events": recent or [],
                }

            else:  # /api/usage-stats
                days = int(query.get("days", ["30"])[0])
                data, _ = self._proxy(
                    "rpc/admin_usage_stats", "POST",
                    json.dumps({"p_days": days}).encode("utf-8"))
                payload = data if isinstance(data, dict) else {"stats": data}

            _PRESENCE_CACHE[ck] = (_t.time(), payload)
            return self._send_json(payload, 200)

        # ─── Active devices analytics (testers monitoring) ────────
        # Devices únicos con events en la ventana ?days=N. Cross-check
        # con emails de Eduardo para excluir su ruido. Cada device viene
        # con perfil: total events, breakdown por tipo, primera/ultima
        # actividad, app_versions vistas, autenticacion. Detecta batches
        # (>=5 devices misma fecha + misma version = pre-launch bots).
        # 2026-07-02 — creado tras confirmacion PrimeTestLab activo.
        if path == "/api/active-devices":
            from datetime import datetime, timezone, timedelta as _td
            from collections import defaultdict
            days = int(query.get("days", ["7"])[0])
            include_edu = query.get("include_eduardo", ["0"])[0] == "1"
            since = (datetime.now(timezone.utc) - _td(days=days)).strftime("%Y-%m-%dT%H:%M:%S")

            # Fetch all events in window (paginated)
            events = []
            offset = 0
            while True:
                batch, sc = self._proxy(
                    f"wallpaper_events?ts=gte.{since}"
                    f"&select=device_id,user_id,event_type,ts,app_version,wallpaper_id"
                    f"&limit=1000&offset={offset}"
                )
                if sc >= 400 or not batch:
                    break
                events.extend(batch)
                if len(batch) < 1000:
                    break
                offset += 1000
            events = [e for e in events if e.get("device_id")]

            # Identify Eduardo (users + devices)
            edu_uids = set()
            edu_devs = set()
            if not include_edu:
                edu_users, _ = self._proxy(
                    "users?email=in.(eduardojcr@gmail.com,gameover.lalo.83@gmail.com,"
                    "pixoramain@gmail.com,testerorbix@gmail.com)&select=id"
                )
                edu_uids = {u["id"] for u in (edu_users or [])}
                for uid in edu_uids:
                    likes, _ = self._proxy(f"wallpaper_likes?user_id=eq.{uid}&select=device_id&limit=1000")
                    for r in (likes or []):
                        if r.get("device_id"): edu_devs.add(r["device_id"])
                    ev, _ = self._proxy(f"wallpaper_events?user_id=eq.{uid}&select=device_id&limit=1000")
                    for r in (ev or []):
                        if r.get("device_id"): edu_devs.add(r["device_id"])
                events = [e for e in events if e.get("user_id") not in edu_uids and e["device_id"] not in edu_devs]

            # Aggregate per device
            by_dev = defaultdict(lambda: {"events":0,"install":0,"view":0,"download":0,"share":0,
                                          "first":None,"last":None,"app_versions":set(),
                                          "wallpapers":set(),"user_id":None})
            for e in events:
                d = e["device_id"]
                b = by_dev[d]
                b["events"] += 1
                et = e["event_type"]
                if et in b: b[et] += 1
                ts = e["ts"]
                if not b["first"] or ts < b["first"]: b["first"] = ts
                if not b["last"] or ts > b["last"]: b["last"] = ts
                if e.get("app_version"): b["app_versions"].add(e["app_version"])
                if e.get("wallpaper_id"): b["wallpapers"].add(e["wallpaper_id"])
                if e.get("user_id"): b["user_id"] = e["user_id"]

            # Classify each device: CORE_TESTER / CASUAL / BOT_BATCH / SINGLE_HIT
            # BOT_BATCH detection — pre-launch bots de Google Play tienen firma:
            #   1) >=10 devices el mismo día con la misma app_version
            #   2) promedio de events por device en el batch <= 2 (bots hacen 1
            #      install + 1 view y ya)
            # Sin la restriccion de events, un release day de app real (donde
            # muchos testers instalan el mismo dia) daria falso positivo.
            from collections import Counter, defaultdict
            batch_events = defaultdict(list)
            for d, b in by_dev.items():
                if b["first"] and b["app_versions"]:
                    key = (b["first"][:10], min(b["app_versions"]))
                    batch_events[key].append(b["events"])
            bot_keys = set()
            for key, ev_list in batch_events.items():
                if len(ev_list) >= 10:
                    avg_events = sum(ev_list) / len(ev_list)
                    if avg_events <= 2.0:
                        bot_keys.add(key)

            items = []
            for d, b in by_dev.items():
                key = (b["first"][:10], min(b["app_versions"])) if b["first"] and b["app_versions"] else None
                is_bot = key in bot_keys if key else False
                if is_bot:
                    kind = "BOT_BATCH"
                elif b["events"] >= 5 and b["install"] >= 2:
                    kind = "CORE_TESTER"
                elif b["events"] >= 2:
                    kind = "CASUAL"
                else:
                    kind = "SINGLE_HIT"
                # calc span in days
                span_days = 0.0
                if b["first"] and b["last"]:
                    try:
                        f_dt = datetime.fromisoformat(b["first"].replace("Z","+00:00"))
                        l_dt = datetime.fromisoformat(b["last"].replace("Z","+00:00"))
                        span_days = round((l_dt - f_dt).total_seconds() / 86400, 2)
                    except Exception:
                        pass
                items.append({
                    "device_id": d,
                    "kind": kind,
                    "events": b["events"],
                    "install": b["install"],
                    "view": b["view"],
                    "download": b["download"],
                    "share": b["share"],
                    "app_version_latest": max(b["app_versions"]) if b["app_versions"] else None,
                    "wallpapers_touched": len(b["wallpapers"]),
                    "first": b["first"],
                    "last": b["last"],
                    "span_days": span_days,
                    "authed": bool(b["user_id"]),
                    "user_id": b["user_id"],
                })
            items.sort(key=lambda x: x["events"], reverse=True)

            # Summary
            kinds = Counter(i["kind"] for i in items)
            return self._send_json({
                "days": days,
                "total_devices": len(items),
                "eduardo_excluded": not include_edu,
                "summary": {
                    "CORE_TESTER": kinds.get("CORE_TESTER", 0),
                    "CASUAL": kinds.get("CASUAL", 0),
                    "SINGLE_HIT": kinds.get("SINGLE_HIT", 0),
                    "BOT_BATCH": kinds.get("BOT_BATCH", 0),
                },
                "items": items,
            }, 200)

        # ─── Recently added wallpapers (freshness monitoring) ─────
        # Wallpapers creados en los últimos ?days=N con stats mergeados
        # (likes/downloads/views/installs). Feeds panel "Últimos agregados"
        # + badge NUEVO en la tabla top wallpapers. 2026-07-02.
        if path == "/api/recent-wallpapers":
            from datetime import datetime, timezone, timedelta as _td
            days = int(query.get("days", ["14"])[0])
            limit = int(query.get("limit", ["30"])[0])
            since = (datetime.now(timezone.utc) - _td(days=days)).strftime("%Y-%m-%dT%H:%M:%S")
            wps, s1 = self._proxy(
                f"wallpapers?created_at=gte.{since}&order=created_at.desc"
                f"&limit={limit}&select=id,name,category,type,created_at,badge,featured,published"
            )
            if s1 >= 400 or not isinstance(wps, list):
                return self._send_json({"error": "wallpapers fetch failed", "detail": wps}, s1 or 500)
            if not wps:
                return self._send_json({"days": days, "total": 0, "items": []}, 200)
            ids = ",".join(w["id"] for w in wps)
            stats, _ = self._proxy(
                f"admin_content_breakdown?id=in.({ids})"
                f"&select=id,likes,downloads,views,installs,unique_devices,install_rate_pct"
            )
            stats_map = {s["id"]: s for s in (stats or [])}
            for w in wps:
                s = stats_map.get(w["id"], {})
                w["likes"] = s.get("likes", 0)
                w["downloads"] = s.get("downloads", 0)
                w["views"] = s.get("views", 0)
                w["installs"] = s.get("installs", 0)
                w["unique_devices"] = s.get("unique_devices", 0)
                w["install_rate_pct"] = s.get("install_rate_pct", 0.0)
            return self._send_json({"days": days, "total": len(wps), "items": wps}, 200)

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

        # 2026-06-22 — Day Cycle catalog (lives in Storage JSON, not Postgres)
        if path == "/api/day-cycle/list":
            url = f"{SUPABASE_STORAGE}/object/public/wallpaper-images/day_cycle_catalog.json"
            try:
                with urllib.request.urlopen(url, timeout=15) as r:
                    return self._send_json(json.loads(r.read()), 200)
            except Exception as e:
                return self._send_json({"error": str(e), "themes": []}, 502)

        # 2026-06-20 — Content moderation (Google Play AI policy compliance)
        if path == "/api/reports":
            status_filter = query.get("status", ["pending"])[0]
            badge_only = query.get("badge_only", ["0"])[0] == "1"
            # Pull raw rows from wallpaper_reports (service-role bypasses RLS).
            filter_q = "" if status_filter == "all" else f"&status=eq.{status_filter}"
            rows, http_status = self._proxy(
                f"wallpaper_reports?select=*&order=reported_at.desc{filter_q}&limit=200"
            )
            if http_status >= 400 or not isinstance(rows, list):
                return self._send_json({"reports": [], "stats": {}}, http_status)
            # Compute stats from all-status pull (admin overview)
            all_rows, _ = self._proxy("wallpaper_reports?select=id,wallpaper_id,status,reported_at&limit=1000")
            stats = self._compute_report_stats(all_rows or [])
            # Attach distinct_reporter_count per wallpaper for the badge.
            counts = {}
            for r in (all_rows or []):
                if r.get("status") in ("pending", "reviewed"):
                    counts[r.get("wallpaper_id")] = counts.get(r.get("wallpaper_id"), 0) + 1
            for r in rows:
                r["distinct_reporter_count"] = counts.get(r.get("wallpaper_id"), 1)
            if badge_only:
                return self._send_json({"stats": stats}, 200)
            return self._send_json({"reports": rows, "stats": stats}, 200)

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

        # ─── Likes audit (counter drift detection) ────────────────
        # Compara wallpaper_stats.likes (counter) vs COUNT(wallpaper_likes)
        # rows reales. Devuelve solo los wallpapers con drift para monitoring
        # rapido de desincronizaciones. Uso: dashboard alarma cuando != 0.
        # 2026-07-02 — creado tras auditoria del pipeline de likes.
        if path == "/api/wallpaper-likes-audit":
            # Snapshot counters
            stats_data, s1 = self._proxy(
                "wallpaper_stats?select=wallpaper_id,likes&likes=gt.0&limit=5000"
            )
            if s1 >= 400:
                return self._send_json({"error": "stats fetch failed"}, s1)
            counters = {r["wallpaper_id"]: r["likes"] for r in (stats_data or [])}

            # Snapshot rows reales (paginado)
            from collections import Counter
            row_counts = Counter()
            offset = 0
            while True:
                batch, sc = self._proxy(
                    f"wallpaper_likes?select=wallpaper_id&limit=1000&offset={offset}"
                )
                if sc >= 400 or not batch:
                    break
                for r in batch:
                    row_counts[r["wallpaper_id"]] += 1
                if len(batch) < 1000:
                    break
                offset += 1000

            # Diff — solo los con drift (incluye wallpapers en likes pero sin stats row)
            all_ids = set(counters) | set(row_counts)
            drift = []
            for wid in all_ids:
                c = counters.get(wid, 0)
                r = row_counts.get(wid, 0)
                if c != r:
                    drift.append({
                        "wallpaper_id": wid,
                        "counter": c,
                        "rows": r,
                        "diff": r - c,
                    })
            drift.sort(key=lambda x: abs(x["diff"]), reverse=True)
            return self._send_json({
                "total_wallpapers_checked": len(all_ids),
                "total_with_drift": len(drift),
                "counter_total": sum(counters.values()),
                "rows_total": sum(row_counts.values()),
                "drift": drift,
            }, 200)

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

    def _handle_import_scene_image_multipart(self):
        """POST /api/import-scene-image — PC file upload into canvas_scene."""
        import cgi
        import tempfile

        ctype = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in ctype:
            return self._send_json({"error": "multipart/form-data required"}, 400)

        environ = {"REQUEST_METHOD": "POST", "CONTENT_TYPE": ctype}
        form = cgi.FieldStorage(fp=self.rfile, headers=self.headers, environ=environ)

        def field(name: str, default: str = "") -> str:
            item = form.get(name)
            if item is None:
                return default
            if isinstance(item, list):
                item = item[0]
            return item.value if hasattr(item, "value") else str(item)

        scene_id = field("scene_id")
        action = field("action", "replace_layer")
        layer_key = field("layer_key") or None
        new_layer_key = field("new_layer_key") or None
        z = int(field("z") or "1")

        if not scene_id or not self._SAFE_ID_RE.match(scene_id):
            return self._send_json({"error": "valid scene_id required"}, 400)
        if action not in ("replace_layer", "add_layer", "background"):
            return self._send_json({"error": "invalid action"}, 400)
        for lk in (layer_key, new_layer_key):
            if lk and not self._SAFE_ID_RE.match(lk):
                return self._send_json({"error": f"invalid layer key: {lk}"}, 400)

        file_item = form.get("file")
        if file_item is None or not getattr(file_item, "file", None):
            return self._send_json({"error": "file field required"}, 400)

        suffix = Path(file_item.filename or "upload.jpg").suffix or ".jpg"
        tmp_path = Path(tempfile.mkstemp(suffix=suffix)[1])
        try:
            tmp_path.write_bytes(file_item.file.read())
            summary = import_image_to_scene(
                scene_id,
                tmp_path,
                action,
                layer_key=layer_key,
                new_layer_key=new_layer_key,
                z=z,
                service_key=SERVICE_KEY,
            )
        except Exception as e:
            return self._send_json({"error": str(e)}, 502)
        finally:
            try:
                tmp_path.unlink(missing_ok=True)
            except Exception:
                pass

        fcm_ok = False
        try:
            fcm_ok = bool(_fcm_push_catalog_invalidate("wallpapers"))
        except Exception:
            pass
        return self._send_json({"ok": True, **summary, "fcm": fcm_ok})

    def _handle_import_sprite_pack_multipart(self):
        """POST /api/import-sprite-pack — PC ZIP upload into canvas_scene sprite."""
        import cgi
        import tempfile

        ctype = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in ctype:
            return self._send_json({"error": "multipart/form-data required"}, 400)

        environ = {"REQUEST_METHOD": "POST", "CONTENT_TYPE": ctype}
        form = cgi.FieldStorage(fp=self.rfile, headers=self.headers, environ=environ)

        def field(name: str, default: str = "") -> str:
            item = form.get(name)
            if item is None:
                return default
            if isinstance(item, list):
                item = item[0]
            return item.value if hasattr(item, "value") else str(item)

        scene_id = field("scene_id")
        action = field("action", "add_sprite")
        manifest_key = field("manifest_key") or None
        sprite_name = field("sprite_name") or None
        frame_skip = float(field("frame_skip") or "2")

        if not scene_id or not self._SAFE_ID_RE.match(scene_id):
            return self._send_json({"error": "valid scene_id required"}, 400)
        if action not in ("replace_sprite", "add_sprite"):
            return self._send_json({"error": "invalid action"}, 400)
        if manifest_key and not self._SAFE_MANIFEST_RE.match(manifest_key):
            return self._send_json({"error": "invalid manifest_key"}, 400)

        file_item = form.get("file")
        if file_item is None or not getattr(file_item, "file", None):
            return self._send_json({"error": "file field required"}, 400)

        tmp_path = Path(tempfile.mkstemp(suffix=".zip")[1])
        try:
            tmp_path.write_bytes(file_item.file.read())
            summary = import_sprite_pack_to_scene(
                scene_id,
                tmp_path,
                action,
                manifest_key=manifest_key,
                sprite_name=sprite_name,
                frame_skip=frame_skip,
                service_key=SERVICE_KEY,
            )
        except Exception as e:
            return self._send_json({"error": str(e)}, 502)
        finally:
            try:
                tmp_path.unlink(missing_ok=True)
            except Exception:
                pass

        fcm_ok = False
        try:
            fcm_ok = bool(_fcm_push_catalog_invalidate("wallpapers"))
        except Exception:
            pass
        return self._send_json({"ok": True, **summary, "fcm": fcm_ok})

    _DASHBOARD_MIME = {
        ".js": "text/javascript; charset=utf-8",
        ".css": "text/css; charset=utf-8",
        ".json": "application/json; charset=utf-8",
        ".map": "application/json; charset=utf-8",
        ".woff2": "font/woff2",
    }

    def _serve_dashboard_asset(self, path: str):
        """Serve files from tools/wallpapers/dashboard/ (e.g. scene_coords.js).
        This is required for the sprite-editor.html ES module imports.
        """
        name = path.lstrip("/")
        if not name or "/" in name or "\\" in name or name.startswith("."):
            if name.endswith(('.js', '.mjs')):
                print(f"[dashboard-assets] REJECTED (bad name): {path!r}")
            return None
        suffix = Path(name).suffix.lower()
        if suffix not in self._DASHBOARD_MIME:
            return None

        local = DASHBOARD_DIR / name
        if not local.is_file():
            print(f"[dashboard-assets] 404 for {path!r} (looked in {local})")
            return None

        # Safety: must be direct child of dashboard dir
        try:
            local.resolve().relative_to(DASHBOARD_DIR.resolve())
        except Exception:
            print(f"[dashboard-assets] path escape attempt: {path!r}")
            return None

        try:
            body = local.read_bytes()
            return self._send(200, self._DASHBOARD_MIME[suffix], body)
        except Exception as e:
            print(f"[dashboard-assets] read error for {name}: {e}")
            return None

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

        # ─── Free Hour: enable/disable the daily ad-free happy hour ────────
        # Writes free_hour_config.json to Storage. App reads it (TTL 30min /
        # on resume). Default in the app is OFF, so absence = current behavior.
        if path == "/api/free-hour":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)
            try:
                enabled = bool(payload.get("enabled", False))
                hour = int(payload.get("hour", 20))
                minute = int(payload.get("minute", 0))
                dur = int(payload.get("duration_min", 7))
                notify = payload.get("notify", True) is not False
            except Exception:
                return self._send_json({"error": "bad fields"}, 400)
            if not (0 <= hour <= 23 and 0 <= minute < 60 and 1 <= dur <= 240
                    and (hour * 60 + minute + dur) <= 1440):
                return self._send_json({"error": "invalid time/duration"}, 400)
            cfg = {"enabled": enabled, "duration_min": dur, "hour": hour,
                   "minute": minute, "notify": notify}
            put_url = f"{SUPABASE_STORAGE}/object/wallpaper-images/free_hour_config.json"
            req = urllib.request.Request(
                put_url, data=json.dumps(cfg, indent=2).encode("utf-8"), method="PUT")
            req.add_header("apikey", SERVICE_KEY)
            req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
            req.add_header("Content-Type", "application/json")
            req.add_header("x-upsert", "true")
            req.add_header("Cache-Control", "no-cache, max-age=0")
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    st = r.status
            except urllib.error.HTTPError as e:
                return self._send_json({"error": e.read().decode()[:500]}, e.code)
            return self._send_json({"ok": True, "config": cfg, "storage_status": st})

        # ─── Update wallpaper metadata directly in Postgres ────────
        # Simple edit endpoint that touches ONLY Postgres for any
        # wallpapers row (static/live/panoramic/canvas_scene). Fields
        # allowed: name, description, tags, glow_color, badge, category,
        # featured, published, daily_eligible. 2026-07-04 — for /TODOS
        # admin view inline edit. Uses PATCH with Prefer=representation
        # so the updated row comes back for verification.
        if path == "/api/wallpaper-update-pg":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)
            wid = payload.get("id")
            fields = payload.get("fields", {})
            if not wid or not isinstance(fields, dict) or not fields:
                return self._send_json({"error": "id + fields required"}, 400)
            allowed = {"name", "description", "tags", "glow_color", "badge",
                       "category", "featured", "published", "daily_eligible"}
            clean = {k: v for k, v in fields.items() if k in allowed}
            if not clean:
                return self._send_json({"error": "no allowed fields"}, 400)

            patch_url = (
                f"{SUPABASE_REST}/wallpapers?id=eq."
                f"{urllib.parse.quote(wid)}"
            )
            patch_body = json.dumps(clean).encode("utf-8")
            req = urllib.request.Request(patch_url, data=patch_body, method="PATCH")
            req.add_header("apikey", SERVICE_KEY)
            req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
            req.add_header("Content-Type", "application/json")
            req.add_header("Prefer", "return=representation")
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    data = json.loads(r.read().decode("utf-8") or "[]")
                    status = r.status
            except urllib.error.HTTPError as e:
                data = {"error": e.read().decode()[:500]}
                status = e.code
            try:
                pushed = _fcm_push_catalog_invalidate("wallpapers")
            except Exception:
                pushed = False
            return self._send_json({
                "id": wid,
                "updated_fields": list(clean.keys()),
                "postgres_status": status,
                "postgres_response": data,
                "fcm_pushed": pushed,
            }, status if status < 400 else 500)

        # (see GET /api/scenes for the listing that survives hiding)
        # ─── canvas_scene visibility ───────────────────────────────
        # 2026-07-15. Two independent switches, both stored in the scene spec
        # (wallpaper-scenes/<id>.json), which is the source of truth that
        # `pixora_publish.py rebuild-index` derives the index from — so these
        # survive a rebuild by construction.
        #
        #   published:false  → hard hide. The item is OMITTED from
        #       catalog_index.json, which is the only thing that hides content
        #       on ALREADY-SHIPPED clients (they never learned to read a flag).
        #   hidden_in:[...]  → per-surface curation ("parallax_tab", "cultura",
        #       "daily", "events"). Item stays in the index; the app filters it
        #       per surface. Needs the 1.7.59+ build to take effect.
        #
        # NOTE: the `published` column on the `wallpapers` table does NOT
        # govern scenes — a scene and its static twin are separate products
        # with separate ids (pilot_drive vs pilot_drive_snowy). See
        # /api/wallpaper-update-pg for the static side.
        # Body: {id, published?: bool, hidden_in?: [str]}
        if path == "/api/scene-visibility":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)
            sid = payload.get("id")
            if not sid:
                return self._send_json({"error": "id required"}, 400)
            has_pub = "published" in payload
            has_hidden = "hidden_in" in payload
            if not has_pub and not has_hidden:
                return self._send_json(
                    {"error": "published and/or hidden_in required"}, 400)
            published = payload.get("published")
            if has_pub and not isinstance(published, bool):
                return self._send_json({"error": "published must be bool"}, 400)
            hidden_in = payload.get("hidden_in")
            if has_hidden:
                valid = {"parallax_tab", "cultura", "daily", "events"}
                if (not isinstance(hidden_in, list)
                        or not all(isinstance(s, str) for s in hidden_in)
                        or not set(hidden_in) <= valid):
                    return self._send_json(
                        {"error": f"hidden_in must be a list from {sorted(valid)}"}, 400)

            def _storage_get(bucket, key):
                url = f"{SUPABASE_STORAGE}/object/public/{bucket}/{key}"
                with urllib.request.urlopen(url, timeout=20) as r:
                    return json.loads(r.read())

            def _storage_put(bucket, key, obj):
                url = f"{SUPABASE_STORAGE}/object/{bucket}/{key}"
                req = urllib.request.Request(
                    url, data=json.dumps(obj, indent=2, ensure_ascii=False).encode("utf-8"),
                    method="PUT")
                req.add_header("apikey", SERVICE_KEY)
                req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
                req.add_header("Content-Type", "application/json")
                req.add_header("x-upsert", "true")
                req.add_header("Cache-Control", "no-cache, max-age=0")
                with urllib.request.urlopen(req, timeout=25) as r:
                    return r.status

            # Specs are not all in one bucket (iah_egyptian_giza lives in
            # wallpaper-images/scenes/), so resolve the location from the
            # index's spec_url and only fall back to the common path.
            spec_bucket, spec_key = "wallpaper-scenes", f"{sid}.json"
            try:
                _idx_probe = _storage_get("wallpaper-images", "catalog_index.json")
                for _i in _idx_probe.get("items", []):
                    if _i.get("id") == sid and _i.get("spec_url"):
                        _tail = str(_i["spec_url"]).split("/object/public/", 1)[-1]
                        spec_bucket, spec_key = _tail.split("/", 1)
                        break
            except Exception:
                pass

            # 1) Patch the spec — the source of truth.
            try:
                spec = _storage_get(spec_bucket, spec_key)
            except Exception as e:
                return self._send_json(
                    {"error": f"spec fetch ({spec_bucket}/{spec_key}): {e}"}, 404)
            if has_pub:
                spec["published"] = published
            if has_hidden:
                if hidden_in:
                    spec["hidden_in"] = hidden_in
                else:
                    spec.pop("hidden_in", None)
            try:
                _storage_put(spec_bucket, spec_key, spec)
            except Exception as e:
                return self._send_json({"error": f"spec write: {e}"}, 502)

            # 2) Mirror into the index, matching rebuild-index's derivation so
            #    a later rebuild produces byte-identical entries.
            try:
                idx = _storage_get("wallpaper-images", "catalog_index.json")
            except Exception as e:
                return self._send_json({"error": f"index fetch: {e}"}, 502)
            import time as _t
            # Preservar created_at del entry previo (para el orden del editor);
            # si la escena es nueva y no lo tiene, estamparlo ahora.
            _old = next((i for i in idx.get("items", []) if i.get("id") == sid), None)
            _created = (_old or {}).get("created_at") or spec.get("created_at") \
                or _t.strftime("%Y-%m-%dT%H:%M:%SZ", _t.gmtime())
            items = [i for i in idx.get("items", []) if i.get("id") != sid]
            is_published = spec.get("published") is not False
            if is_published:
                bg = spec.get("background", {}) or {}
                entry = {
                    "id": sid,
                    "type": spec.get("type"),
                    "schema": spec.get("schema_version", 1),
                    "title": spec.get("title", {"en": sid}),
                    "preview_url": bg.get("preview_url",
                        bg.get("url", "").replace(".webp", "_preview.webp")),
                    "tags": spec.get("tags", []),
                    "category": spec.get("category"),
                    "featured": spec.get("featured", False),
                    "spec_url": f"{SUPABASE_STORAGE}/object/public/{spec_bucket}/{spec_key}",
                    "created_at": _created,
                }
                # Carry description + glow from the spec so making a scene
                # visible doesn't wipe the copy the app reads from the index.
                if spec.get("description"):
                    entry["description"] = spec["description"]
                if spec.get("description_rich"):
                    entry["description_rich"] = spec["description_rich"]
                if spec.get("glow_color"):
                    entry["glow_color"] = spec["glow_color"]
                if spec.get("hidden_in"):
                    entry["hidden_in"] = spec["hidden_in"]
                items.append(entry)
            items.sort(key=lambda it: (it.get("type") or "", it.get("id") or ""))
            idx["items"] = items
            idx["version"] = int(idx.get("version", 0)) + 1
            idx["updated_at"] = _t.strftime("%Y-%m-%dT%H:%M:%SZ", _t.gmtime())
            try:
                _storage_put("wallpaper-images", "catalog_index.json", idx)
            except Exception as e:
                return self._send_json({"error": f"index write: {e}"}, 502)

            # 3) Tell devices to drop their cached catalog. This also re-fetches
            #    specs in place and nudges Daily rotation (v1.7.43 behaviour).
            try:
                pushed = _fcm_push_catalog_invalidate("wallpapers")
            except Exception:
                pushed = False

            return self._send_json({
                "ok": True,
                "id": sid,
                "published": is_published,
                "hidden_in": spec.get("hidden_in", []),
                "in_index": is_published,
                "index_version": idx["version"],
                "fcm_pushed": pushed,
            })

        # 2026-06-20 — Resolve a moderation report (Google Play AI policy).
        # Body: {id: uuid, status: "removed"|"reviewed"|"dismissed", admin_notes?: str}
        if path == "/api/reports/resolve":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)
            rid = payload.get("id")
            status = payload.get("status")
            admin_notes = payload.get("admin_notes")
            if not rid or status not in ("removed", "reviewed", "dismissed"):
                return self._send_json({"error": "id + valid status required"}, 400)
            rpc_body = json.dumps({
                "p_report_id": rid,
                "p_status": status,
                "p_admin_notes": admin_notes,
            }).encode("utf-8")
            data, http_status = self._proxy("rpc/resolve_report", "POST", rpc_body)
            return self._send_json({"ok": http_status < 400, "data": data}, http_status)

        # 2026-06-22 — Day Cycle: actualizar metadata (name/desc/glow) o
        # eliminar un theme completo. Body: {id, action: "update"|"delete",
        # changes?: {name, description, glowColor}}
        if path == "/api/day-cycle/edit":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)
            theme_id = payload.get("id")
            action = payload.get("action")
            if not theme_id or action not in ("update", "delete"):
                return self._send_json({"error": "id + action(update|delete) required"}, 400)
            # Cargar catálogo
            cat_url = f"{SUPABASE_STORAGE}/object/public/wallpaper-images/day_cycle_catalog.json"
            try:
                with urllib.request.urlopen(cat_url, timeout=15) as r:
                    catalog = json.loads(r.read())
            except Exception as e:
                return self._send_json({"error": f"catalog fetch: {e}"}, 502)
            themes = catalog.get("themes", [])
            idx = next((i for i, t in enumerate(themes) if t.get("id") == theme_id), -1)
            if idx < 0:
                return self._send_json({"error": "theme not found"}, 404)
            if action == "delete":
                themes.pop(idx)
            else:
                changes = payload.get("changes") or {}
                for k in ("name", "description", "glowColor"):
                    if k in changes and isinstance(changes[k], str):
                        themes[idx][k] = changes[k]
            catalog["themes"] = themes
            # PUT back
            put_url = f"{SUPABASE_STORAGE}/object/wallpaper-images/day_cycle_catalog.json"
            req = urllib.request.Request(put_url,
                data=json.dumps(catalog, indent=2, ensure_ascii=False).encode("utf-8"),
                method="PUT")
            req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
            req.add_header("Content-Type", "application/json")
            req.add_header("x-upsert", "true")
            try:
                urllib.request.urlopen(req, timeout=30)
            except Exception as e:
                return self._send_json({"error": f"put: {e}"}, 502)
            return self._send_json({"ok": True, "themes_remaining": len(themes)}, 200)

        # Sprite editor save — update spec sprites and/or image_layers + FCM
        if path == "/api/save-scene-sprites":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)
            scene_id = payload.get("scene_id")
            new_sprites = payload.get("sprites")
            new_layers = payload.get("image_layers")
            new_cycles = payload.get("cycles")
            if not scene_id:
                return self._send_json({"error": "scene_id required"}, 400)
            if new_sprites is None and new_layers is None and new_cycles is None:
                return self._send_json({"error": "sprites, image_layers or cycles required"}, 400)
            if not self._SAFE_ID_RE.match(scene_id):
                return self._send_json({"error": "invalid scene_id format"}, 400)
            try:
                spec = fetch_scene_spec(scene_id, SERVICE_KEY)
            except Exception as e:
                return self._send_json({"error": f"spec fetch: {e}"}, 502)
            bumped_layers = []
            if isinstance(new_sprites, list):
                spec["sprites"] = new_sprites
            if isinstance(new_layers, list):
                bumped_layers = bump_layers_with_url_changes(spec, new_layers)
                spec["image_layers"] = new_layers
            # Frame cycles — animation sequence order (e.g. sunburst spin).
            # The order/windows come pre-computed from the editor.
            if isinstance(new_cycles, list):
                spec["cycles"] = new_cycles
            try:
                put_scene_spec(scene_id, spec, SERVICE_KEY)
            except Exception as e:
                return self._send_json({"error": f"spec save: {e}"}, 502)
            fcm_ok = False
            try:
                fcm_ok = bool(_fcm_push_catalog_invalidate("wallpapers"))
            except Exception:
                pass
            return self._send_json({
                "ok": True,
                "scene_id": scene_id,
                "sprites_updated": len(spec.get("sprites") or []),
                "layers_updated": len(spec.get("image_layers") or []),
                "layers_revision_bumped": bumped_layers,
                "fcm": fcm_ok,
            })

        # Import image from connected Android device into a canvas_scene.
        # POST /api/device-import-image
        # body: {device_path, scene_id, action, layer_key?, new_layer_key?, z?}
        if path == "/api/device-import-image":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)
            scene_id = payload.get("scene_id")
            device_path = payload.get("device_path")
            action = payload.get("action", "replace_layer")
            if not scene_id or not device_path:
                return self._send_json({"error": "scene_id + device_path required"}, 400)
            if not self._SAFE_ID_RE.match(scene_id):
                return self._send_json({"error": "invalid scene_id"}, 400)
            if action not in ("replace_layer", "add_layer", "background"):
                return self._send_json({"error": "invalid action"}, 400)
            try:
                local = pull_device_image(
                    device_path, serial=payload.get("serial"),
                )
                summary = import_image_to_scene(
                    scene_id,
                    local,
                    action,
                    layer_key=payload.get("layer_key"),
                    new_layer_key=payload.get("new_layer_key"),
                    z=int(payload.get("z") or 1),
                    service_key=SERVICE_KEY,
                )
            except Exception as e:
                return self._send_json({"error": str(e)}, 502)
            fcm_ok = False
            try:
                fcm_ok = bool(_fcm_push_catalog_invalidate("wallpapers"))
            except Exception:
                pass
            return self._send_json({"ok": True, **summary, "fcm": fcm_ok})

        # Import image from PC upload (multipart) into a canvas_scene.
        if path == "/api/import-scene-image":
            return self._handle_import_scene_image_multipart()

        # Import sprite ZIP pack from connected Android device.
        if path == "/api/device-import-sprite":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)
            scene_id = payload.get("scene_id")
            device_path = payload.get("device_path")
            action = payload.get("action", "add_sprite")
            if not scene_id or not device_path:
                return self._send_json({"error": "scene_id + device_path required"}, 400)
            if not self._SAFE_ID_RE.match(scene_id):
                return self._send_json({"error": "invalid scene_id"}, 400)
            if action not in ("replace_sprite", "add_sprite"):
                return self._send_json({"error": "invalid action"}, 400)
            try:
                local = pull_device_image(device_path, serial=payload.get("serial"))
                summary = import_sprite_pack_to_scene(
                    scene_id,
                    local,
                    action,
                    manifest_key=payload.get("manifest_key"),
                    sprite_name=payload.get("sprite_name"),
                    frame_skip=float(payload.get("frame_skip") or 2.0),
                    service_key=SERVICE_KEY,
                )
            except Exception as e:
                return self._send_json({"error": str(e)}, 502)
            fcm_ok = False
            try:
                fcm_ok = bool(_fcm_push_catalog_invalidate("wallpapers"))
            except Exception:
                pass
            return self._send_json({"ok": True, **summary, "fcm": fcm_ok})

        # Import sprite ZIP pack from PC (multipart).
        if path == "/api/import-sprite-pack":
            return self._handle_import_sprite_pack_multipart()

        # Replace one canvas_scene image_layer bitmap in-place + bump revision + FCM.
        # POST /api/replace-scene-layer
        # body: {scene_id, layer_key, file_path}  (file_path = local path on this PC)
        if path == "/api/replace-scene-layer":
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length > 0 else b"{}"
            try:
                payload = json.loads(body.decode("utf-8"))
            except Exception as e:
                return self._send_json({"error": f"bad JSON: {e}"}, 400)
            scene_id = payload.get("scene_id")
            layer_key = payload.get("layer_key")
            file_path = payload.get("file_path")
            if not scene_id or not layer_key or not file_path:
                return self._send_json(
                    {"error": "scene_id, layer_key, file_path required"}, 400)
            if not self._SAFE_ID_RE.match(scene_id):
                return self._send_json({"error": "invalid scene_id format"}, 400)
            local = Path(str(file_path))
            if not local.is_file():
                return self._send_json({"error": f"file not found: {local}"}, 400)
            try:
                summary = replace_scene_layer_asset(
                    scene_id,
                    layer_key,
                    local,
                    service_key=SERVICE_KEY,
                )
            except Exception as e:
                return self._send_json({"error": str(e)}, 502)
            fcm_ok = False
            try:
                fcm_ok = bool(_fcm_push_catalog_invalidate("wallpapers"))
            except Exception:
                pass
            return self._send_json({
                "ok": True,
                **summary,
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

    scene_coords = DASHBOARD_DIR / "scene_coords.js"
    if not scene_coords.exists():
        print(f"WARNING: scene_coords.js missing at {scene_coords}")
        print("         The sprite editor will fail to load (ES module 404).")
    else:
        print(f"  scene_coords: {scene_coords}")

    print(f"Pixora Admin Dashboard")
    print(f"  Serving:    http://127.0.0.1:{PORT}/")
    print(f"  Dashboard:  {DASHBOARD_HTML}")
    print(f"  Supabase:   {SUPABASE_REST}")
    print(f"  Press Ctrl+C to stop\n")
    Timer(0.6, open_browser).start()
    class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
        """Handle requests in separate threads so the sprite editor (which loads
        multiple assets + does API calls) doesn't block itself."""
        pass

    server = ThreadedHTTPServer(("127.0.0.1", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        server.server_close()


if __name__ == "__main__":
    main()
