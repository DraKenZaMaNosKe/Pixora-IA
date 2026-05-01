"""
Pixora Wallpapers — Admin CLI (runs LOCALLY on your PC, never inside the app).

Reads admin views/RPCs from Supabase using the service-role key.
The service-role key lives in KEYS_LOCAL.md (gitignored).

Usage:
    python tools/wallpapers/wp_admin.py stats
    python tools/wallpapers/wp_admin.py daily [--days 30]
    python tools/wallpapers/wp_admin.py top-users [--limit 20]
    python tools/wallpapers/wp_admin.py top-wallpapers [--limit 20]
    python tools/wallpapers/wp_admin.py user-history <identity> [--limit 50]
    python tools/wallpapers/wp_admin.py wallpaper <wallpaper_id>
    python tools/wallpapers/wp_admin.py dashboard            # generates HTML in tools/wallpapers/admin_dashboard.html and opens it
    python tools/wallpapers/wp_admin.py search <text>        # search wallpapers by name/tag
    python tools/wallpapers/wp_admin.py recompute-trending
"""
from __future__ import annotations
import argparse, json, os, re, sys, urllib.request, urllib.error, urllib.parse, webbrowser
from datetime import datetime
from pathlib import Path

# Force UTF-8 stdout on Windows so box-drawing chars don't crash cp1252
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

KEYS_PATH = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
PROJECT_REF = "vzuwvsmlyigjtsearxym"
REST = f"https://{PROJECT_REF}.supabase.co/rest/v1"
RPC = f"{REST}/rpc"

DASHBOARD_OUT = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/admin_dashboard.html")


# ─── auth ─────────────────────────────────────────────────────────────────────
def get_service_key() -> str:
    content = KEYS_PATH.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", content)
    if not m:
        raise SystemExit("Service Role Key not found in KEYS_LOCAL.md")
    return m.group(1)


def headers(key: str) -> dict[str, str]:
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }


# ─── HTTP helpers ─────────────────────────────────────────────────────────────
def get(url: str, key: str) -> list | dict:
    req = urllib.request.Request(url, method="GET")
    for k, v in headers(key).items(): req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def rpc(name: str, params: dict, key: str) -> list | dict:
    req = urllib.request.Request(f"{RPC}/{name}", data=json.dumps(params).encode(),
                                  method="POST")
    for k, v in headers(key).items(): req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode("utf-8")
            return json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        print(f"RPC {name} HTTP {e.code}: {e.read().decode()[:300]}")
        raise


# ─── pretty printing ──────────────────────────────────────────────────────────
def table(rows: list[dict], cols: list[str], max_widths: dict[str, int] | None = None):
    """Print a simple aligned text table."""
    if not rows:
        print("(no rows)")
        return
    max_widths = max_widths or {}

    def cell(r: dict, c: str) -> str:
        v = r.get(c)
        s = "" if v is None else str(v)
        return s[: max_widths.get(c, 60)]

    widths = {}
    for c in cols:
        widths[c] = max(len(c), max((len(cell(r, c)) for r in rows), default=0))

    print(" | ".join(c.upper().ljust(widths[c]) for c in cols))
    print("-+-".join("-" * widths[c] for c in cols))
    for r in rows:
        print(" | ".join(cell(r, c).ljust(widths[c]) for c in cols))


def fmt_ts(s: str | None) -> str:
    if not s: return "-"
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return s[:16]


# ─── commands ─────────────────────────────────────────────────────────────────
def cmd_stats(args, key):
    data = rpc("wp_stats", {}, key)
    s = data[0] if isinstance(data, list) else data
    print(f"┌─ Pixora Catalog ────────────────────────────────")
    print(f"│ Wallpapers (published / unpublished / total): "
          f"{s['published']} / {s['unpublished']} / {s['total']}")
    print(f"│ Total views:    {s['total_views']:>12,}")
    print(f"│ Total installs: {s['total_installs']:>12,}")
    print(f"│ By category:")
    for cat, n in sorted((s.get("by_category") or {}).items(), key=lambda x: -x[1]):
        print(f"│   {cat:<12} {n:>4}")
    print(f"└──────────────────────────────────────────────────")
    print("\nTop 10 most viewed:")
    table(s.get("most_viewed") or [], ["id", "name", "views"], max_widths={"name": 38})


