"""
Fix v6 — Pokemon Cafe 3D:
ROOT CAUSE FINAL: el GIF original tiene alpha=0 en zonas chroma PERO el RGB
queda como (0,255,0). Cualquier blend/upscale en el renderer arrastra ese
verde a los bordes. Pillow no normaliza RGB cuando alpha=0.

Solucion definitiva:
  1) Preservar la alpha original del GIF (no la inventamos).
  2) Para CUALQUIER pixel con alpha < 250, resetear RGB a (0,0,0).
     Bordes semitransparentes pintan negro suave (sombra natural), NO verde.
  3) Adicionalmente, eliminar cualquier verde residual en pixeles visibles
     (G > R y G > B) reduciendo G a avg(R,B). Pikachu amarillo (R>G) sobrevive.
  4) NO Gaussian blur del alpha — preserva bordes definidos.
"""
import io, json, re, sys, urllib.request, zipfile
from pathlib import Path
import numpy as np
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/pokemon")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_pokemon_3d")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"

def load_service_key():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)
SK = load_service_key()


def kill_chroma_clean(img_rgba: Image.Image) -> Image.Image:
    """Definitive chroma kill: zero out RGB where alpha is low, despill green
    where G dominates R AND B, NO alpha blur (keeps clean edges)."""
    arr = np.array(img_rgba)
    r = arr[..., 0].astype(int)
    g = arr[..., 1].astype(int)
    b = arr[..., 2].astype(int)
    a = arr[..., 3]

    # 1) Where alpha < 250 (transparent or semi), reset RGB to 0 so the
    #    pixel does NOT carry chroma color into any later blending.
    transparent_mask = a < 250
    new_r = np.where(transparent_mask, 0, r).astype(np.uint8)
    new_g = np.where(transparent_mask, 0, g).astype(np.uint8)
    new_b = np.where(transparent_mask, 0, b).astype(np.uint8)

    # 2) Despill remaining visible pixels where G dominates R AND B.
    visible = a >= 250
    g_int = new_g.astype(int)
    r_int = new_r.astype(int)
    b_int = new_b.astype(int)
    spill_mask = visible & (g_int - r_int > 18) & (g_int - b_int > 18)
    target_g = np.clip((r_int + b_int) // 2 + 3, 0, 255)
    new_g = np.where(spill_mask, target_g, new_g).astype(np.uint8)

    # 3) For ANY pixel where alpha is high but it's clearly pure chroma green
    #    (some GIFs have alpha=255 but color=#00FF00 in border antialias),
    #    kill it explicitly.
    pure_chroma_visible = visible & (g_int > 200) & (r_int < 80) & (b_int < 80)
    new_a = a.copy()
    new_a[pure_chroma_visible] = 0
    new_r = np.where(pure_chroma_visible, 0, new_r).astype(np.uint8)
    new_g = np.where(pure_chroma_visible, 0, new_g).astype(np.uint8)
    new_b = np.where(pure_chroma_visible, 0, new_b).astype(np.uint8)

    out = np.dstack([new_r, new_g, new_b, new_a])
    return Image.fromarray(out)


def extract_zip(src_gif, out_zip, label, n_frames=8):
    gif = Image.open(src_gif)
    total = 0
    try:
        while True:
            gif.seek(total); total += 1
    except EOFError: pass
    indices = [int(i * total / n_frames) for i in range(n_frames)]
    print(f"  {label}: {total} src frames -> {len(indices)} cleaned")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for out_i, src_i in enumerate(indices, start=1):
            gif.seek(src_i)
            frame = gif.convert("RGBA")
            frame = kill_chroma_clean(frame)
            fb = io.BytesIO()
            frame.save(fb, "PNG", optimize=True)
            zf.writestr(f"frame_{out_i:03d}.png", fb.getvalue())
    out_zip.write_bytes(buf.getvalue())
    print(f"    -> {out_zip.name}: {out_zip.stat().st_size:,} B")
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
    print("=" * 60); print("Pokemon Cafe 3D — v6 (RGB zero on transparent)"); print("=" * 60)
    WORK.mkdir(parents=True, exist_ok=True)

    info_c = extract_zip(SRC_DIR / "chimenea_activa.gif",
                        WORK / "pokemon_cafe_chimenea.zip", "Chimenea")
    info_p = extract_zip(SRC_DIR / "pokemon_gif_tomando_cafesito.gif",
                        WORK / "pokemon_cafe_pikachu.zip", "Pikachu")

    put("wallpaper-sprites", "pokemon_cafe_chimenea.zip", WORK / "pokemon_cafe_chimenea.zip", "application/zip")
    put("wallpaper-sprites", "pokemon_cafe_pikachu.zip",  WORK / "pokemon_cafe_pikachu.zip",  "application/zip")

    mf = get_json("wallpaper-sprites", "manifest.json")
    mf["pokemon_cafe/chimenea"] = {"zip": "pokemon_cafe_chimenea.zip", "frames": info_c["frames"], "size": info_c["zip_size"]}
    mf["pokemon_cafe/pikachu"]  = {"zip": "pokemon_cafe_pikachu.zip",  "frames": info_p["frames"], "size": info_p["zip_size"]}
    put_json("wallpaper-sprites", "manifest.json", mf)

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  FCM wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print("\nv6 OK — RGB queda en negro donde alpha=0, no mas halo verde.")
