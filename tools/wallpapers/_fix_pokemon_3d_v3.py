"""
Fix v3 — Pokemon Cafe 3D:
  · Chroma key MAS estricto (solo verde puro chroma, no amarillos de Pikachu)
  · Feather mas suave (radius=1, solo difuminar bordes)
  · Pikachu vuelta a la posicion previa que Eduardo aprobo visualmente
  · Chimenea mas grande + mas a la izquierda + mas abajo
"""
import io, json, re, sys, urllib.request, zipfile
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

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


def remove_chroma_strict(img_rgba: Image.Image, feather_px: int = 1) -> Image.Image:
    """
    STRICT chroma key removal. Only kills pixels that are clearly green-screen
    background:  high saturation green AND red<120 AND blue<120 AND green
    dominates by big margin. Pikachu's yellow (R~250 G~220 B~50) survives
    because its R is way above 120. Then a tiny 1px alpha blur softens the
    edges so the contour doesn't look hard-cut.
    """
    arr = np.array(img_rgba)
    r = arr[..., 0].astype(int)
    g = arr[..., 1].astype(int)
    b = arr[..., 2].astype(int)
    a = arr[..., 3].copy()

    # STRICT chroma green: bright green + low red + low blue + dominant
    is_chroma = (
        (g > 180) &
        (r < 120) &
        (b < 120) &
        (g - r > 60) &
        (g - b > 60)
    )

    new_alpha = a.copy()
    new_alpha[is_chroma] = 0

    if feather_px > 0:
        alpha_img = Image.fromarray(new_alpha)
        alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(radius=feather_px))
        new_alpha = np.array(alpha_img)

    out = arr.copy()
    out[..., 3] = new_alpha
    return Image.fromarray(out)


def extract_and_zip(src_gif: Path, out_zip: Path, label: str, apply_chroma: bool):
    gif = Image.open(src_gif)
    total = 0
    try:
        while True:
            gif.seek(total); total += 1
    except EOFError: pass
    indices = [int(i * total / EXTRACT_FRAMES) for i in range(EXTRACT_FRAMES)]
    print(f"  {label}: {total} frames -> {len(indices)} chroma={apply_chroma}")
    buf = io.BytesIO()
    total_bytes = 0
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for out_i, src_i in enumerate(indices, start=1):
            gif.seek(src_i)
            frame = gif.convert("RGBA")
            if apply_chroma:
                frame = remove_chroma_strict(frame, feather_px=1)
            fb = io.BytesIO()
            frame.save(fb, "PNG", optimize=True)
            data = fb.getvalue()
            zf.writestr(f"frame_{out_i:03d}.png", data)
            total_bytes += len(data)
    out_zip.write_bytes(buf.getvalue())
    print(f"    raw={total_bytes:,}B zip={out_zip.stat().st_size:,}B")
    return {"frames": len(indices), "zip_size": out_zip.stat().st_size}


def put(bucket, remote, local, ct):
    body = local.read_bytes() if isinstance(local, Path) else local
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


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
        print(f"  PUT {bucket}/{remote} -> {r.status} JSON")


if __name__ == "__main__":
    print("=" * 60); print("Pokemon Cafe 3D — fix v3 (chroma estricto)"); print("=" * 60)
    WORK.mkdir(parents=True, exist_ok=True)

    print("\n[1/4] Re-extract chimenea con chroma, Pikachu con feather solo")
    info_c = extract_and_zip(SRC_CHIM, ZIP_CHIM, "Chimenea", apply_chroma=True)
    # Pikachu: chroma estricto + feather. Si el sprite tiene fondo verde puro
    # se quitara; si no, el filtro estricto no toca nada del Pikachu amarillo.
    info_p = extract_and_zip(SRC_PIKA, ZIP_PIKA, "Pikachu", apply_chroma=True)

    print("\n[2/4] Re-upload ZIPs")
    put("wallpaper-sprites", "pokemon_cafe_chimenea.zip", ZIP_CHIM, "application/zip")
    put("wallpaper-sprites", "pokemon_cafe_pikachu.zip",  ZIP_PIKA, "application/zip")

    print("\n[3/4] Update manifest")
    mf = get_json("wallpaper-sprites", "manifest.json")
    mf["pokemon_cafe/chimenea"] = {"zip": "pokemon_cafe_chimenea.zip",
                                   "frames": info_c["frames"], "size": info_c["zip_size"]}
    mf["pokemon_cafe/pikachu"]  = {"zip": "pokemon_cafe_pikachu.zip",
                                   "frames": info_p["frames"], "size": info_p["zip_size"]}
    put_json("wallpaper-sprites", "manifest.json", mf)

    print("\n[4/4] Update spec — Pikachu back to approved pos, chimenea bigger+left+down")
    spec = get_json("wallpaper-scenes", "pokemon_cafe_3d.json")
    for sp in spec["sprites"]:
        if sp["name"] == "chimenea":
            sp["params"]["x"] = 0.18           # mucho mas a la izquierda
            sp["params"]["y"] = 0.66           # mas abajo
            sp["params"]["scale"] = 0.0042     # ~50% mas grande
            sp["frame_skip"] = 2
            print(f"  chimenea: x=0.18 y=0.66 scale=0.0042")
        elif sp["name"] == "pikachu":
            sp["params"]["x"] = 0.55           # posicion que Eduardo aprobo
            sp["params"]["y"] = 0.67
            sp["params"]["scale"] = 0.0030
            sp["frame_skip"] = 12              # ciclo lento ~6s mantenido
            print(f"  pikachu : x=0.55 y=0.67 scale=0.0030 frame_skip=12")
    put_json("wallpaper-scenes", "pokemon_cafe_3d.json", spec)

    print("\n[5/5] FCM")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  FCM wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print("\nFix v3 subido.")