def cmd_daily(args, key):
    rows = get(f"{REST}/admin_daily_activity?limit={args.days}", key)
    table(rows, ["day", "total_events", "unique_devices", "views", "installs", "shares"])


def cmd_top_users(args, key):
    rows = get(f"{REST}/admin_top_users_30d?limit={args.limit}", key)
    print(f"Top {len(rows)} most active identities (30 days):")
    table(rows, ["identity_type", "identity", "total_events", "views", "installs",
                 "favorites", "unique_wallpapers", "active_days", "first_seen", "last_seen"],
          max_widths={"identity": 30, "first_seen": 16, "last_seen": 16})


def cmd_top_wallpapers(args, key):
    rows = get(f"{REST}/admin_wallpaper_breakdown?order=views.desc&limit={args.limit}", key)
    table(rows, ["id", "name", "category", "views", "installs", "shares",
                 "unique_devices", "install_rate_pct"],
          max_widths={"id": 36, "name": 38})


def cmd_user_history(args, key):
    data = rpc("admin_user_history",
               {"p_identity": args.identity, "p_limit": args.limit}, key)
    if not data:
        print(f"No events for identity '{args.identity}'")
        return
    for r in data:
        r["ts"] = fmt_ts(r.get("ts"))
    table(data, ["ts", "event_type", "wallpaper_id", "wallpaper_name", "app_version"],
          max_widths={"wallpaper_id": 30, "wallpaper_name": 30})


def cmd_wallpaper(args, key):
    rows = get(f"{REST}/admin_wallpaper_breakdown?id=eq.{urllib.parse.quote(args.wallpaper_id)}", key)
    if not rows:
        print(f"Wallpaper '{args.wallpaper_id}' not found.")
        return
    w = rows[0]
    print(f"┌─ {w['name']} ({w['id']})")
    print(f"│ Category:       {w['category']}")
    print(f"│ Featured:       {w.get('featured')}")
    print(f"│ Views:          {w['views']:,}")
    print(f"│ Installs:       {w['installs']:,}")
    print(f"│ Shares:         {w['shares']:,}")
    print(f"│ Unique devices: {w['unique_devices']:,}")
    print(f"│ Install rate:   {w['install_rate_pct']}%")
    print(f"│ Trending score: {w['trending_score']:.4f}")
    print(f"└──────────────────────────────────────")


def cmd_search(args, key):
    rows = rpc("wp_search", {"p_query": args.query, "p_limit": 30, "p_offset": 0,
                              "p_category": None}, key)
    if not rows:
        print(f"No matches for '{args.query}'")
        return
    table(rows, ["id", "name", "category", "trending_score"],
          max_widths={"id": 36, "name": 40})


def cmd_recompute_trending(args, key):
    n = rpc("wp_recompute_trending", {}, key)
    print(f"Recomputed trending_score for {n} wallpapers.")


def cmd_dashboard(args, key):
    print("Building dashboard…")
    stats   = rpc("wp_stats", {}, key)[0]
    daily   = get(f"{REST}/admin_daily_activity?limit=30", key)
    topu    = get(f"{REST}/admin_top_users_30d?limit=15", key)
    topw    = get(f"{REST}/admin_wallpaper_breakdown?order=views.desc&limit=20", key)

    html = build_dashboard_html(stats, daily, topu, topw)
    DASHBOARD_OUT.write_text(html, encoding="utf-8")
    print(f"Wrote {DASHBOARD_OUT}")
    if not args.no_open:
        webbrowser.open(DASHBOARD_OUT.as_uri())


