"""
Fix v5 — Pokemon Cafe 3D:
  · ELIMINAR halo verde alrededor de Pikachu (contorno verde residual)
  · Estrategia: ampliar chroma key (capturar bordes semi-saturados verdes)
    + NO usar feather (bordes hard binarios) + despill agresivo de cualquier
    pixel verde-dominante restante.
  · Borde duro sin antialias visible es mejor que halo verde visible.
"""
import io, json, re, sys, urllib.request, zipfile
from pathlib import Path
import numpy as np
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/pokemon")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_pokemon_3d")
SRC_CHIM = SRC_DIR / "chimenea_activa.gif"
SRC_PIKA = SRC_DIR / "pokemon_gif_tomando_cafesito.gif"
ZIP_CHIM = WORK / "pokemon_cafe_chimenea.zip"
ZIP_PIKA = WORK / "pokemon_cafe_pikachu.zip"
EXTRACT_FRAMES = 15

def load_service_key():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)
SK = load_service_key()


def chroma_kill_no_halo(img_rgba: Image.Image) -> Image.Image:
    """
    Aggressive chroma kill — captures pure chroma + borderline green tints,
    so no halo survives. NO feather (binary alpha) eliminates the semi-
    transparent edge that was carrying the green color.
    Pikachu yellow RGB(250, 220, 50): g-r=-30, NOT removed.
    Halo green RGB(150, 200, 100):    g>140, g-r=50, g-b=100, REMOVED.
    """
    arr = np.array(img_rgba)
    r = arr[..., 0].astype(int)
    g = arr[..., 1].astype(int)
    b = arr[..., 2].astype(int)
    a = arr[..., 3].copy()

    # Stage 1 — PURE chroma: bright saturated green
    pure_chroma = (g > 180) & (r < 130) & (b < 130) & (g - r > 50) & (g - b > 50)
    # Stage 2 — BORDERLINE green halo: mid-bright green dominant over R and B
    halo_chroma = (g > 140) & (g - r > 35) & (g - b > 35)

    new_alpha = a.copy()
    new_alpha[pure_chroma | halo_chroma] = 0

    # Despill remaining visible pixels (interior + edge) where G still
    # dominates both R and B by smaller margin (post-halo cleanup)
    visible = new_alpha > 0
    g_over_r = g - r
    g_over_b = g - b
    spill_mask = visible & (g_over_r > 15) & (g_over_b > 15)
    target_g = np.clip((r + b) // 2 + 3, 0, 255)
    new_g = np.where(spill_mask, target_g, g).astype(np.uint8)

    out = arr.copy()
    out[..., 1] = new_g
    out[..., 3] = new_alpha   # binary alpha (no feather) — bordes hard sin halo
    return Image.fromarray(out)


def extract_and_zip(src_gif: Path, out_zip: Path, label: str):
    gif = Image.open(src_gif)
    total = 0
    try:
        while True:
            gif.seek(total); total += 1
    except EOFError: pass
    indices = [int(i * total / EXTRACT_FRAMES) for i in range(EXTRACT_FRAMES)]
    print(f"  {label}: {total}->{len(indices)} (chroma amplio + despill, NO feather)")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for out_i, src_i in enumerate(indices, start=1):
            gif.seek(src_i)
            frame = gif.convert("RGBA")
            frame = chroma_kill_no_halo(frame)
            fb = io.BytesIO()
            frame.save(fb, "PNG", optimize=True)
            zf.writestr(f"frame_{out_i:03d}.png", fb.getvalue())
    out_zip.write_bytes(buf.getvalue())
    print(f"    zip={out_zip.stat().st_size:,}B")
    return {"frames": len(indices), "zip_size": out_zip.stat().st_size}


def put(bucket, remote, local, ct):
    body = local.read_bytes() if isinstance(local, Path) else local
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status}")


def get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def put_json(bucket, remote, data):
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", "application/json"); req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status}")


if __name__ == "__main__":
    print("=" * 60); print("Pokemon Cafe 3D — v5 (anti-halo)"); print("=" * 60)
    WORK.mkdir(parents=True, exist_ok=True)
    info_c = extract_and_zip(SRC_CHIM, ZIP_CHIM, "Chimenea")
    info_p = extract_and_zip(SRC_PIKA, ZIP_PIKA, "Pikachu")
    put("wallpaper-sprites", "pokemon_cafe_chimenea.zip", ZIP_CHIM, "application/zip")
    put("wallpaper-sprites", "pokemon_cafe_pikachu.zip",  ZIP_PIKA, "application/zip")
    mf = get_json("wallpaper-sprites", "manifest.json")
    mf["pokemon_cafe/chimenea"] = {"zip": "pokemon_cafe_chimenea.zip", "frames": info_c["frames"], "size": info_c["zip_size"]}
    mf["pokemon_cafe/pikachu"]  = {"zip": "pokemon_cafe_pikachu.zip",  "frames": info_p["frames"], "size": info_p["zip_size"]}
    put_json("wallpaper-sprites", "manifest.json", mf)
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  FCM wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print("v5 listo")
