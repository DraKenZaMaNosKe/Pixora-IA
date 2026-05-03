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

        return self._send(404, "text/plain", b"not found")


def open_browser():
    webbrowser.open(f"http://localhost:{PORT}/")


def main():
    if not DASHBOARD_HTML.exists():
        print(f"FATAL: dashboard html missing at {DASHBOARD_HTML}")
        sys.exit(1)
    print(f"Pixora Admin Dashboard")
    print(f"  Serving:    http://localhost:{PORT}/")
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