def build_dashboard_html(stats: dict, daily: list, topu: list, topw: list) -> str:
    by_cat = stats.get("by_category") or {}
    most_viewed = stats.get("most_viewed") or []

    def jrow(r, cols):
        return "<tr>" + "".join(f"<td>{r.get(c) if r.get(c) is not None else ''}</td>" for c in cols) + "</tr>"

    daily_rows = "\n".join(jrow(r, ["day","total_events","unique_devices","views","installs","shares"]) for r in daily)
    topu_rows = "\n".join(jrow(r, ["identity_type","identity","total_events","views","installs","favorites","active_days","last_seen"]) for r in topu)
    topw_rows = "\n".join(jrow(r, ["id","name","category","views","installs","unique_devices","install_rate_pct"]) for r in topw)
    cat_rows = "\n".join(f"<tr><td>{c}</td><td style='text-align:right'>{n}</td></tr>" for c, n in sorted(by_cat.items(), key=lambda x: -x[1]))
    most_rows = "\n".join(jrow(r, ["id","name","views"]) for r in most_viewed)

    chart_labels = json.dumps([r["day"] for r in daily][::-1])
    chart_views = json.dumps([r["views"] for r in daily][::-1])
    chart_installs = json.dumps([r["installs"] for r in daily][::-1])

    return f"""<!doctype html>
<html lang="es"><head>
<meta charset="utf-8">
<title>Pixora — Admin Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<style>
  :root {{ color-scheme: dark; }}
  body {{ font-family: ui-monospace, 'Cascadia Code', monospace; background:#0b0b14; color:#e7e7f0; margin:0; padding:32px; }}
  h1 {{ font-family: 'Fraunces', serif; font-style: italic; font-size: 42px; margin: 0 0 6px; color:#fff; }}
  h1 small {{ font-style: normal; font-size:13px; color:#7a7a8c; font-family: ui-monospace, monospace; }}
  h2 {{ font-size:14px; letter-spacing:.2em; color:#aaa; text-transform:uppercase; margin:32px 0 12px; }}
  .grid {{ display:grid; grid-template-columns: repeat(4, 1fr); gap:16px; margin-bottom:24px; }}
  .card {{ background:#161624; border-radius:12px; padding:20px; border:1px solid #1f1f2e; }}
  .card .label {{ font-size:11px; color:#7a7a8c; text-transform:uppercase; letter-spacing:.15em; }}
  .card .value {{ font-size:28px; font-weight:700; margin-top:6px; }}
  table {{ width:100%; border-collapse:collapse; background:#161624; border-radius:8px; overflow:hidden; }}
  th, td {{ padding:8px 12px; text-align:left; border-bottom:1px solid #1f1f2e; font-size:13px; }}
  th {{ background:#1f1f2e; color:#aaa; text-transform:uppercase; font-size:11px; letter-spacing:.1em; }}
  .panel {{ background:#161624; border-radius:12px; padding:20px; border:1px solid #1f1f2e; }}
  .row2 {{ display:grid; grid-template-columns: 2fr 1fr; gap:16px; }}
  canvas {{ max-height: 280px !important; }}
  footer {{ margin-top:40px; color:#555; font-size:11px; }}
</style>
</head><body>
<h1>Pixora · Admin Dashboard <small>generado {datetime.now().strftime('%Y-%m-%d %H:%M')}</small></h1>

<div class="grid">
  <div class="card"><div class="label">Wallpapers publicados</div><div class="value">{stats['published']}</div></div>
  <div class="card"><div class="label">Total de vistas</div><div class="value">{stats['total_views']:,}</div></div>
  <div class="card"><div class="label">Total de installs</div><div class="value">{stats['total_installs']:,}</div></div>
  <div class="card"><div class="label">Categorías activas</div><div class="value">{len(by_cat)}</div></div>
</div>

<h2>Actividad diaria · últimos {len(daily)} días</h2>
<div class="panel"><canvas id="chartDaily"></canvas></div>

<div class="row2" style="margin-top:24px;">
  <div>
    <h2>Wallpapers — top 20 por vistas</h2>
    <div class="panel" style="padding:0; overflow-x:auto;">
      <table><thead><tr><th>id</th><th>nombre</th><th>cat</th><th>vistas</th><th>installs</th><th>devices únicos</th><th>install %</th></tr></thead>
      <tbody>{topw_rows}</tbody></table>
    </div>
  </div>
  <div>
    <h2>Por categoría</h2>
    <div class="panel" style="padding:0;">
      <table><thead><tr><th>categoría</th><th style="text-align:right">total</th></tr></thead><tbody>{cat_rows}</tbody></table>
    </div>
    <h2>Top 10 más vistos</h2>
    <div class="panel" style="padding:0;">
      <table><thead><tr><th>id</th><th>nombre</th><th>vistas</th></tr></thead><tbody>{most_rows}</tbody></table>
    </div>
  </div>
</div>

<h2>Top usuarios · últimos 30 días</h2>
<div class="panel" style="padding:0; overflow-x:auto;">
  <table><thead><tr><th>tipo</th><th>identidad</th><th>eventos</th><th>vistas</th><th>installs</th><th>favs</th><th>días activos</th><th>última visita</th></tr></thead>
  <tbody>{topu_rows}</tbody></table>
</div>

<h2>Diario · raw</h2>
<div class="panel" style="padding:0; overflow-x:auto;">
  <table><thead><tr><th>día</th><th>eventos</th><th>devices únicos</th><th>vistas</th><th>installs</th><th>shares</th></tr></thead>
  <tbody>{daily_rows}</tbody></table>
</div>

<footer>Datos en vivo desde Supabase · run <code>python tools/wallpapers/wp_admin.py dashboard</code> para refrescar</footer>

<script>
new Chart(document.getElementById('chartDaily'), {{
  type: 'line',
  data: {{
    labels: {chart_labels},
    datasets: [
      {{ label: 'views', data: {chart_views}, borderColor:'#7c4dff', backgroundColor:'rgba(124,77,255,.15)', tension:.3, fill:true }},
      {{ label: 'installs', data: {chart_installs}, borderColor:'#00bcd4', backgroundColor:'rgba(0,188,212,.10)', tension:.3, fill:true }}
    ]
  }},
  options: {{ responsive:true, plugins:{{ legend:{{ labels:{{ color:'#aaa' }} }} }}, scales:{{ x:{{ ticks:{{ color:'#7a7a8c' }}, grid:{{ color:'#1f1f2e' }} }}, y:{{ ticks:{{ color:'#7a7a8c' }}, grid:{{ color:'#1f1f2e' }} }} }} }}
}});
</script>
</body></html>
"""


