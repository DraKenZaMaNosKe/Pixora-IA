"""Generalized canvas_scene uploader for the ia_contenido_pipeline.

Reads a scene config (dict) and does the full upload:
  - cover-fit + webp encode background, character layer(s), flat static, preview
  - upload assets to Storage (wallpaper-images)
  - build canonical canvas_scene spec (image_layers + particles + cycles + sprites)
  - upload spec JSON (wallpaper-scenes)
  - upsert catalog_index.json entry (with `published` flag)
  - insert/replace row in Postgres wallpapers (published flag)

Designed for the Codex handoff: each scene folder in
  ia_contenido_pipeline/wallpapers/1_por_editar/<scene>/
has a SCENE_SPEC_V2_DRAFT.json + METADATA. We pass the extracted params here.

Upload HIDDEN by default (published=False) so Eduardo reviews / sprite-edits in
the darkroom, then flips visible.
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"
TARGET = (1080, 2340)

SK = re.findall(
    r"eyJ[A-Za-z0-9_\-\.]{100,500}",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
)[0]


def put(bucket, remote, body, ct="image/webp"):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}", data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("apikey", SK)
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "no-cache, max-age=0")
    with urllib.request.urlopen(req, timeout=180) as r:
        print(f"    PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


def put_json(bucket, remote, data):
    put(bucket, remote, json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8"),
        "application/json")


def get_json(bucket, remote):
    # Unique cache-bust per read — a FIXED param let the CDN serve a stale
    # catalog and back-to-back uploads clobbered each other's entries.
    import time
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}?nc={time.time()}"
    req = urllib.request.Request(url)
    req.add_header("Cache-Control", "no-cache")
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def _cover(img, keep_alpha):
    tw, th = TARGET
    src = img.convert("RGBA")
    sw, sh = src.size
    scale = max(tw / sw, th / sh)
    nw, nh = int(round(sw * scale)), int(round(sh * scale))
    resized = src.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    cropped = resized.crop((left, top, left + tw, top + th))
    if keep_alpha:
        return cropped
    out = Image.new("RGB", TARGET, (0, 0, 0))
    out.paste(cropped, mask=cropped.split()[3])
    return out


def _webp(img, quality):
    import io
    buf = io.BytesIO()
    img.save(buf, "WEBP", quality=quality, method=6)
    return buf.getvalue()


def upload_scene(cfg):
    sid = cfg["scene_id"]
    src = Path(cfg["src_dir"])
    print("=" * 60)
    print(f"Upload scene: {sid}   (published={cfg.get('published', False)})")
    print("=" * 60)

    def u(name):
        return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{name}"

    # --- bake assets ---
    print("[1/5] Baking assets (cover-fit 1080x2340 + webp)...")
    bg = _cover(Image.open(src / cfg["background_file"]), keep_alpha=False)
    bg_body = _webp(bg, 88)

    layer_bodies = {}
    for L in cfg["layers"]:
        im = _cover(Image.open(src / L["file"]), keep_alpha=True)
        layer_bodies[L["key"]] = _webp(im, 92)

    flat = _cover(Image.open(src / cfg["static_file"]), keep_alpha=False)
    flat_body = _webp(flat, 88)
    prev = flat.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev_body = _webp(prev, 85)

    # --- revision (bump if scene already exists) ---
    try:
        existing = get_json(SCENES_BUCKET, f"{sid}.json")
        rev = max((int(l.get("revision", 1)) for l in existing.get("image_layers", [])), default=1) + 1
    except Exception:
        rev = 1
    print(f"    revision -> {rev}")

    # --- upload assets ---
    print("[2/5] Uploading to Storage...")
    put(IMG_BUCKET, f"{sid}_background.webp", bg_body)
    for key, body in layer_bodies.items():
        put(IMG_BUCKET, f"{sid}_{key}.webp", body)
    put(IMG_BUCKET, f"{sid}.webp", flat_body)
    put(IMG_BUCKET, f"{sid}_preview.webp", prev_body)

    url_flat = u(f"{sid}.webp")
    url_prev = u(f"{sid}_preview.webp")

    # --- build canonical canvas_scene spec ---
    print("[3/5] Building canvas_scene spec...")
    bgc = cfg["bg"]
    image_layers = [{
        "key": "background", "url": u(f"{sid}_background.webp"), "z": bgc.get("z", 0),
        "parallax_factor": bgc.get("parallax", 0.10), "scroll_factor": 0.0,
        "scale": bgc.get("scale", 1.08), "offset_x_px": 0, "offset_y_px": 0, "revision": rev,
    }]
    for L in cfg["layers"]:
        layer = {
            "key": L["key"], "url": u(f"{sid}_{L['key']}.webp"), "z": L.get("z", 10),
            "parallax_factor": L.get("parallax", 0.6), "scroll_factor": 0.0,
            "scale": L.get("scale", 1.0), "offset_x_px": 0, "offset_y_px": 0, "revision": rev,
        }
        if L.get("bob"):
            layer["bob_amplitude_px"] = L["bob"][0]
            layer["bob_period_sec"] = L["bob"][1]
        image_layers.append(layer)

    spec = {
        "schema_version": 1, "id": sid, "type": "canvas_scene",
        "title": cfg["title"], "tags": cfg["tags"],
        "category": cfg.get("category_semantic", "scenes"),
        "featured": cfg.get("featured", False),
        "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
        "image_layers": image_layers,
        "cycles": cfg.get("cycles", []),
        "sprites": cfg.get("sprites", []),
        "particles": cfg.get("particles", []),
        "events": [],
    }
    put_json(SCENES_BUCKET, f"{sid}.json", spec)

    # --- catalog_index ---
    print("[4/5] Updating catalog_index...")
    try:
        cat = get_json(IMG_BUCKET, "catalog_index.json")
    except Exception:
        cat = {"version": 0, "items": []}
    cat["version"] = (cat.get("version", 0) or 0) + 1
    entry = {
        "id": sid, "type": "canvas_scene", "schema": 1, "title": cfg["title"],
        "preview_url": url_prev, "image_url": url_flat, "tags": cfg["tags"],
        "category": cfg.get("category_semantic", "scenes"),
        "featured": cfg.get("featured", False), "glow_color": cfg["glow"],
        "published": bool(cfg.get("published", False)),
        "description": cfg.get("desc_plain", ""),
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{sid}.json",
    }
    items = [it for it in cat.get("items", []) if it.get("id") != sid]
    items.insert(0, entry)
    cat["items"] = items
    put_json(IMG_BUCKET, "catalog_index.json", cat)

    # --- Postgres ---
    print("[5/5] Registering in Postgres...")
    from apply_migration import connect
    conn = connect()
    cur = conn.cursor()
    cur.execute("DELETE FROM wallpapers WHERE id = %s;", (sid,))
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    sort = cur.fetchone()[0]
    cur.execute(
        """
        INSERT INTO wallpapers (
            id, name, description, description_rich, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, %s, 'static'::wallpaper_type, 'SCENES'::wallpaper_category, %s,
            %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, %s, 0,
            %s, false, %s, %s, %s
        ) RETURNING id, published;
        """,
        (sid, cfg["name"], cfg.get("desc_plain", ""), cfg.get("desc_rich"),
         cfg["tags"], f"{sid}.webp", f"{sid}_preview.webp", len(flat_body), len(prev_body),
         cfg["glow"], sort, cfg.get("featured", False),
         bool(cfg.get("published", False)), "Pixora Studio", TARGET[0], TARGET[1]),
    )
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    print(f"    Postgres row: id={row[0]} published={row[1]}")
    print(f"DONE — {sid}  (spec + catalog v{cat['version']} + postgres)")
    print("=" * 60)
    return {"scene_id": sid, "revision": rev, "catalog_version": cat["version"]}


# ── Config de cammy (escena de prueba) ────────────────────────────────────
if __name__ == "__main__":
    BASE = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar")
    cammy = {
        "scene_id": "cammy_sf_parallax",
        "src_dir": str(BASE / "cammy_streetfighter"),
        "background_file": "cm_solofondo_v2.png",
        "bg": {"z": 0, "parallax": 0.10, "scale": 1.05},
        "layers": [
            {"key": "cammy", "file": "cm_personaje_v2_clean_final.png", "z": 10,
             "parallax": 0.72, "scale": 1.0, "bob": [3.0, 5.5]},
        ],
        "static_file": "cm_wallpaper_estatico_v2_final.png",
        "particles": [{"kind": "embers", "params": {
            "count": 22, "speed": 0.32, "color": "#FF8A24", "min_size": 1.0, "max_size": 3.5}}],
        "cycles": [], "sprites": [],
        "title": {"es": "Cammy", "en": "Cammy"},
        "tags": ["cammy", "streetfighter", "sf", "delta red", "pelea", "kick",
                 "anime", "parallax", "capcom", "accion", "gaming"],
        "category_semantic": "gaming",
        "glow": "#FF4500",
        "name": "Cammy",
        "desc_plain": "Beret azul, trenza y patada de fuego. Delta Red no pide permiso.",
        "desc_rich": None,
        "featured": False,
        "published": False,   # OCULTO — Eduardo revisa/edita sprites, luego visible
    }
    upload_scene(cammy)
