"""
Reconcilia los STATIC wallpapers: detecta los que en JSON Storage tienen
nombre/categoría/etc. diferentes a los de Postgres y sincroniza usando
el endpoint /api/wallpaper-edit del admin server local.

Esto es one-shot: solo se corre cuando hay desfase porque los edits en
dashboard antes del bug fix (2026-05-13) solo escribían al JSON, no a
Postgres. Después de correr esto, todo queda en sync.

Para LIVE wallpapers no aplica — esos solo viven en Storage.
"""
from __future__ import annotations
import sys, re, json, urllib.request, urllib.parse, urllib.error
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
SERVICE_KEY = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", KEYS).group(1)
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
ADMIN_LOCAL = "http://127.0.0.1:5758"

# Campos que el dashboard puede editar — solo esos comparamos
EDITABLE = {
    "name": "name",
    "description": "description",
    "category": "category",
    "tags": "tags",
    "sortOrder": "sort_order",
    "badge": "badge",
    "glowColor": "glow_color",
}


def fetch_storage_catalog() -> dict:
    url = f"{PROJECT}/storage/v1/object/public/wallpaper-images/dynamic_catalog.json"
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.loads(r.read())


def fetch_all_pg_wallpapers() -> dict[str, dict]:
    """Returns {id: row} for every wallpaper in the Postgres table."""
    cols = "id,name,description,category,tags,sort_order,badge,glow_color"
    rows: list[dict] = []
    page_size = 1000
    offset = 0
    while True:
        url = f"{PROJECT}/rest/v1/wallpapers?select={cols}&order=id.asc&limit={page_size}&offset={offset}"
        req = urllib.request.Request(url)
        req.add_header("apikey", SERVICE_KEY)
        req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
        with urllib.request.urlopen(req, timeout=30) as r:
            batch = json.loads(r.read())
        rows.extend(batch)
        if len(batch) < page_size:
            break
        offset += page_size
    return {r["id"]: r for r in rows}


def fields_differ(json_item: dict, pg_row: dict) -> dict:
    """Returns dict of {json_field: new_value} for fields that differ."""
    diff = {}
    for json_key, pg_col in EDITABLE.items():
        new_val = json_item.get(json_key)
        old_val = pg_row.get(pg_col)
        # Normalize None vs empty string
        if new_val == "" and old_val is None:
            continue
        if new_val is None and old_val == "":
            continue
        # Tags: compare as sorted lists
        if json_key == "tags":
            if (new_val or []) != (old_val or []):
                diff[json_key] = new_val or []
            continue
        if new_val != old_val:
            diff[json_key] = new_val
    return diff


def send_edit(wid: str, diff: dict) -> tuple[bool, str]:
    body = json.dumps({"kind": "static", "id": wid, "fields": diff}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{ADMIN_LOCAL}/api/wallpaper-edit",
        data=body,
        method="POST",
        headers={"Content-Type": "application/json; charset=utf-8"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read())
        pg = data.get("postgres") or {}
        st = data.get("storage") or {}
        ok = (pg.get("status", 200) < 400) and st.get("ok", False)
        return (ok, "OK" if ok else json.dumps(data)[:200])
    except urllib.error.HTTPError as e:
        return (False, e.read().decode()[:200])
    except Exception as e:
        return (False, str(e))


def main():
    print("Fetching Storage catalog (dynamic_catalog.json)...")
    catalog = fetch_storage_catalog()
    storage_items = catalog.get("wallpapers", [])
    print(f"  {len(storage_items)} wallpapers in Storage\n")

    print("Fetching all rows from Postgres `wallpapers` table...")
    pg_by_id = fetch_all_pg_wallpapers()
    print(f"  {len(pg_by_id)} rows in Postgres\n")

    print("Comparing each wallpaper...\n")
    out_of_sync = []
    missing_in_pg = []
    for item in storage_items:
        wid = item.get("id")
        if not wid:
            continue
        pg = pg_by_id.get(wid)
        if not pg:
            missing_in_pg.append(wid)
            continue
        diff = fields_differ(item, pg)
        if diff:
            out_of_sync.append((wid, diff, pg))

    if missing_in_pg:
        print(f"WARN: {len(missing_in_pg)} ids en Storage pero NO en Postgres (no se sincronizan):")
        for wid in missing_in_pg[:5]:
            print(f"   - {wid}")
        if len(missing_in_pg) > 5:
            print(f"   ... y {len(missing_in_pg) - 5} mas")
        print()

    if not out_of_sync:
        print("Nada que sincronizar — todo esta en sync.")
        return

    print(f"{len(out_of_sync)} wallpapers fuera de sync:\n")
    for wid, diff, pg in out_of_sync:
        old_name = pg.get("name") or "?"
        new_name = diff.get("name", old_name)
        changed = list(diff.keys())
        print(f"  - {wid:50}  '{old_name[:30]}' -> '{new_name[:30]}'  fields: {changed}")
    print()

    print("Sincronizando...")
    ok_count = 0
    fail_count = 0
    for wid, diff, _pg in out_of_sync:
        ok, msg = send_edit(wid, diff)
        if ok:
            ok_count += 1
            print(f"  OK   {wid}")
        else:
            fail_count += 1
            print(f"  FAIL {wid}: {msg}")
    print(f"\nTerminado: {ok_count} sincronizados, {fail_count} fallaron")


if __name__ == "__main__":
    main()
