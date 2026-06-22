"""Day Cycle wallpaper — Ventana Mexicana (día / tarde / noche).

Eduardo entregó 3 imágenes; duplicamos día para llenar morning + afternoon.
Mapping:
    morning   = día (duplicado)
    afternoon = día (mismo archivo en Storage, sólo apunta dos veces)
    evening   = tarde
    night     = noche
    preview   = día (highlight visual)
"""
import json, re, sys, urllib.request
from pathlib import Path
from PIL import Image
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
CATALOG = "day_cycle_catalog.json"

DOWNLOADS = Path(r"C:/Users/lalo/Downloads")
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/day_cycle_ventana_mx")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_daycycle_ventana")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

SK = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
               Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")).group(1)

# Mapping uuid → momento
MAPPING = [
    {"uuid": "31f610b0", "moment": "dia",   "new_name": "ventana_mx_dia"},
    {"uuid": "8d909ed6", "moment": "tarde", "new_name": "ventana_mx_tarde"},
    {"uuid": "7ca641c7", "moment": "noche", "new_name": "ventana_mx_noche"},
]

THEME_ID = "daycycle_ventana_mexicana"
THEME_NAME = "Ventana Mexicana"
THEME_DESC = "Una ventana típica de México que vive las tres luces del día — luz cálida de la mañana, dorado del atardecer y noche cozy con focos cálidos."
GLOW = "#D97706"  # ámbar mexicano cálido


def put(remote, body, ct):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}",
        data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {remote} -> {r.status} ({len(body):,} B)")


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
        print(f"  PUT {CATALOG} -> {r.status} (catalog updated)")


# 1. Procesar cada imagen → rename + backup + encode WebP + upload
print("=" * 60)
print("Day Cycle — Ventana Mexicana")
print("=" * 60)

remotes = {}  # moment → remote filename
for m in MAPPING:
    matches = list(DOWNLOADS.glob(f"*{m['uuid']}*.jpg"))
    if not matches:
        raise SystemExit(f"No encontrado *{m['uuid']}*")
    src = matches[0]
    print(f"\n[{m['moment']}]  {src.name[:50]}")
    new_dl = DOWNLOADS / f"{m['new_name']}.jpg"
    if src != new_dl:
        src.rename(new_dl); src = new_dl
    import shutil
    shutil.copy2(src, BACKUP / f"{m['new_name']}.jpg")

    img = Image.open(src).convert("RGB")
    remote = f"{m['new_name']}.webp"
    out = WORK / remote
    img.save(out, "WEBP", quality=90, method=6)
    put(remote, out.read_bytes(), "image/webp")
    remotes[m["moment"]] = remote

# 2. Preview = downscale del DÍA
print("\n[preview]")
dia_img = Image.open(DOWNLOADS / "ventana_mx_dia.jpg").convert("RGB")
dia_img.thumbnail((540, 1170), Image.LANCZOS)
prev_path = WORK / "ventana_mx_preview.webp"
dia_img.save(prev_path, "WEBP", quality=85, method=6)
put("ventana_mx_preview.webp", prev_path.read_bytes(), "image/webp")

# 3. Update catalog — primer item
print("\n[catalog]")
cat = get_catalog()
themes = cat.get("themes", [])
new_theme = {
    "id": THEME_ID,
    "name": THEME_NAME,
    "description": THEME_DESC,
    "previewImage": "ventana_mx_preview.webp",
    "morningImage": remotes["dia"],
    "afternoonImage": remotes["dia"],  # duplicado
    "eveningImage": remotes["tarde"],
    "nightImage": remotes["noche"],
    "glowColor": GLOW,
}
# Replace if id exists, else append
idx = next((i for i, t in enumerate(themes) if t.get("id") == THEME_ID), -1)
if idx >= 0:
    themes[idx] = new_theme
    print(f"  replace existing theme at idx {idx}")
else:
    themes.append(new_theme)
    print(f"  append (total themes: {len(themes)})")
cat["themes"] = themes
put_catalog(cat)

# 4. FCM
print("\n[FCM] day_cycle invalidate")
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _fcm_push import send_catalog_invalidate
print(f"  -> {send_catalog_invalidate('day_cycle')}")

print("\n[OK] Ventana Mexicana publicada como Day Cycle.")
