"""Flip the 7 batch7b canvas_scene wallpapers to VISIBLE (published=true).
Updates Postgres + catalog_index.json. FCM invalidate is a separate step.
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET = "wallpaper-images"
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]

IDS = [
    "jack_colina_calabazas_parallax",
    "jack_sally_halloween_town_parallax",
    "johnny_bravo_guitarra_parallax",
    "motoratones_villanos_invasion_parallax",
    "pez_conserje_fondo_bikini_parallax",
    "sedusa_noir_townsville_parallax",
    "vaca_pollo_granja_parallax",
]


def get_json(bucket, remote):
    import time
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}?nc={time.time()}"
    req = urllib.request.Request(url); req.add_header("Cache-Control", "no-cache")
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def put_json(bucket, remote, data):
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("apikey", SK)
    req.add_header("Content-Type", "application/json"); req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "no-cache, max-age=0")
    with urllib.request.urlopen(req, timeout=180) as r:
        print(f"    PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


# --- Postgres ---
from apply_migration import connect
conn = connect(); conn.set_client_encoding("UTF8")
cur = conn.cursor()
for sid in IDS:
    cur.execute("UPDATE wallpapers SET published = true WHERE id = %s RETURNING id, published;", (sid,))
    row = cur.fetchone()
    print(f"  PG  {sid:42} -> published={row[1]}" if row else f"  !! no row {sid}")
conn.commit(); cur.close(); conn.close()

# --- catalog_index ---
print("\nUpdating catalog_index...")
cat = get_json(IMG_BUCKET, "catalog_index.json")
cat["version"] = (cat.get("version", 0) or 0) + 1
touched = 0
for it in cat.get("items", []):
    if it.get("id") in IDS:
        it["published"] = True; touched += 1
put_json(IMG_BUCKET, "catalog_index.json", cat)
print(f"  catalog v{cat['version']} — {touched}/{len(IDS)} entries set published=true")
print("\nDONE. Ahora corre el FCM: python _fcm_push.py catalog wallpapers")
