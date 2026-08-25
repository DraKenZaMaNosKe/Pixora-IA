"""Add a subtle living eclipse and cloud illumination to hidden Mumm-Ra scene."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, get_json, put, put_json


SID = "mummra_templo_eclipse_depth"
STATIC_ID = "mummra_templo_eclipse_static"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/mummra_templo_eclipse_20260824")
MASTER = ROOT / "production" / "mummra_templo_eclipse_1080x2340.png"
SPRITES = ROOT / "sprites"
QA = ROOT / "qa"
SIZE = (1080, 2340)
PHASES = (0.35, 0.62, 1.0, 0.62)


def public_url(name):
    return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{name}"


def make_frame(index, intensity):
    cx, cy = 550, 215
    halo = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    # Broad eclipse corona. Concentric rings keep the center dark.
    for radius, alpha in ((190, 16), (160, 24), (138, 34), (120, 48)):
        a = int(alpha * intensity)
        hd.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=(255, 35, 42, a))
    halo = halo.filter(ImageFilter.GaussianBlur(34))

    clouds = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    cd = ImageDraw.Draw(clouds)
    cloud_shapes = [
        (250, 190, 505, 365, 26), (585, 180, 845, 360, 28),
        (155, 275, 430, 470, 17), (680, 270, 955, 470, 18),
        (330, 310, 555, 500, 14), (555, 310, 770, 500, 14),
    ]
    for left, top, right, bottom, alpha in cloud_shapes:
        cd.ellipse((left, top, right, bottom), fill=(255, 48, 52, int(alpha * intensity)))
    clouds = clouds.filter(ImageFilter.GaussianBlur(30))
    frame = Image.alpha_composite(halo, clouds)

    # Restore the eclipse disk to transparency so its black center never brightens.
    mask = Image.new("L", SIZE, 255)
    md = ImageDraw.Draw(mask)
    md.ellipse((cx - 93, cy - 93, cx + 93, cy + 93), fill=0)
    frame.putalpha(Image.composite(frame.getchannel("A"), Image.new("L", SIZE, 0), mask))
    path = SPRITES / f"eclipse_glow_{index}.webp"
    frame.save(path, "WEBP", lossless=True, method=6)
    return path


def webp_bytes(image, quality):
    import io
    out = io.BytesIO()
    image.save(out, "WEBP", quality=quality, method=6)
    return out.getvalue()


def main():
    SPRITES.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    if spec.get("published") is not False:
        raise RuntimeError("Safety stop: Mumm-Ra must remain hidden while tuning")
    before = json.loads(json.dumps(spec))
    (QA / "SCENE_SPEC_BEFORE_ECLIPSE_TUNE.json").write_text(
        json.dumps(before, indent=2, ensure_ascii=False), encoding="utf-8")

    with Image.open(MASTER) as source:
        rgb = source.convert("RGB")
        if rgb.size != SIZE:
            raise RuntimeError(f"Unexpected master dimensions: {rgb.size}")
        static_body = webp_bytes(rgb, 88)
        preview = rgb.resize((540, 1170), Image.Resampling.LANCZOS)
        preview_body = webp_bytes(preview, 24)
        if len(preview_body) >= 50_000:
            preview_body = webp_bytes(preview, 14)
        if len(preview_body) >= 50_000:
            raise RuntimeError(f"Preview exceeds 50 KB: {len(preview_body)}")
    put(IMG_BUCKET, f"{SID}.webp", static_body)
    put(IMG_BUCKET, f"{SID}_preview.webp", preview_body)
    put(IMG_BUCKET, f"{STATIC_ID}.webp", static_body)
    put(IMG_BUCKET, f"{STATIC_ID}_preview.webp", preview_body)

    layers = [x for x in spec.get("image_layers", [])
              if not x.get("key", "").startswith("eclipse_glow_")]
    revision = max(int(x.get("revision", 1)) for x in layers) + 1
    for layer in layers:
        layer["revision"] = revision
    for index, intensity in enumerate(PHASES):
        path = make_frame(index, intensity)
        remote = f"{SID}_eclipse_glow_{index}.webp"
        put(IMG_BUCKET, remote, path.read_bytes())
        layers.append({
            "key": f"eclipse_glow_{index}",
            "url": public_url(remote),
            "z": 2,
            "parallax_factor": 0.018,
            "scroll_factor": 0.0,
            "scale": 1.26,
            "offset_x_px": 0,
            "offset_y_px": 0,
            "initial_alpha": 1.0 if index == 0 else 0.0,
            "revision": revision,
        })
    spec["image_layers"] = layers
    spec["cycles"] = [x for x in spec.get("cycles", []) if x.get("name") != "eclipse_breath"]
    spec["cycles"].append({
        "name": "eclipse_breath",
        "duration_s": 3.6,
        "frames": [
            {"layer_key": f"eclipse_glow_{i}", "from_s": i * 0.9, "to_s": (i + 1) * 0.9}
            for i in range(4)
        ],
    })
    spec["published"] = False
    put_json(SCENES_BUCKET, f"{SID}.json", spec)

    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [x for x in catalog.get("items", []) if x.get("id") == SID]
    if len(matches) != 1 or matches[0].get("published") is not False:
        raise RuntimeError("Hidden catalog entry not found")
    catalog["version"] = int(catalog.get("version", 0)) + 1
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    from apply_migration import connect
    conn = connect(); cur = conn.cursor()
    cur.execute(
        "UPDATE wallpapers SET image_size=%s, preview_size=%s WHERE id=%s AND published=false",
        (len(static_body), len(preview_body), SID),
    )
    if cur.rowcount != 1:
        raise RuntimeError("Hidden canvas Postgres row not found")
    cur.execute("SELECT COALESCE(MAX(sort_order),0)+1 FROM wallpapers")
    sort_order = cur.fetchone()[0]
    cur.execute(
        """
        INSERT INTO wallpapers (
            id,name,description,type,category,tags,image_path,preview_path,
            image_size,preview_size,glow_color,badge,sort_order,featured,
            trending_score,published,daily_eligible,author_name,media_width,media_height
        ) VALUES (
            %s,%s,%s,'static'::wallpaper_type,'ANIME'::wallpaper_category,%s,%s,%s,%s,%s,
            '#FF3526','NEW'::wallpaper_badge,%s,false,0,false,false,'Pixora Studio',1080,2340
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name,description=EXCLUDED.description,tags=EXCLUDED.tags,
            image_path=EXCLUDED.image_path,preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size,preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color,published=false,updated_at=now()
        """,
        (STATIC_ID,"Mumm-Ra: templo del eclipse",
         "Mumm-Ra desciende de la Piramide Negra bajo un eclipse rojo.",
         ["mumm-ra","thundercats","fan art","templo","eclipse","villano","retro"],
         f"{STATIC_ID}.webp",f"{STATIC_ID}_preview.webp",len(static_body),len(preview_body),sort_order),
    )
    conn.commit(); cur.close(); conn.close()

    remote = get_json(SCENES_BUCKET, f"{SID}.json")
    assert remote.get("published") is False
    assert len([x for x in remote["image_layers"] if x["key"].startswith("eclipse_glow_")]) == 4
    assert len(remote.get("cycles", [])) == 1
    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(remote, indent=2, ensure_ascii=False), encoding="utf-8")
    receipt = {
        "scene_id": SID,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "published": False,
        "catalog_version": catalog["version"],
        "revision": revision,
        "eclipse_frames": 4,
        "cycle_seconds": 3.6,
        "static_id": STATIC_ID,
        "static_hidden_verified": True,
        "preview_bytes": len(preview_body),
        "hidden_verified": True,
    }
    (QA / "ECLIPSE_TUNE_RECEIPT.json").write_text(
        json.dumps(receipt, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(receipt, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
