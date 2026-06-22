"""Pack Jake (Adventure Time) — Day Cycle + Pano + Static extra.

  · Day Cycle: jake_adventure_dia_completo (4 momentos)
        morning   = jake_enlamanana
        afternoon = jake_mediodia
        evening   = jake_tarde
        night     = jake_de_noche
  · Panoramic: pano_jake_colinas (16:9, Jake en colinas felices)
  · Static:    jake_mediodia_audifonos (el mediodía duplicado como static
               independiente, Eduardo lo pidió específicamente)
"""
import json, re, shutil, sys, urllib.request
from pathlib import Path
from PIL import Image
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
CATALOG = "day_cycle_catalog.json"
DL = Path(r"C:/Users/lalo/Downloads")
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/jake_adventure")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_jake")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)
SK = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
               Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")).group(1)

# ------------------------------ DAY CYCLE -------------------------------
DAY_CYCLE = {
    "id": "daycycle_jake_adventure",
    "name": "Jake · Día Completo",
    "description": "Jake el perro disfrutando las colinas Adventure Time en sus cuatro horarios — amanecer suave, mediodía con audífonos, atardecer dorado y noche estrellada con luna.",
    "glow": "#FACC15",
    "prefix": "jake_adventure",
    "files": {
        "dia":   "jake_enlamanana.jpg",
        "tarde2": "jake_mediodia_usartambienparaestatica.jpg",  # afternoon
        "tarde": "jake_tarde.jpg",
        "noche": "jake_de_noche.jpg",
    },
}

# ------------------------------ PANO + STATIC ----------------------------
ASSETS = [
    {"id": "pano_jake_colinas",
     "src": "jake_panoramica.jpg",
     "name": "Jake · Colinas Adventure",
     "description": "Jake feliz sobre las colinas Adventure Time bajo el sol de la mañana, estilo cartoon clásico.",
     "kind": "panoramic", "cat": "PANORAMIC", "glow": "#FACC15",
     "tags": ["jake", "adventure_time", "perro", "colinas", "cartoon", "panoramico", "anime", "amarillo"]},
    {"id": "jake_mediodia_audifonos",
     "src": "jake_mediodia_usartambienparaestatica.jpg",
     "name": "Jake · Audífonos al Mediodía",
     "description": "Jake con audífonos disfrutando música al mediodía sobre colinas verdes — momento chill total.",
     "kind": "static", "cat": "ANIME", "glow": "#FACC15",
     "tags": ["jake", "adventure_time", "perro", "audifonos", "cartoon", "anime", "chill", "musica"]},
]


def put(remote, body, ct="image/webp"):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}",
        data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"    PUT {remote} -> {r.status} ({len(body):,} B)")


def encode(src, dst, quality=90):
    img = Image.open(src).convert("RGB")
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes(), img


def encode_preview(src, dst, max_side, quality=85):
    img = Image.open(src).convert("RGB")
    img.thumbnail((max_side, max_side * 2), Image.LANCZOS)
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes()


def get_catalog():
    url = f"{PROJECT}/storage/v1/object/public/{BUCKET}/{CATALOG}"
    try:
        return json.loads(urllib.request.urlopen(url, timeout=15).read())
    except Exception:
        return {"themes": []}


def put_catalog(data):
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{BUCKET}/{CATALOG}",
        data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"    PUT {CATALOG} -> {r.status}")


print("=" * 60); print("Pack Jake Adventure Time"); print("=" * 60)

# 1) DAY CYCLE
print(f"\n[DAY CYCLE] {DAY_CYCLE['name']}")
remote_map = {}
for moment, fname in DAY_CYCLE["files"].items():
    src = DL / fname
    shutil.copy2(src, BACKUP / fname)
    remote = f"{DAY_CYCLE['prefix']}_{moment}.webp"
    body, _ = encode(src, WORK / remote)
    put(remote, body)
    remote_map[moment] = remote
prev_remote = f"{DAY_CYCLE['prefix']}_preview.webp"
prev_body = encode_preview(DL / DAY_CYCLE["files"]["dia"], WORK / prev_remote, 540)
put(prev_remote, prev_body)

cat = get_catalog()
themes = cat.get("themes", [])
new_theme = {
    "id": DAY_CYCLE["id"],
    "name": DAY_CYCLE["name"],
    "description": DAY_CYCLE["description"],
    "previewImage": prev_remote,
    "morningImage": remote_map["dia"],
    "afternoonImage": remote_map["tarde2"],
    "eveningImage": remote_map["tarde"],
    "nightImage": remote_map["noche"],
    "glowColor": DAY_CYCLE["glow"],
}
idx = next((i for i, t in enumerate(themes) if t.get("id") == DAY_CYCLE["id"]), -1)
if idx >= 0:
    themes[idx] = new_theme; print(f"    catalog: replace at {idx}")
else:
    themes.append(new_theme); print(f"    catalog: append (total {len(themes)})")
cat["themes"] = themes
put_catalog(cat)

# 2) PANO + STATIC
conn = connect(); cur = conn.cursor()
for w in ASSETS:
    src = DL / w["src"]
    print(f"\n[{w['kind'].upper()}] {w['id']}  {w['name']}")
    shutil.copy2(src, BACKUP / w["src"])
    full_remote = f"{w['id']}.webp"
    prev_remote = f"{w['id']}_preview.webp"
    full_body, img = encode(src, WORK / full_remote)
    max_side = 1080 if w["kind"] == "panoramic" else 540
    q = 82 if w["kind"] == "panoramic" else 85
    prev_body = encode_preview(src, WORK / prev_remote, max_side, q)
    put(full_remote, full_body)
    put(prev_remote, prev_body)
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    sort = cur.fetchone()[0]
    cur.execute(f"""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name,
            media_width, media_height
        ) VALUES (
            %s, %s, %s, '{w["kind"]}'::wallpaper_type,
            '{w["cat"]}'::wallpaper_category, %s,
            %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s,
            false, 0, true, true, 'Pixora Studio', %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description,
            tags=EXCLUDED.tags, image_path=EXCLUDED.image_path,
            preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color,
            media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
            updated_at=now()
        RETURNING id, sort_order;
    """, (w["id"], w["name"], w["description"], w["tags"],
          full_remote, prev_remote, len(full_body), len(prev_body),
          w["glow"], sort, img.width, img.height))
    rid, rsort = cur.fetchone()
    print(f"    postgres: {rid}  sort={rsort}")
conn.commit(); cur.close(); conn.close()

print("\n[FCM]")
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _fcm_push import send_catalog_invalidate
print(f"  day_cycle  -> {send_catalog_invalidate('day_cycle')}")
print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")
print("\n[OK] Pack Jake completo")
