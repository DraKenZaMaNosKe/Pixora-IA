"""
Re-sube los sprites de Alicia con AUTO-TRIM (bounding box del alpha, sin tocar
al personaje) y corrige scale/posición en la spec.

Antes: sprites 1080x1920 (canvas completo) → salían gigantes a scale 1.0.
Ahora: sprites recortados al personaje + scale para tamaño natural.

Trim medido:
  · Alicia: 404x794, centro (0.502, 0.716)
  · Gato:   622x887, centro (0.501, 0.440)

Con high_res=true → div=1 → rw = natW · scale · 1080 · factor.
Para rw = natW (tamaño natural, misma fracción del ancho que en la
composición original): scale = 1/1080 = 0.000926.

Usa NUEVOS manifest_keys/zip names para evitar el cache de 1h del admin server
(/api/sprite-frame). Bump del catalog para que el editor recargue. Sin FCM
(se dispara cuando el usuario guarde posiciones en el editor).
"""
from __future__ import annotations
import io, json, re, sys, urllib.request, zipfile
from pathlib import Path
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
TMP = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_alicia")

IMG_BUCKET     = "wallpaper-images"
SCENES_BUCKET  = "wallpaper-scenes"
SPRITES_BUCKET = "wallpaper-sprites"
R_SPEC     = "alicia_wonderland.json"
R_CATALOG  = "catalog_index.json"
R_MANIFEST = "manifest.json"

# Nuevos keys (evitan el cache del admin server)
ALICIA_KEY = "alicia_wonderland/alicia_t"
GATO_KEY   = "alicia_wonderland/gato_t"
ALICIA_ZIP = "alicia_wonderland_alicia_t.zip"
GATO_ZIP   = "alicia_wonderland_gato_t.zip"

SCALE = 0.000926  # 1/1080 → tamaño natural con high_res
# centros medidos (respecto al canvas 1080x1920). La Y es un punto de partida
# — el usuario afina en el editor (el fondo es 9:16 vs referencia 9:19.5).
ALICIA_PARAMS = {"x": 0.502, "y": 0.716, "scale": SCALE, "alpha": 255,
                 "parallax_factor": 0.03, "z": 2, "high_res": True}
GATO_PARAMS   = {"x": 0.501, "y": 0.440, "scale": SCALE, "alpha": 255,
                 "parallax_factor": 0.0, "z": 1, "high_res": True}


def load_service_key():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_service_key()


def put(bucket, remote, body, ct):
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


def put_json(bucket, remote, data):
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    put(bucket, remote, body, "application/json")


def get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def one_frame_zip(png_path: Path) -> bytes:
    img = Image.open(png_path).convert("RGBA")
    fbuf = io.BytesIO(); img.save(fbuf, "PNG", optimize=True)
    zbuf = io.BytesIO()
    with zipfile.ZipFile(zbuf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("frame_001.png", fbuf.getvalue())
    print(f"    {png_path.name}: {img.width}x{img.height}")
    return zbuf.getvalue()


print("=" * 60)
print("Alicia — re-trim sprites + fix scale/pos")
print("=" * 60)

# 1. ZIPs trimmed
print("\n[1/4] Crear ZIPs trimmed")
alicia_zip = one_frame_zip(TMP / "alicia_trim.png")
gato_zip   = one_frame_zip(TMP / "gato_trim.png")

# 2. Subir con nuevos nombres
print("\n[2/4] Subir sprites trimmed")
put(SPRITES_BUCKET, ALICIA_ZIP, alicia_zip, "application/zip")
put(SPRITES_BUCKET, GATO_ZIP, gato_zip, "application/zip")

# 3. Manifest (nuevos keys)
print("\n[3/4] Manifest")
manifest = get_json(SPRITES_BUCKET, R_MANIFEST)
manifest[ALICIA_KEY] = {"zip": ALICIA_ZIP, "frames": 1, "size": len(alicia_zip)}
manifest[GATO_KEY]   = {"zip": GATO_ZIP, "frames": 1, "size": len(gato_zip)}
put_json(SPRITES_BUCKET, R_MANIFEST, manifest)

# 4. Spec (nuevos manifest_keys + params corregidos) + catalog bump
print("\n[4/4] Spec + catalog bump")
spec = get_json(SCENES_BUCKET, R_SPEC)
for sp in spec["sprites"]:
    if sp["name"] == "alicia":
        sp["manifest_key"] = ALICIA_KEY
        sp["params"] = ALICIA_PARAMS
    elif sp["name"] == "gato_cheshire":
        sp["manifest_key"] = GATO_KEY
        sp["params"] = GATO_PARAMS
put_json(SCENES_BUCKET, R_SPEC, spec)

cat = get_json(IMG_BUCKET, R_CATALOG)
cat["version"] = (cat.get("version", 0) or 0) + 1
put_json(IMG_BUCKET, R_CATALOG, cat)
print(f"  · catalog version -> {cat['version']}")

print("\n" + "=" * 60)
print("Listo. Refresca el sprite editor (F5) y abre 'alicia_wonderland'.")
print("Los sprites ahora salen a tamaño natural. Afina la Y si hace falta.")
print("=" * 60)
