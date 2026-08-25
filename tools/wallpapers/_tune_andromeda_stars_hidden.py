"""Tune hidden Andromeda scene: gentler depth and subtle star twinkle cycle."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, get_json, put, put_json


SID = "andromeda_cadena_nebular_depth"
STATIC_ID = "andromeda_cadena_nebular_static"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/andromeda_cadena_nebular_20260824")
SPRITES = ROOT / "sprites"
QA = ROOT / "qa"
SIZE = (1080, 2340)
MASTER = ROOT / "production" / "andromeda_cadena_nebular_v2_1080x2340.png"
DEPTH = ROOT / "production" / "andromeda_cadena_nebular_v2_depth_1080x2340.png"
STAR_POINTS = [
    (92, 170, 10, (255, 86, 196)),
    (274, 382, 7, (255, 190, 74)),
    (522, 245, 6, (126, 170, 255)),
    (777, 323, 9, (213, 92, 255)),
    (951, 489, 7, (92, 214, 255)),
    (146, 645, 6, (255, 126, 219)),
    (861, 735, 8, (255, 222, 119)),
]
PHASES = (0.24, 0.55, 1.0, 0.55)


def public_url(name):
    return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{name}"


def make_frame(index, intensity):
    glow = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    core = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cd = ImageDraw.Draw(core)
    for star_index, (x, y, radius, rgb) in enumerate(STAR_POINTS):
        local = intensity if star_index % 4 == index else max(0.16, intensity * 0.48)
        r = max(2, int(radius * (0.75 + local * 0.55)))
        alpha = int(115 * local)
        gd.ellipse((x - r * 3, y - r * 3, x + r * 3, y + r * 3), fill=(*rgb, alpha))
        core_rgb = tuple(min(255, int(channel * 0.35 + 166)) for channel in rgb)
        cd.ellipse((x - max(1, r // 3), y - max(1, r // 3), x + max(1, r // 3), y + max(1, r // 3)), fill=(*core_rgb, int(245 * local)))
        cd.line((x - r * 2, y, x + r * 2, y), fill=(*rgb, int(220 * local)), width=1)
        cd.line((x, y - r * 2, x, y + r * 2), fill=(*rgb, int(220 * local)), width=1)
    glow = glow.filter(ImageFilter.GaussianBlur(10))
    frame = Image.alpha_composite(glow, core)
    path = SPRITES / f"stars_twinkle_{index}.webp"
    frame.save(path, "WEBP", lossless=True, method=6)
    return path


def webp_bytes(image, *, quality=None, lossless=False):
    import io
    out = io.BytesIO()
    image.save(out, "WEBP", quality=quality or 100, lossless=lossless, method=6)
    return out.getvalue()


def main():
    SPRITES.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    if spec.get("published") is not False:
        raise RuntimeError("Safety stop: Andromeda must remain hidden while tuning")

    before = json.loads(json.dumps(spec))
    (QA / "SCENE_SPEC_BEFORE_STAR_TUNE.json").write_text(
        json.dumps(before, indent=2, ensure_ascii=False), encoding="utf-8")

    with Image.open(MASTER) as source:
        rgb = source.convert("RGB")
        if rgb.size != SIZE:
            raise RuntimeError(f"Unexpected RGB dimensions: {rgb.size}")
        background_body = webp_bytes(rgb, quality=90)
        static_body = webp_bytes(rgb, quality=90)
        preview = rgb.resize((540, 1170), Image.Resampling.LANCZOS)
        preview_body = webp_bytes(preview, quality=42)
        if len(preview_body) >= 50_000:
            preview_body = webp_bytes(preview, quality=20)
        if len(preview_body) >= 50_000:
            preview_body = webp_bytes(preview, quality=12)
        if len(preview_body) >= 50_000:
            raise RuntimeError(f"Preview exceeds 50 KB: {len(preview_body)} bytes")
    with Image.open(DEPTH) as source:
        depth = source.convert("L")
        if depth.size != SIZE:
            raise RuntimeError(f"Unexpected depth dimensions: {depth.size}")
        lo, hi = depth.getextrema()
        if hi - lo < 100:
            raise RuntimeError(f"Insufficient depth range: {lo}..{hi}")
        depth_body = webp_bytes(depth, lossless=True)

    put(IMG_BUCKET, f"{SID}_background.webp", background_body)
    put(IMG_BUCKET, f"{SID}.webp", static_body)
    put(IMG_BUCKET, f"{SID}_preview.webp", preview_body)
    put(IMG_BUCKET, f"{SID}_background_depth.webp", depth_body)
    put(IMG_BUCKET, f"{STATIC_ID}.webp", static_body)
    put(IMG_BUCKET, f"{STATIC_ID}_preview.webp", preview_body)

    layers = [layer for layer in spec.get("image_layers", [])
              if not layer.get("key", "").startswith("stars_twinkle_")]
    background = next(layer for layer in layers if layer.get("key") == "background")
    revision = max(int(layer.get("revision", 1)) for layer in layers) + 1
    background["parallax_factor"] = 0.040
    background["depth_strength"] = 0.28
    background["revision"] = revision

    for index, intensity in enumerate(PHASES):
        path = make_frame(index, intensity)
        remote = f"{SID}_stars_twinkle_{index}.webp"
        body = path.read_bytes()
        put(IMG_BUCKET, remote, body)
        layers.append({
            "key": f"stars_twinkle_{index}",
            "url": public_url(remote),
            "z": 2,
            "parallax_factor": 0.022,
            "scroll_factor": 0.0,
            "scale": 1.26,
            "offset_x_px": 0,
            "offset_y_px": 0,
            "initial_alpha": 1.0 if index == 0 else 0.0,
            "revision": revision,
        })

    spec["image_layers"] = layers
    spec["cycles"] = [cycle for cycle in spec.get("cycles", [])
                      if cycle.get("name") != "stellar_twinkle"]
    spec["cycles"].append({
        "name": "stellar_twinkle",
        "duration_s": 6.4,
        "frames": [
            {"layer_key": f"stars_twinkle_{i}", "from_s": i * 1.6, "to_s": (i + 1) * 1.6}
            for i in range(4)
        ],
    })
    spec["published"] = False
    put_json(SCENES_BUCKET, f"{SID}.json", spec)

    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1 or matches[0].get("published") is not False:
        raise RuntimeError("Safety stop: hidden catalog entry not found")
    catalog["version"] = int(catalog.get("version", 0)) + 1
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    from apply_migration import connect
    conn = connect()
    cur = conn.cursor()
    cur.execute(
        "UPDATE wallpapers SET image_size=%s, preview_size=%s WHERE id=%s AND published=false",
        (len(static_body), len(preview_body), SID),
    )
    if cur.rowcount != 1:
        conn.rollback()
        cur.close()
        conn.close()
        raise RuntimeError("Hidden Postgres row not found")
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers")
    static_sort = cur.fetchone()[0]
    cur.execute(
        """
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'static'::wallpaper_type, 'ANIME'::wallpaper_category, %s,
            %s, %s, %s, %s, '#FF4FBF', 'NEW'::wallpaper_badge, %s,
            false, 0, false, false, 'Pixora Studio', 1080, 2340
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description,
            tags=EXCLUDED.tags, image_path=EXCLUDED.image_path,
            preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color, published=false,
            media_width=1080, media_height=2340, updated_at=now()
        """,
        (
            STATIC_ID,
            "Andromeda: cadena nebular",
            "Shun protege un templo cosmico mientras su cadena atraviesa la nebulosa.",
            ["andromeda", "shun", "saint seiya", "anime", "fan art", "cadena", "cosmos"],
            f"{STATIC_ID}.webp",
            f"{STATIC_ID}_preview.webp",
            len(static_body),
            len(preview_body),
            static_sort,
        ),
    )
    conn.commit()
    cur.close()
    conn.close()

    remote = get_json(SCENES_BUCKET, f"{SID}.json")
    assert remote.get("published") is False
    assert len([l for l in remote["image_layers"] if l["key"].startswith("stars_twinkle_")]) == 4
    assert remote["image_layers"][0]["depth_strength"] == 0.28

    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(remote, indent=2, ensure_ascii=False), encoding="utf-8")
    receipt = {
        "scene_id": SID,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "published": False,
        "catalog_version": catalog["version"],
        "revision": revision,
        "star_frames": 4,
        "cycle_seconds": 6.4,
        "depth_strength": 0.28,
        "parallax_factor": 0.040,
        "background_bytes": len(background_body),
        "depth_bytes": len(depth_body),
        "static_bytes": len(static_body),
        "preview_bytes": len(preview_body),
        "master_file": MASTER.name,
        "depth_file": DEPTH.name,
        "static_id": STATIC_ID,
        "static_hidden_verified": True,
        "hidden_verified": True,
    }
    (QA / "STAR_TUNE_RECEIPT.json").write_text(
        json.dumps(receipt, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(receipt, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
