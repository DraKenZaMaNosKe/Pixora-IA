"""Reorganiza el catálogo de tonos: saca las voces de llamada (source voces_*)
de anime_tv_pack y modern_futuristic_pack y las junta en un pack nuevo
'voces_llamada_pack', que queda DESTACADO (primero en la lista).

No re-sube audio ni imágenes (solo mueve entradas en el JSON) → instantáneo.
Idempotente: si ya existe el pack, re-consolida sin duplicar.
"""
import json, re, urllib.request
from datetime import datetime, timezone
from pathlib import Path

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
CATALOG = "ringtones_catalog.json"
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]

NEW_ID = "voces_llamada_pack"
NEW_PACK_META = {
    "id": NEW_ID,
    "name": "Voces de Llamada",
    "description": "Voces originales, anime y galácticas",
    "previewImage": "",
    "glowColor": "#FF2E9A",
    "category": "VOCES",
}

def now_iso(): return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def put(remote, body, ct):
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("apikey", SK)
    req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "no-cache, max-age=0")
    with urllib.request.urlopen(req, timeout=120) as r: return r.status

def is_voz(t):
    return str(t.get("source", "")).startswith("voces") or str(t.get("source", "")).startswith("romance")

cat = json.loads(urllib.request.urlopen(
    f"{PROJECT}/storage/v1/object/public/{BUCKET}/{CATALOG}?nc=1", timeout=20).read())
packs = cat.get("packs", [])

# 1) recolectar todas las voces (de cualquier pack, incluyendo uno ya-existente) y quitarlas
voces = []
seen = set()
for p in packs:
    keep = []
    for t in p.get("tones", []):
        if is_voz(t) or p.get("id") == NEW_ID:
            if t["id"] not in seen:
                seen.add(t["id"]); voces.append(t)
        else:
            keep.append(t)
    p["tones"] = keep

# orden lógico dentro del pack: anime/mucamas primero, luego sci-fi, luego romance
def rank(t):
    s = t.get("source", "")
    if s.startswith("romance"): return 2
    # anime = las que NO son alien/robot/androide/interdimensional/mente/protocolo/reina/traductor/asistente
    scifi = any(k in t["id"] for k in
        ("alien","robot","androide","interdimensional","mente_colmena","protocolo","reina","traductor","asistente"))
    return 1 if scifi else 0
voces.sort(key=rank)

# 2) construir/actualizar el pack nuevo
new_pack = next((p for p in packs if p.get("id") == NEW_ID), None)
if new_pack is None:
    new_pack = dict(NEW_PACK_META); new_pack["tones"] = []
    packs = [p for p in packs if p.get("id") != NEW_ID]
else:
    packs = [p for p in packs if p.get("id") != NEW_ID]
    new_pack.update(NEW_PACK_META)
new_pack["tones"] = voces

# 3) dejar el pack DESTACADO al frente, y quitar packs que quedaron vacíos
packs = [p for p in packs if p.get("tones")]
cat["packs"] = [new_pack] + packs
cat["lastUpdated"] = now_iso()

# 4) subir
put(CATALOG, json.dumps(cat, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")

print(f"[OK] '{new_pack['name']}' quedó con {len(voces)} voces, destacado al frente.")
print("Distribución final:")
for p in cat["packs"]:
    print(f"   {p['id']:26} {len(p.get('tones',[])):>3} tonos   ({p.get('category')})")

# 5) FCM
try:
    import sys
    sys.path.insert(0, str(Path(__file__).parent.parent / "wallpapers"))
    from _fcm_push import send_catalog_invalidate
    print("\nFCM ringtones ->", send_catalog_invalidate("ringtones"))
except Exception as e:
    print("FCM fallo (no crítico):", e)
