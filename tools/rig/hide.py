"""Oculta uno o mas canvas_scene: published:false + hidden_in en todas las
secciones, en el spec (wallpaper-scenes) y en el catalog_index. Sin FCM
(corre make_visible.py despues para el refresco).

Uso: python hide.py <SID> [<SID2> ...]
"""
import json, re, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
PUB = f"{PROJECT}/storage/v1/object/public"
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]
SIDS = sys.argv[1:]
HIDE = ["parallax_tab", "cultura", "daily", "events", "arte", "anime"]
if not SIDS:
    print("uso: python hide.py <SID> [<SID2> ...]"); sys.exit(1)

def now_iso(): return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def put(bucket, remote, body, ct):
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}", data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("apikey", SK)
    req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=60) as r: return r.status

def getj(bucket, remote):
    return json.loads(urllib.request.urlopen(f"{PUB}/{bucket}/{remote}?nc={int(datetime.now().timestamp())}", timeout=25).read())

for sid in SIDS:
    try:
        spec = getj("wallpaper-scenes", f"{sid}.json")
        spec["published"] = False
        spec["hidden_in"] = HIDE
        put("wallpaper-scenes", f"{sid}.json", json.dumps(spec, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")
        print(f"  ✓ spec {sid} -> OCULTO")
    except Exception as e:
        print(f"  · spec {sid}: {e}")

idx = getj("wallpaper-images", "catalog_index.json")
touched = 0
for it in idx["items"]:
    if it.get("id") in SIDS:
        it["published"] = False
        it["hidden_in"] = HIDE
        touched += 1
idx["version"] = int(idx.get("version", 0)) + 1
idx["updated_at"] = now_iso()
put("wallpaper-images", "catalog_index.json", json.dumps(idx, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"  ✓ catalog_index v{idx['version']} ({touched} entradas ocultas)")
print(f"\n[OK] {len(SIDS)} escena(s) OCULTA(S).")
