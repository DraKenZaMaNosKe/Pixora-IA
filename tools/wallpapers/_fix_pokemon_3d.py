"""
Fix v2 — Pokemon Cafe 3D sprites:
  · Aplicar chroma key (verde -> transparente) + feather de bordes
  · Spill suppression (reducir tinte verde en pixeles semi-transparentes)
  · Re-zip + re-upload ambos sprites
  · Update spec con scales mas grandes + frame_skip lento para Pikachu
  · Limpiar caches sprites en device + relaunch

Razon: los GIFs originales tienen fondo green chroma key sin limpiar. PIL
no removia el verde porque el GIF era opaco (mode='P' con paleta indexada).
Necesitamos detectar pixeles verdes dominantes y setearlos como alpha=0,
mas un blur leve del canal alpha para que los bordes no se vean cortados.
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


def remove_green_chroma(img_rgba: Image.Image,
                        g_min: int = 90,
                        g_dom: int = 30,
                        feather_px: int = 2) -> Image.Image:
    """
    Detect green chroma pixels (high G, dominant over R and B), make them
    fully transparent. Then apply a small Gaussian blur to the alpha channel
    so the edges feather softly into the background instead of hard-cutting.
    Also spill-suppresses any remaining greenish tint on semi-transparent
    pixels (typical at the edge of the subject).
    """
    arr = np.array(img_rgba)
    r, g, b, a = arr[..., 0], arr[..., 1], arr[..., 2], arr[..., 3]

    is_green = (g > g_min) & (g.astype(int) > r.astype(int) + g_dom) & \
               (g.astype(int) > b.astype(int) + g_dom)

    new_alpha = a.copy()
    new_alpha[is_green] = 0

    if feather_px > 0:
        alpha_img = Image.fromarray(new_alpha)
        alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(radius=feather_px))
        new_alpha = np.array(alpha_img)

    # Spill suppression on edge pixels (semi-transparent + still greenish)
    edge_mask = (new_alpha > 0) & (new_alpha < 255)
    avg_rb = ((r.astype(int) + b.astype(int)) // 2).astype(np.uint8)
    greenish = g > avg_rb
    spill_mask = edge_mask & greenish
    new_g = np.where(spill_mask, avg_rb, g)

    out = arr.copy()
    out[..., 1] = new_g
    out[..., 3] = new_alpha
    return Image.fromarray(out)


def extract_and_zip(src_gif: Path, out_zip: Path, label: str):
    gif = Image.open(src_gif)
    total = 0
    try:
        while True:
            gif.seek(total); total += 1
    except EOFError: pass
    indices = [int(i * total / EXTRACT_FRAMES) for i in range(EXTRACT_FRAMES)]
    print(f"  {label}: source {total} frames -> sampling {len(indices)} + chroma-key")
    buf = io.BytesIO()
    total_bytes = 0
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for out_i, src_i in enumerate(indices, start=1):
            gif.seek(src_i)
            frame = gif.convert("RGBA")
            frame = remove_green_chroma(frame)
            fb = io.BytesIO()
            frame.save(fb, "PNG", optimize=True)
            data = fb.getvalue()
            zf.writestr(f"frame_{out_i:03d}.png", data)
            total_bytes += len(data)
    out_zip.write_bytes(buf.getvalue())
    print(f"    -> {out_zip.name}: raw={total_bytes:,}B zip={out_zip.stat().st_size:,}B")
    return {"frames": len(indices), "raw_size": total_bytes, "zip_size": out_zip.stat().st_size}


def put(bucket, remote, local, ct):
    body = local.read_bytes() if isinstance(local, Path) else local
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


def get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def put_json(bucket, remote, data):
    payload = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=payload, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} (JSON)")


if __name__ == "__main__":
    print("=" * 60); print("Pokemon Cafe 3D — chroma-key fix v2"); print("=" * 60)

    print("\n[1/4] Re-extract + chroma-key + re-zip")
    WORK.mkdir(parents=True, exist_ok=True)
    info_c = extract_and_zip(SRC_CHIM, ZIP_CHIM, "Chimenea")
    info_p = extract_and_zip(SRC_PIKA, ZIP_PIKA, "Pikachu")

    print("\n[2/4] Re-upload ZIPs (overwrite)")
    put("wallpaper-sprites", "pokemon_cafe_chimenea.zip", ZIP_CHIM, "application/zip")
    put("wallpaper-sprites", "pokemon_cafe_pikachu.zip",  ZIP_PIKA, "application/zip")

    print("\n[3/4] Update manifest (sizes refreshed)")
    mf = get_json("wallpaper-sprites", "manifest.json")
    mf["pokemon_cafe/chimenea"] = {"zip": "pokemon_cafe_chimenea.zip",
                                   "frames": info_c["frames"],
                                   "size": info_c["zip_size"]}
    mf["pokemon_cafe/pikachu"]  = {"zip": "pokemon_cafe_pikachu.zip",
                                   "frames": info_p["frames"],
                                   "size": info_p["zip_size"]}
    put_json("wallpaper-sprites", "manifest.json", mf)

    print("\n[4/4] Update spec — bigger sprites + slower Pikachu sip cycle")
    spec = get_json("wallpaper-scenes", "pokemon_cafe_3d.json")
    for sp in spec["sprites"]:
        if sp["name"] == "chimenea":
            # Chimenea de piedra del fondo: cuesta visualizar exacto donde
            # va el fuego encima — primer intento, ajustar si Eduardo dice.
            sp["params"]["x"] = 0.27
            sp["params"]["y"] = 0.60
            sp["params"]["scale"] = 0.0028
            sp["frame_skip"] = 2          # fuego dinamico, ~7fps
            print(f"  chimenea: x=0.27 y=0.60 scale=0.0028 frame_skip=2 (~7fps fuego)")
        elif sp["name"] == "pikachu":
            sp["params"]["x"] = 0.55
            sp["params"]["y"] = 0.72
            sp["params"]["scale"] = 0.0042
            sp["frame_skip"] = 12         # 15 frames * 12 / 30fps = 6 segundos por ciclo
            print(f"  pikachu : x=0.55 y=0.72 scale=0.0042 frame_skip=12 (~6s ciclo)")
    put_json("wallpaper-scenes", "pokemon_cafe_3d.json", spec)

    print("\n[5/5] FCM")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  FCM wallpapers -> {send_catalog_invalidate('wallpapers')}")

    print("\n" + "=" * 60); print("Fix subido"); print("=" * 60)
