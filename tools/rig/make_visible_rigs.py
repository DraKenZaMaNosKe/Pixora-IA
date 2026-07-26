"""Hace VISIBLES los 3 wallpapers rig: published:true + quita hidden_in en el
spec (wallpaper-scenes) y en el catalog_index. FCM wallpapers al final para que
los devices bajen el catálogo nuevo y aparezcan.
"""
import json, re, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
PUB = f"{PROJECT}/storage/v1/object/public"
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]
SIDS = ["heroina_candy_mecha_rig_v1", "astronauta_nebula_flota", "delfines_santuario_luz"]

def now_iso(): return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def put(bucket, remote, body, ct):
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}", data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("apikey", SK)
    req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=60) as r: return r.status

def getj(bucket, remote):
    return json.loads(urllib.request.urlopen(f"{PUB}/{bucket}/{remote}?nc={int(datetime.now().timestamp())}", timeout=25).read())

# 1) specs: published true + hidden_in []
for sid in SIDS:
    spec = getj("wallpaper-scenes", f"{sid}.json")
    spec["published"] = True
    spec["hidden_in"] = []
    put("wallpaper-scenes", f"{sid}.json", json.dumps(spec, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")
    print(f"  ✓ spec {sid} -> published:true, visible")

# 2) catalog_index: cada entry published true + hidden_in []
idx = getj("wallpaper-images", "catalog_index.json")
for it in idx["items"]:
    if it.get("id") in SIDS:
        it["published"] = True
        it["hidden_in"] = []
idx["version"] = int(idx.get("version", 0)) + 1
idx["updated_at"] = now_iso()
put("wallpaper-images", "catalog_index.json", json.dumps(idx, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"  ✓ catalog_index v{idx['version']} (3 entradas visibles)")

# 3) FCM
try:
    sys.path.insert(0, str(Path(__file__).parent.parent / "wallpapers"))
    from _fcm_push import send_catalog_invalidate
    print("  FCM wallpapers ->", send_catalog_invalidate("wallpapers"))
except Exception as e:
    print("  FCM fallo (no crítico):", e)

print("\n[OK] Los 3 wallpapers rig están VISIBLES para los usuarios.")
