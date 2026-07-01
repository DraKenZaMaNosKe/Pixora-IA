"""
Ryu Hadouken — canvas_scene (patron Goku Genkidama).

Capas:
  ryu_solo_fondo.png          -> sky/fondo (parallax bajo, cover-fit runtime)
  ryu_solo_completo.png       -> Ryu (SUBJECT COMPLETO tight en canvas TARGET,
                                 scale runtime lo agranda al tamaño final)
  ryu_wallpaper_estatico.png  -> flat grid + preview
  ryu_/ryu_.gif               -> sprite orb (frames extraidos + crop)

FORMULA CROSS-DEVICE (validated 2026-06-30, both Ryu and Morrigan):

  1. Subject bitmap: crop tight to subject bbox, resize with MARGIN=15% into
     canvas TARGET (1080x2340), centered. Subject NEVER touches canvas edges
     — guarantees no crop on any device aspect ratio.

  2. Spec: scale = TARGET_W / new_subject_width  (renders subject at ~TARGET
     width on Samsung), offset_x_px=0, offset_y_px=0. Editor fine-tunes if
     needed.

  3. Background bitmap: cover-fit to TARGET (fill 1080x2340, crop edges).
     Never pad-with-black — bands become visible on devices where
     surface_h == TARGET_h (Samsung A155M is TARGET-shaped).

  4. Runtime: renderer applies cover-fit(bitmap→surface) × def.scale. Since
     bitmap is TARGET-aspect (0.462) and every phone surface is close to
     that ratio, cover-fit factor is consistent across devices → subject
     position stays identical.

  5. Multi-frame elements (hair animation, orb): pack as sprite ZIP with
     manifest_key. behavior="static", frame_skip=N auto-cycles. Use
     params.z to interleave with image_layers (v1.7.47+).

See tools/wallpapers/_upload_morrigan_darkstalkers.py for the reference
implementation of this formula (dedicated bake_subject_complete helper).
"""
from __future__ import annotations

import io
import json
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/ryu")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_ryu_hadouken")

SRC_BG = SRC / "ryu_solo_fondo.png"
SRC_RYU = SRC / "ryu_solo_completo.png"
# Escala vía spec (cover-fit base × scale > 1 → bitmap más grande que pantalla,
# sin recortar — el parallax pannea sobre el excedente). No escalar en CapCut.
RYU_LAYER_SCALE = 2.35
RYU_OFFSET_X = 18
RYU_OFFSET_Y = -1208
ORB_PAD = 24
ORB_POS = {"x": 0.554, "y": 0.310, "scale": 0.0010}
FONDO_SCALE = 1.18
FONDO_OFFSET_Y = 72
SRC_FLAT = SRC / "ryu_wallpaper_estatico.png"
SRC_ORB_GIF = SRC / "ryu_" / "ryu_.gif"

TARGET = (1080, 2340)
SCENE_ID = "ryu_hadouken"
ORB_KEY = "ryu_hadouken_orb"

IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"
SPRITES_BUCKET = "wallpaper-sprites"

R_BG = f"{SCENE_ID}_bg.webp"
R_RYU = f"{SCENE_ID}_ryu.webp"
R_FLAT = f"{SCENE_ID}.webp"
R_PREVIEW = f"{SCENE_ID}_preview.webp"
R_SPEC = f"{SCENE_ID}.json"
R_CATALOG = "catalog_index.json"
R_MANIFEST = "manifest.json"
ORB_ZIP = WORK / "ryu_hadouken_orb.zip"

TAGS = [
    "ryu", "street fighter", "hadouken", "fighting", "anime",
    "capcom", "3d", "parallax", "live", "animated", "energy",
]
GLOW = "#00B4FF"

EXTRACT_FRAMES = 12
FRAME_SKIP = 2.8


def load_service_key() -> str:
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_service_key()


def put(bucket: str, remote: str, local: Path, ct: str) -> int:
    body = local.read_bytes()
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body,
        method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")
    return len(body)


def put_json(bucket: str, remote: str, data: dict) -> None:
    payload = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=payload,
        method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} (JSON)")


def get_json(bucket: str, remote: str) -> dict:
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def cover_fit(img, target=TARGET, transparent=False):
    from PIL import Image

    tw, th = target
    src = img.convert("RGBA")
    sw, sh = src.size
    scale = max(tw / sw, th / sh)
    nw, nh = int(round(sw * scale)), int(round(sh * scale))
    resized = src.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    cropped = resized.crop((left, top, left + tw, top + th))
    if not transparent:
        out = Image.new("RGB", target, (0, 0, 0))
        out.paste(cropped, mask=cropped.split()[3])
        return out
    return cropped