# ─── main ─────────────────────────────────────────────────────────────────────
def main() -> int:
    p = argparse.ArgumentParser()
    sp = p.add_subparsers(dest="cmd", required=True)
    sp.add_parser("stats")
    d = sp.add_parser("daily"); d.add_argument("--days", type=int, default=30)
    tu = sp.add_parser("top-users"); tu.add_argument("--limit", type=int, default=20)
    tw = sp.add_parser("top-wallpapers"); tw.add_argument("--limit", type=int, default=20)
    h = sp.add_parser("user-history"); h.add_argument("identity"); h.add_argument("--limit", type=int, default=50)
    w = sp.add_parser("wallpaper"); w.add_argument("wallpaper_id")
    s = sp.add_parser("search"); s.add_argument("query")
    sp.add_parser("recompute-trending")
    db = sp.add_parser("dashboard"); db.add_argument("--no-open", action="store_true")

    args = p.parse_args()
    key = get_service_key()

    cmd_map = {
        "stats": cmd_stats,
        "daily": cmd_daily,
        "top-users": cmd_top_users,
        "top-wallpapers": cmd_top_wallpapers,
        "user-history": cmd_user_history,
        "wallpaper": cmd_wallpaper,
        "search": cmd_search,
        "recompute-trending": cmd_recompute_trending,
        "dashboard": cmd_dashboard,
    }
    cmd_map[args.cmd](args, key)
    return 0


if __name__ == "__main__":
    sys.exit(main())
