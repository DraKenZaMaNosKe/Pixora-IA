"""Batch 2026-06-21-B:
   · 4 Day Cycle themes (Nave, Pacman, Starsheeptrooper, Egipto)
   · 1 static wallpaper (Gatito Naranjoso · Afuera)
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
DOWNLOADS = Path(r"C:/Users/lalo/Downloads")
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/2026_06_21_batch_b")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_batch_b")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)
SK = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
               Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")).group(1)

DAY_CYCLES = [
    {
        "theme_id": "daycycle_nave_interior",
        "name": "Nave · Vista desde Adentro",
        "description": "Vista del piloto desde la cabina de una nave interestelar — el cosmos cambia su luz a lo largo del día, mañana cálida, tarde dorada y noche entre estrellas.",
        "glow": "#5C7CFA",
        "files": {
            "dia": "nave_de_dia_vistadesdeadentro.jpg",
            "tarde": "nave_detarde_vistadesdeadentro.jpg",
            "noche": "nave_denochevistadesdedetnro.jpg",
        },
        "prefix": "nave_interior",
    },
    {
        "theme_id": "daycycle_pacman_vida_cotidiana",
        "name": "Pacman · Vida Cotidiana",
        "description": "El día a día de un Pac-Man en su rutina — trabajando en el día, descansando en casa por la tarde y durmiendo dulcemente por la noche.",
        "glow": "#FACC15",
        "files": {
            "dia": "pacman_de_diatrabajando.jpg",
            "tarde": "pacmandetarde_ensucasa.jpg",
            "noche": "pacmandenoche_dormidito.jpg",
        },
        "prefix": "pacman_vida",
    },
    {
        "theme_id": "daycycle_starsheeptrooper",
        "name": "Star Sheep Trooper",
        "description": "Soldado borrego galáctico patrullando bases en distintos momentos del día — heroísmo cósmico con un toque tierno.",
        "glow": "#A78BFA",
        "files": {
            "dia": "starsheeptrooper_dia.jpg",
            "tarde": "starsheeptrooper_tarde.jpg",
            "noche": "starsheeptrooper_noche.jpg",
        },
        "prefix": "starsheep_trooper",
    },
    {
        "theme_id": "daycycle_egipto_piramides",
        "name": "Egipto · Pirámides Eternas",
        "description": "Las pirámides milenarias vistas a tres horas distintas — sol del día, atardecer ámbar sobre el desierto y noche estrellada con la luna llena.",
        "glow": "#F59E0B",
        "files": {
            "dia": "egiptodia.jpg",
            "tarde": "egipto_tarde.jpg",
            "noche": "egipto_noche.jpg",
        },
        "prefix": "egipto_piramides",
    },
]

STATICS = [
    {
        "id": "gatito_naranjoso_afuera",
        "src": "gatitonaranjosoafueradesucasa_estatica.jpg",
        "name": "Gatito Naranjoso · Afuera de Casa",
        "description": "Un gatito naranjoso disfrutando del exterior de su casa — escena cozy con vegetación y luces cálidas.",
        "cat": "NATURE",
        "glow": "#F97316",
        "tags": ["gatito", "naranjoso", "casa", "cozy", "afuera", "mascotas"],
    },
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


def encode_webp(src, dst, quality=90):
    img = Image.open(src).convert("RGB")
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes(), img


def encode_preview(src, dst, max_side=540, quality=85):
    img = Image.open(src).convert("RGB")
    img.thumbnail((max_side, max_side * 2), Image.LANCZOS)
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes()


print("=" * 60)
print("Batch B — 4 Day Cycles + 1 Static")
print("=" * 60)

# 1) DAY CYCLES
catalog = get_catalog()
themes = catalog.get("themes", [])
for dc in DAY_CYCLES:
    print(f"\n[DAY CYCLE] {dc['name']}")
    remote_map = {}
    for moment, fname in dc["files"].items():
        src = DOWNLOADS / fname
        if not src.exists():
            raise SystemExit(f"NO existe {src}")
        shutil.copy2(src, BACKUP / fname)
        remote = f"{dc['prefix']}_{moment}.webp"
        out = WORK / remote
        body, _ = encode_webp(src, out)
        put(remote, body)
        remote_map[moment] = remote
    # preview = downscale del día
    prev_remote = f"{dc['prefix']}_preview.webp"
    prev_body = encode_preview(DOWNLOADS / dc["files"]["dia"], WORK / prev_remote)
    put(prev_remote, prev_body)
    # entry
    new_theme = {
        "id": dc["theme_id"],
        "name": dc["name"],
        "description": dc["description"],
        "previewImage": prev_remote,
        "morningImage": remote_map["dia"],
        "afternoonImage": remote_map["dia"],   # duplicado
        "eveningImage": remote_map["tarde"],
        "nightImage": remote_map["noche"],
        "glowColor": dc["glow"],
    }
    idx = next((i for i, t in enumerate(themes) if t.get("id") == dc["theme_id"]), -1)
    if idx >= 0:
        themes[idx] = new_theme; print(f"    catalog: replace at {idx}")
    else:
        themes.append(new_theme); print(f"    catalog: append (total {len(themes)})")

catalog["themes"] = themes
print(f"\n[catalog] saving {len(themes)} themes")
put_catalog(catalog)

# 2) STATICS
print("\n" + "=" * 60); print("STATICS"); print("=" * 60)
conn = connect(); cur = conn.cursor()
for w in STATICS:
    src = DOWNLOADS / w["src"]
    if not src.exists():
        print(f"\n[SKIP] {w['id']}: NO existe"); continue
    print(f"\n[STATIC] {w['id']}  {w['name']}")
    shutil.copy2(src, BACKUP / w["src"])
    img = Image.open(src).convert("RGB")
    full_remote = f"{w['id']}.webp"
    prev_remote = f"{w['id']}_preview.webp"
    full_body, _ = encode_webp(src, WORK / full_remote)
    prev_body = encode_preview(src, WORK / prev_remote)
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
            %s, %s, %s, 'static'::wallpaper_type,
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

# 3) FCM
print("\n" + "=" * 60); print("FCM"); print("=" * 60)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _fcm_push import send_catalog_invalidate
print(f"  day_cycle  -> {send_catalog_invalidate('day_cycle')}")
print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")
print("\n[OK] batch B completo")