def phase1_process() -> dict:
    from PIL import Image

    print("\n[1/6] Procesamiento local")
    WORK.mkdir(parents=True, exist_ok=True)
    info: dict = {}

    bg = cover_fit(Image.open(SRC_BG))
    # Ryu: resolución nativa 1080x1920 — el engine hace cover-fit + scale en runtime.
    ryu = Image.open(SRC_RYU).convert("RGBA")
    flat = cover_fit(Image.open(SRC_FLAT))

    out_bg = WORK / R_BG
    out_ryu = WORK / R_RYU
    out_flat = WORK / R_FLAT
    out_prev = WORK / R_PREVIEW

    bg.save(out_bg, "WEBP", quality=90, method=6)
    ryu.save(out_ryu, "WEBP", quality=92, method=6)
    flat.save(out_flat, "WEBP", quality=88, method=6)

    prev = flat.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(out_prev, "WEBP", quality=85, method=6)

    info.update(
        {
            "bg_w": TARGET[0],
            "bg_h": TARGET[1],
            "bg_size": out_bg.stat().st_size,
            "ryu_size": out_ryu.stat().st_size,
            "flat_size": out_flat.stat().st_size,
            "prev_size": out_prev.stat().st_size,
        }
    )
    print(f"  · bg/flat -> {TARGET[0]}x{TARGET[1]} · ryu native {ryu.size[0]}x{ryu.size[1]}")

    gif = Image.open(SRC_ORB_GIF)
    total = 0
    while True:
        try:
            gif.seek(total)
            total += 1
        except EOFError:
            break
    indices = [int(i * total / EXTRACT_FRAMES) for i in range(EXTRACT_FRAMES)]
    print(f"  · orb GIF: {total} frames -> {len(indices)} cropped samples")

    boxes = []
    for src_i in indices:
        gif.seek(src_i)
        frame = gif.convert("RGBA")
        bbox = frame.split()[3].getbbox()
        if bbox:
            boxes.append(bbox)
    if not boxes:
        raise SystemExit("GIF orb sin alpha bbox")
    x0 = max(0, min(b[0] for b in boxes) - ORB_PAD)
    y0 = max(0, min(b[1] for b in boxes) - ORB_PAD)
    x1 = min(gif.width, max(b[2] for b in boxes) + ORB_PAD)
    y1 = min(gif.height, max(b[3] for b in boxes) + ORB_PAD)
    print(f"  · orb crop {x1 - x0}x{y1 - y0} from ({x0},{y0})")

    buf = io.BytesIO()
    raw_total = 0
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for out_i, src_i in enumerate(indices, start=1):
            gif.seek(src_i)
            frame = gif.convert("RGBA").crop((x0, y0, x1, y1))
            fbuf = io.BytesIO()
            frame.save(fbuf, "PNG", optimize=True)
            data = fbuf.getvalue()
            zf.writestr(f"frame_{out_i:03d}.png", data)
            raw_total += len(data)
    ORB_ZIP.write_bytes(buf.getvalue())
    info["orb"] = {
        "frames": len(indices),
        "raw_size": raw_total,
        "zip_size": ORB_ZIP.stat().st_size,
    }
    print(
        f"    -> {ORB_ZIP.name}: {len(indices)} frames, "
        f"zip={info['orb']['zip_size']:,} B"
    )
    return info


def phase2_upload(info: dict) -> None:
    print("\n[2/6] Upload assets")
    put(IMG_BUCKET, R_BG, WORK / R_BG, "image/webp")
    put(IMG_BUCKET, R_RYU, WORK / R_RYU, "image/webp")
    put(IMG_BUCKET, R_FLAT, WORK / R_FLAT, "image/webp")
    put(IMG_BUCKET, R_PREVIEW, WORK / R_PREVIEW, "image/webp")
    put(SPRITES_BUCKET, "ryu_hadouken_orb.zip", ORB_ZIP, "application/zip")


def phase3_manifest(info: dict) -> None:
    print("\n[3/6] wallpaper-sprites/manifest.json")
    manifest = get_json(SPRITES_BUCKET, R_MANIFEST)
    manifest[ORB_KEY] = {
        "zip": "ryu_hadouken_orb.zip",
        "frames": info["orb"]["frames"],
        "size": info["orb"]["zip_size"],
    }
    put_json(SPRITES_BUCKET, R_MANIFEST, manifest)


