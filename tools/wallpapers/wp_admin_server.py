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
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from threading import Timer

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
    "day_cycle": ("wallpaper-images", "day_cycle_catalog.json",      "scenes"),
    "ringtones": ("wallpaper-images", "ringtones_catalog.json",      "ringtones"),
}


# ─── Get service key once at startup ──────────────────────────────────────────
def get_service_key() -> str:
    content = KEYS_PATH.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", content)
    if not m:
        raise SystemExit("Service Role Key not found in KEYS_LOCAL.md")
    return m.group(1)


SERVICE_KEY = get_service_key()


# ─── HTTP handler ─────────────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # quieter logs
        if "/api/" in args[0] if args else False:
            return
        sys.stderr.write(f"  {self.address_string()} - {fmt % args}\n")

    def _send(self, status: int, ctype: str, body: bytes):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, obj, status: int = 200):
        body = json.dumps(obj).encode("utf-8")
        self._send(status, "application/json; charset=utf-8", body)

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
            limit = int(query.get("limit", ["50"])[0])
            order = query.get("order", ["views.desc"])[0]
            data, status = self._proxy(f"admin_wallpaper_breakdown?order={order}&limit={limit}")
            return self._send_json(data, status)

        if path == "/api/recent-events":
            limit = int(query.get("limit", ["50"])[0])
            data, status = self._proxy(
                f"wallpaper_events?select=id,ts,device_id,user_id,wallpaper_id,event_type,app_version&order=ts.desc&limit={limit}"
            )
            return self._send_json(data, status)

        if path == "/api/wallpaper":
            wid = query.get("id", [""])[0]
            data, status = self._proxy(
                f"admin_wallpaper_breakdown?id=eq.{urllib.parse.quote(wid)}"
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
                return self._send_json({
                    "ok": True,
                    "bucket": bucket,
                    "file": fname,
                    "count": len(parsed.get(items_key, [])),
                    "storage_response": resp[:200],
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
