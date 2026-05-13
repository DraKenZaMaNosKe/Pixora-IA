"""
Reverse sync: Postgres `wallpapers` (lo que el app ve) → JSON Storage.

Hace que el JSON `dynamic_catalog.json` refleje exactamente lo que está en
Postgres, de modo que el dashboard quede consistente con la app. Útil cuando
hay desfase y no sabes qué edits ya llegaron y cuáles no — se elige a Postgres
como fuente de verdad y se sobrescribe el JSON.

SOLO STATIC. LIVE wallpapers no tocan Postgres así que no necesitan sync inverso.
"""
from __future__ import annotations
import sys, re, json, urllib.request
from pathlib import Path
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
SERVICE_KEY = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", KEYS).group(1)
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"

BUCKET = "wallpaper-images"
FILE = "dynamic_catalog.json"

# Postgres column → JSON key (inverse of EDITABLE map en el server)
PG_TO_JSON = {
    "name": "name",
    "description": "description",
    "category": "category",
    "tags": "tags",
    "sort_order": "sortOrder",
    "badge": "badge",
    "glow_color": "glowColor",
}


def fetch_all_pg_wallpapers() -> dict[str, dict]:
    cols = "id," + ",".join(PG_TO_JSON.keys())
    rows: list[dict] = []
    offset = 0
    while True:
        url = f"{PROJECT}/rest/v1/wallpapers?select={cols}&order=id.asc&limit=1000&offset={offset}"
        req = urllib.request.Request(url)
        req.add_header("apikey", SERVICE_KEY)
        req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
        with urllib.request.urlopen(req, timeout=30) as r:
            batch = json.loads(r.read())
        rows.extend(batch)
        if len(batch) < 1000:
            break
        offset += 1000
    return {r["id"]: r for r in rows}


def fetch_storage_catalog() -> dict:
    url = f"{PROJECT}/storage/v1/object/public/{BUCKET}/{FILE}"
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.loads(r.read())


def upload_catalog(catalog: dict) -> int:
    payload = json.dumps(catalog, indent=2, ensure_ascii=False).encode("utf-8")
    url = f"{PROJECT}/storage/v1/object/{BUCKET}/{FILE}"
    req = urllib.request.Request(url, data=payload, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.status


def main():
    print("Fetching Postgres `wallpapers` table...")
    pg_by_id = fetch_all_pg_wallpapers()
    print(f"  {len(pg_by_id)} rows in Postgres\n")

    print("Fetching Storage JSON catalog...")
    catalog = fetch_storage_catalog()
    items = catalog.get("wallpapers", [])
    print(f"  {len(items)} wallpapers in Storage\n")

    print("Computing diffs (Postgres -> Storage)...")
    changes = 0
    only_in_storage = []
    only_in_pg = []
    for item in items:
        wid = item.get("id")
        pg = pg_by_id.get(wid)
        if not pg:
            only_in_storage.append(wid)
            continue
        # Apply Postgres values into the JSON item
        item_changed = False
        for pg_col, json_key in PG_TO_JSON.items():
            new_val = pg.get(pg_col)
            old_val = item.get(json_key)
            # Normalize: tags list, badge None vs ""
            if pg_col == "tags":
                new_val = new_val or []
                old_val = old_val or []
            if new_val != old_val:
                item[json_key] = new_val
                item_changed = True
        if item_changed:
            changes += 1
    # Items in Postgres but not in Storage
    storage_ids = {i.get("id") for i in items}
    for wid in pg_by_id:
        if wid not in storage_ids:
            only_in_pg.append(wid)

    print(f"  {changes} entries actualizados en el JSON local")
    if only_in_storage:
        print(f"  WARN {len(only_in_storage)} ids en Storage pero NO en Postgres (se dejan como estan):")
        for wid in only_in_storage[:5]:
            print(f"    - {wid}")
        if len(only_in_storage) > 5:
            print(f"    ... y {len(only_in_storage) - 5} mas")
    if only_in_pg:
        print(f"  WARN {len(only_in_pg)} ids en Postgres pero NO en Storage (no se agregan):")
        for wid in only_in_pg[:5]:
            print(f"    - {wid}")
    print()

    if changes == 0:
        print("Storage ya esta sincronizado con Postgres — nada que hacer.")
        return

    catalog["lastUpdated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    print(f"Subiendo catalogo actualizado a Storage...")
    status = upload_catalog(catalog)
    print(f"  PUT status: {status}")
    print(f"\nListo: {changes} entradas sincronizadas Postgres -> Storage")


if __name__ == "__main__":
    main()