def phase4_spec() -> dict:
    print("\n[4/6] Scene spec")
    url_bg = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_BG}"
    url_ryu = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_RYU}"
    url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_FLAT}"
    url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}"

    spec = {
        "schema_version": 1,
        "id": SCENE_ID,
        "type": "canvas_scene",
        "title": {
            "en": "Ryu Hadouken",
            "es": "Ryu Cargando Poder",
        },
        "tags": TAGS,
        "category": "anime",
        "featured": True,
        "background": {
            "url": url_flat,
            "preview_url": url_prev,
            "scroll": False,
        },
        "image_layers": [
            {
                "key": "fondo",
                "url": url_bg,
                "z": 0,
                "parallax_factor": 0.35,
                "scroll_factor": 0.35,
                "scale": FONDO_SCALE,
                "offset_x_px": 0,
                "offset_y_px": FONDO_OFFSET_Y,
                "revision": 2,
            },
            {
                "key": "ryu",
                "url": url_ryu,
                "z": 1,
                "parallax_factor": 0.85,
                "scroll_factor": 0.85,
                "scale": RYU_LAYER_SCALE,
                "offset_x_px": RYU_OFFSET_X,
                "offset_y_px": RYU_OFFSET_Y,
                "revision": 3,
            },
        ],
        "sprites": [
            {
                "name": "orb",
                "manifest_key": ORB_KEY,
                "behavior": "static",
                "frame_skip": FRAME_SKIP,
                "params": {
                    "x": ORB_POS["x"],
                    "y": ORB_POS["y"],
                    "scale": ORB_POS["scale"],
                    "alpha": 255,
                    "parallax_factor": 0.85,
                    "high_res": True,
                },
            }
        ],
        "particles": [],
        "events": [
            {
                "kind": "flash_overlay",
                "interval_s": 2.8,
                "duration_s": 0.35,
                "params": {
                    "color": "#B8E8FF",
                    "peak_alpha": 75,
                },
            }
        ],
    }
    put_json(SCENES_BUCKET, R_SPEC, spec)
    return spec


def phase5_catalog_and_postgres(info: dict, spec: dict) -> None:
    print("\n[5/6] catalog_index + Postgres")
    cat = get_json(IMG_BUCKET, R_CATALOG)
    cat["version"] = (cat.get("version", 0) or 0) + 1
    entry = {
        "id": SCENE_ID,
        "type": "canvas_scene",
        "schema": 1,
        "title": spec["title"],
        "preview_url": f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}",
        "tags": TAGS,
        "category": "anime",
        "featured": True,
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{R_SPEC}",
    }
    items = cat.get("items", [])
    items = [it for it in items if it.get("id") != SCENE_ID]
    items.insert(0, entry)
    cat["items"] = items
    put_json(IMG_BUCKET, R_CATALOG, cat)
    print(f"  · catalog_index v{cat['version']} ({len(items)} items)")

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    cur.execute(
        """
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'static'::wallpaper_type, 'SCENES'::wallpaper_category, %s,
            %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, true, 0,
            true, false, %s, %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description, tags=EXCLUDED.tags,
            image_path=EXCLUDED.image_path, preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color, badge=EXCLUDED.badge,
            featured=EXCLUDED.featured, published=EXCLUDED.published,
            media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
            updated_at=now()
        RETURNING id;
        """,
        (
            SCENE_ID,
            "Ryu Cargando Poder",
            "Ryu de Street Fighter cargando su Hadouken — parallax 3D y esfera de energia animada",
            TAGS,
            R_FLAT,
            R_PREVIEW,
            info["flat_size"],
            info["prev_size"],
            GLOW,
            next_sort,
            "Pixora Studio",
            info["bg_w"],
            info["bg_h"],
        ),
    )
    print(f"  · postgres upserted: {cur.fetchone()[0]}")
    conn.commit()
    cur.close()
    conn.close()


def phase6_fcm() -> None:
    print("\n[6/6] FCM invalidate")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate

    print(f"  · wallpapers -> {send_catalog_invalidate('wallpapers')}")


if __name__ == "__main__":
    print("=" * 60)
    print("Ryu Hadouken — canvas_scene publisher")
    print("=" * 60)
    for src in (SRC_BG, SRC_RYU, SRC_FLAT, SRC_ORB_GIF):
        if not src.exists():
            raise SystemExit(f"No existe {src}")
    info = phase1_process()
    phase2_upload(info)
    phase3_manifest(info)
    spec = phase4_spec()
    phase5_catalog_and_postgres(info, spec)
    phase6_fcm()
    print("\n" + "=" * 60)
    print("Ryu Hadouken publicado")
    print(f"  · spec: wallpaper-scenes/{R_SPEC}")
    print(f"  · sprite: {ORB_KEY} ({info['orb']['frames']} frames)")
    print("=" * 60)