"""Add a moonlight pulse and living stars to the hidden Sailor scene."""
import io
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, get_json, put, put_json

SID = "sailor_moon_tuxedo_eclipse_depth"
STATIC_ID = "sailor_moon_tuxedo_eclipse_static"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/sailor_moon_tuxedo_eclipse_20260824")
MASTER = ROOT / "production/sailor_moon_tuxedo_eclipse_1080x2340.png"
SPRITES = ROOT / "sprites"
QA = ROOT / "qa"
SIZE = (1080, 2340)
PHASES = (0.32, 0.58, 1.0, 0.58)
STARS = [(76, 305), (149, 226), (562, 231), (694, 278), (936, 154), (1004, 334)]


def public_url(name):
    return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{name}"


def encode(image, quality):
    out = io.BytesIO(); image.save(out, "WEBP", quality=quality, method=6); return out.getvalue()


def make_frame(index, intensity):
    frame = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    glow = Image.new("RGBA", SIZE, (0, 0, 0, 0)); draw = ImageDraw.Draw(glow)
    for radius, alpha in ((320, 8), (250, 14), (190, 24)):
        draw.ellipse((765-radius, 315-radius, 765+radius, 315+radius), fill=(224, 239, 255, int(alpha*intensity)))
    glow = glow.filter(ImageFilter.GaussianBlur(42))
    frame = Image.alpha_composite(frame, glow)
    stars = Image.new("RGBA", SIZE, (0, 0, 0, 0)); sd = ImageDraw.Draw(stars)
    for n, (x, y) in enumerate(STARS):
        strength = intensity if (n + index) % 2 == 0 else 1.25 - intensity * 0.5
        alpha = int(185 * max(0.25, min(1.0, strength)))
        radius = 3 + (n % 3)
        sd.line((x-radius*3, y, x+radius*3, y), fill=(205, 228, 255, alpha), width=2)
        sd.line((x, y-radius*3, x, y+radius*3), fill=(255, 244, 199, alpha), width=2)
        sd.ellipse((x-radius, y-radius, x+radius, y+radius), fill=(255, 255, 245, alpha))
    stars = stars.filter(ImageFilter.GaussianBlur(0.7))
    frame = Image.alpha_composite(frame, stars)
    path = SPRITES / f"moonlight_{index}.webp"; frame.save(path, "WEBP", lossless=True, method=6); return path


def main():
    SPRITES.mkdir(parents=True, exist_ok=True); QA.mkdir(parents=True, exist_ok=True)
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    if spec.get("published") is not False:
        raise RuntimeError("Safety stop: Sailor scene must remain hidden while tuning")
    with Image.open(MASTER) as source:
        rgb = source.convert("RGB")
        if rgb.size != SIZE: raise RuntimeError(f"Unexpected master dimensions: {rgb.size}")
        static_body = encode(rgb, 88)
        preview = rgb.resize((540, 1170), Image.Resampling.LANCZOS)
        for quality in (24, 18, 14, 10):
            preview_body = encode(preview, quality)
            if len(preview_body) < 50_000: break
        if len(preview_body) >= 50_000: raise RuntimeError(f"Preview exceeds 50 KB: {len(preview_body)}")
    for key in (SID, STATIC_ID):
        put(IMG_BUCKET, f"{key}.webp", static_body); put(IMG_BUCKET, f"{key}_preview.webp", preview_body)

    layers = [layer for layer in spec.get("image_layers", []) if not layer.get("key", "").startswith("moonlight_")]
    revision = max(int(layer.get("revision", 1)) for layer in layers) + 1
    for layer in layers: layer["revision"] = revision
    for index, intensity in enumerate(PHASES):
        path = make_frame(index, intensity); remote = f"{SID}_moonlight_{index}.webp"; put(IMG_BUCKET, remote, path.read_bytes())
        layers.append({"key": f"moonlight_{index}", "url": public_url(remote), "z": 2,
                       "parallax_factor": 0.014, "scroll_factor": 0.0, "scale": 1.26,
                       "offset_x_px": 0, "offset_y_px": 0, "initial_alpha": 1.0 if index == 0 else 0.0,
                       "revision": revision})
    spec["image_layers"] = layers
    spec["cycles"] = [{"name": "moonlight_breath", "duration_s": 4.8,
                       "frames": [{"layer_key": f"moonlight_{i}", "from_s": i*1.2, "to_s": (i+1)*1.2} for i in range(4)]}]
    spec["published"] = False; put_json(SCENES_BUCKET, f"{SID}.json", spec)
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1 or matches[0].get("published") is not False: raise RuntimeError("Hidden catalog entry not found")
    catalog["version"] = int(catalog.get("version", 0)) + 1; put_json(IMG_BUCKET, "catalog_index.json", catalog)

    from apply_migration import connect
    conn = connect(); cur = conn.cursor()
    cur.execute("UPDATE wallpapers SET image_size=%s,preview_size=%s WHERE id=%s AND published=false", (len(static_body), len(preview_body), SID))
    if cur.rowcount != 1: raise RuntimeError("Hidden canvas row not found")
    cur.execute("SELECT COALESCE(MAX(sort_order),0)+1 FROM wallpapers"); sort_order = cur.fetchone()[0]
    cur.execute("""INSERT INTO wallpapers (id,name,description,type,category,tags,image_path,preview_path,image_size,preview_size,glow_color,badge,sort_order,featured,trending_score,published,daily_eligible,author_name,media_width,media_height)
        VALUES (%s,%s,%s,'static'::wallpaper_type,'ANIME'::wallpaper_category,%s,%s,%s,%s,%s,'#C9DFFF','NEW'::wallpaper_badge,%s,false,0,false,false,'Pixora Studio',1080,2340)
        ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,tags=EXCLUDED.tags,image_path=EXCLUDED.image_path,preview_path=EXCLUDED.preview_path,image_size=EXCLUDED.image_size,preview_size=EXCLUDED.preview_size,glow_color=EXCLUDED.glow_color,published=false,updated_at=now()""",
        (STATIC_ID, "Promesa bajo la Luna", "Sailor Moon y Tuxedo Mask protegen el Reino Lunar bajo un cielo vivo.",
         ["sailor moon","tuxedo mask","anime","fan art","luna","romance","magia"], f"{STATIC_ID}.webp", f"{STATIC_ID}_preview.webp", len(static_body), len(preview_body), sort_order))
    conn.commit(); cur.close(); conn.close()
    remote = get_json(SCENES_BUCKET, f"{SID}.json")
    (ROOT/"SCENE_SPEC_QA.json").write_text(json.dumps(remote, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    receipt = {"scene_id": SID, "updated_at": datetime.now(timezone.utc).isoformat(), "published": False,
               "catalog_version": catalog["version"], "revision": revision, "moonlight_frames": 4,
               "cycle_seconds": 4.8, "static_id": STATIC_ID, "preview_bytes": len(preview_body), "hidden_verified": True}
    (QA/"MOONLIGHT_TUNE_RECEIPT.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__": main()
