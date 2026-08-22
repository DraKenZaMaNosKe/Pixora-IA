"""Prepare the private Supergirl crystal-canyon parallax content pack.

The supplied fan-art reference is preserved as the character source because
model editing was unavailable.  OpenCV GrabCut separates the foreground; a
near crystal bed provides a natural occlusion for the source's cropped boots.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/supergirl_crystal_hope_parallax")
SOURCE = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/.codex-remote-attachments/019f7dd2-f7d2-76d2-ab01-5ae5829f6f3d/ec33d472-bf16-4d9a-b979-46ac6000977e/1-Photo-1.jpg")
BACKGROUND = Path(r"C:/Users/lalo/.codex/generated_images/019f7dd2-f7d2-76d2-ab01-5ae5829f6f3d/exec-af3f0ebc-d870-44e8-80b7-67e47ecba127.png")
NEW_BACKGROUND = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/.codex-remote-attachments/019f7dd2-f7d2-76d2-ab01-5ae5829f6f3d/771e9846-80ac-44d2-90c8-b00aa49519fa/1-Photo-1.jpg")
NEW_CHARACTER = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/.codex-remote-attachments/019f7dd2-f7d2-76d2-ab01-5ae5829f6f3d/771e9846-80ac-44d2-90c8-b00aa49519fa/2-Photo-2.jpg")
NEW_COMPOSITE = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/.codex-remote-attachments/019f7dd2-f7d2-76d2-ab01-5ae5829f6f3d/771e9846-80ac-44d2-90c8-b00aa49519fa/3-Photo-3.jpg")
W, H = 1080, 2340


def contain(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    out = img.copy()
    out.thumbnail(size, Image.Resampling.LANCZOS)
    return out


def cover(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    tw, th = size
    scale = max(tw / img.width, th / img.height)
    resized = img.resize((round(img.width * scale), round(img.height * scale)), Image.Resampling.LANCZOS)
    x = (resized.width - tw) // 2
    y = (resized.height - th) // 2
    return resized.crop((x, y, x + tw, y + th))


def grabcut_character(src_bgr: np.ndarray) -> np.ndarray:
    h, w = src_bgr.shape[:2]
    mask = np.full((h, w), cv2.GC_PR_BGD, np.uint8)
    # Confident background borders. Cape tips intentionally remain probable.
    mask[:18, :] = cv2.GC_BGD
    mask[:, :8] = cv2.GC_BGD
    mask[:, -8:] = cv2.GC_BGD

    # Broad silhouette: hair, cape, torso, arms, skirt, legs and boots.
    silhouette = np.array([
        [285, 38], [200, 85], [145, 190], [55, 320], [0, 405],
        [70, 525], [86, 680], [165, 770], [218, 970], [250, 1307],
        [610, 1307], [626, 1000], [675, 760], [665, 625], [736, 520],
        [736, 330], [620, 300], [560, 180], [500, 70], [390, 30],
    ], np.int32)
    cv2.fillPoly(mask, [silhouette], cv2.GC_PR_FGD)

    # Definite character seeds prevent blue costume from merging into canyon.
    seeds = [
        np.array([[290,70],[430,55],[500,190],[445,260],[265,250],[230,155]], np.int32),
        np.array([[235,245],[505,245],[570,560],[480,680],[235,670],[160,470]], np.int32),
        np.array([[260,610],[500,610],[585,835],[520,1070],[235,1070],[180,800]], np.int32),
        np.array([[250,970],[400,970],[400,1307],[245,1307]], np.int32),
        np.array([[420,940],[590,940],[610,1307],[420,1307]], np.int32),
    ]
    for poly in seeds:
        cv2.fillPoly(mask, [poly], cv2.GC_FGD)

    bgd = np.zeros((1, 65), np.float64)
    fgd = np.zeros((1, 65), np.float64)
    cv2.grabCut(src_bgr, mask, None, bgd, fgd, 10, cv2.GC_INIT_WITH_MASK)
    alpha = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
    # Hard silhouette guard: GrabCut tends to absorb similarly-blue canyon
    # pieces around the boots.  This union follows the actual body/cape while
    # still leaving GrabCut responsible for the fine hair and cloth edges.
    guard = np.zeros((h, w), np.uint8)
    parts = [
        [[220,35],[405,20],[545,105],[570,245],[475,315],[260,305],[185,175]],
        [[190,220],[505,215],[580,515],[540,760],[190,760],[120,500]],
        [[115,300],[255,255],[290,590],[215,735],[125,690],[60,450]],
        [[475,255],[585,270],[700,670],[620,735],[540,610],[500,420]],
        [[225,680],[390,680],[425,900],[408,1080],[395,1307],[238,1307],[250,1050],[225,850]],
        [[390,680],[565,680],[590,850],[570,1040],[610,1307],[425,1307],[415,1080],[405,900]],
        [[205,230],[55,300],[0,400],[80,535],[175,690],[300,565]],
        [[445,210],[610,255],[736,315],[736,530],[610,625],[485,530]],
    ]
    for pts in parts:
        cv2.fillPoly(guard, [np.asarray(pts, np.int32)], 255)
    alpha = cv2.bitwise_and(alpha, guard)
    alpha = cv2.morphologyEx(alpha, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8), iterations=2)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.8)
    return alpha


def make_shards(seed: int, near: bool) -> Image.Image:
    rng = np.random.default_rng(seed)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer, "RGBA")
    count = 10 if not near else 8
    for i in range(count):
        if near and i < 5:
            cx = int(rng.choice([rng.integers(40, 310), rng.integers(770, 1040)]))
            cy = int(rng.integers(1840, 2310))
            radius = int(rng.integers(85, 210))
        else:
            cx = int(rng.integers(30, 1050))
            cy = int(rng.integers(260, 2200))
            radius = int(rng.integers(13, 48) if not near else rng.integers(28, 78))
        n = int(rng.integers(4, 7))
        angles = np.sort(rng.random(n) * np.pi * 2)
        pts = []
        for a in angles:
            rr = radius * rng.uniform(0.5, 1.0)
            pts.append((cx + int(np.cos(a) * rr), cy + int(np.sin(a) * rr)))
        base = (18, 81, 143, 178) if i % 3 else (150, 88, 28, 185)
        draw.polygon(pts, fill=base, outline=(255, 195, 75, 150), width=max(1, radius // 28))
        if len(pts) >= 3:
            draw.line([pts[0], pts[2]], fill=(90, 225, 255, 190), width=max(1, radius // 24))
    return layer.filter(ImageFilter.GaussianBlur(0.35 if near else 0.15))


def make_foreground_ledge(bg: Image.Image) -> Image.Image:
    """Reuse the painted floor as a naturally integrated near occluder."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    floor = bg.convert("RGBA")
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    ridge = [(0, 1940), (150, 1905), (310, 1970), (455, 1918),
             (620, 1982), (785, 1928), (930, 1888), (1080, 1948),
             (1080, H), (0, H)]
    d.polygon(ridge, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.0))
    floor.putalpha(mask)
    layer.alpha_composite(floor)
    return layer


def radial_glow(center: tuple[int, int], radius: int, strength: float) -> Image.Image:
    yy, xx = np.ogrid[:H, :W]
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2)
    a = np.clip(1 - d / radius, 0, 1) ** 2 * 190 * strength
    arr = np.zeros((H, W, 4), np.uint8)
    arr[..., 0] = 255
    arr[..., 1] = 205
    arr[..., 2] = 82
    arr[..., 3] = a.astype(np.uint8)
    return Image.fromarray(arr, "RGBA").filter(ImageFilter.GaussianBlur(7))


def remove_white_background(img: Image.Image) -> Image.Image:
    """Build a soft alpha matte from Grok's near-white isolation canvas."""
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    dist = np.sqrt(np.sum((255.0 - rgb) ** 2, axis=2))
    alpha = np.clip((dist - 5.0) / 34.0 * 255.0, 0, 255).astype(np.uint8)
    # Do not flood-fill the silhouette: the white gaps between individual hair
    # curls and cape ribbons are real background and must remain transparent.
    alpha = cv2.erode(alpha, np.ones((3, 3), np.uint8), iterations=1)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.35)
    # Remove the white matte baked into antialiased edge pixels. Convert from
    # white-composited RGB back to straight-alpha foreground color.
    a = alpha.astype(np.float32) / 255.0
    safe = np.maximum(a[..., None], 0.035)
    clean_rgb = (rgb - 255.0 * (1.0 - a[..., None])) / safe
    clean_rgb = np.clip(clean_rgb, 0, 255)
    clean_rgb[a < 0.035] = 0
    clean_rgb[a > 0.985] = rgb[a > 0.985]
    rgba = np.dstack([clean_rgb.astype(np.uint8), alpha])
    return Image.fromarray(rgba, "RGBA")


def main() -> None:
    for name in ("sources", "layers", "production", "qa"):
        (ROOT / name).mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE, ROOT / "sources" / "reference_supergirl.jpg")
    shutil.copy2(NEW_BACKGROUND, ROOT / "sources" / "grok_background_clean.jpg")
    shutil.copy2(NEW_CHARACTER, ROOT / "sources" / "grok_supergirl_fullbody_white.jpg")
    shutil.copy2(NEW_COMPOSITE, ROOT / "sources" / "grok_composite_guide.jpg")

    bg = cover(Image.open(NEW_BACKGROUND).convert("RGB"), (W, H))
    bg.save(ROOT / "layers" / "background_crystal_canyon.png", quality=95)

    char_canvas = cover(Image.open(NEW_CHARACTER).convert("RGB"), (W, H))
    char = remove_white_background(char_canvas)
    char.save(ROOT / "layers" / "supergirl_fullbody.png")
    char.getchannel("A").save(ROOT / "qa" / "character_mask.png")

    # Remove rejected extraction artifacts from older local drafts. They are
    # deliberately excluded from the hybrid scene and must not confuse review.
    for stale in (
        ROOT / "layers" / "supergirl_fullbody_occluded.png",
        ROOT / "layers" / "crystal_shards_far.png",
        ROOT / "layers" / "crystal_foreground_ledge.png",
        ROOT / "layers" / "background_reference_composite.png",
    ):
        stale.unlink(missing_ok=True)

    # Emblem location after cover-fit of the supplied full-body canvas.
    for i, strength in enumerate((0.35, 0.72, 1.0, 0.68)):
        radial_glow((540, 920), 165 + i * 8, strength).save(ROOT / "layers" / f"emblem_glow_{i}.png")

    # Use Grok's integrated composition for the catalog/static fallback.
    flat = cover(Image.open(NEW_COMPOSITE).convert("RGB"), (W, H)).convert("RGBA")
    qa_master = bg.convert("RGBA")
    qa_master.alpha_composite(char)
    qa_master.alpha_composite(radial_glow((540, 920), 180, 0.55))
    qa_master.convert("RGB").save(ROOT / "qa" / "QA_master.jpg", quality=92)
    flat.convert("RGB").save(ROOT / "production" / "supergirl_crystal_hope_parallax.webp", "WEBP", quality=91, method=6)
    preview = flat.convert("RGB").resize((540, 1170), Image.Resampling.LANCZOS)
    preview.save(ROOT / "production" / "preview.jpg", quality=91)

    spec = {
        "schema_version": 1,
        "id": "supergirl_crystal_hope_parallax",
        "type": "canvas_scene",
        "published": False,
        "title": {"es": "Supergirl · Esperanza de Krypton", "en": "Supergirl · Hope of Krypton"},
        "category": "comics",
        "image_layers": [
            {"key":"background","file":"layers/background_crystal_canyon.png","z":0,"parallax_factor":0.10,"scale":1.10},
            {"key":"supergirl","file":"layers/supergirl_fullbody.png","z":10,"parallax_factor":0.62,"scale":1.0},
            *[{"key":f"emblem_glow_{i}","file":f"layers/emblem_glow_{i}.png","z":13,"parallax_factor":0.62,"scale":1.0,"initial_alpha":1.0 if i==0 else 0.0,"bob_amplitude_px":3.5,"bob_period_sec":5.8,"bob_phase_source":"supergirl"} for i in range(4)],
        ],
        "cycles": [{"name":"emblem_pulse","duration_s":4.8,"frames":[
            {"layer_key":"emblem_glow_0","from_s":0.0,"to_s":1.2},
            {"layer_key":"emblem_glow_1","from_s":1.2,"to_s":2.4},
            {"layer_key":"emblem_glow_2","from_s":2.4,"to_s":3.2},
            {"layer_key":"emblem_glow_3","from_s":3.2,"to_s":4.0},
            {"layer_key":"emblem_glow_0","from_s":4.0,"to_s":4.8},
        ]}],
        "particles": [{"kind":"motes","params":{"count":18,"speed":0.12,"color":"#79E7FF","min_size":1.0,"max_size":3.2}}],
    }
    (ROOT / "SCENE_SPEC_DRAFT.json").write_text(json.dumps(spec, ensure_ascii=False, indent=2), encoding="utf-8")

    metadata = """# Supergirl · Esperanza de Krypton

## Descripción de la escena

Kara Zor-El avanza entre los restos de un cañón cristalino alienígena. Los fragmentos azules y dorados suspendidos sugieren que acaba de atravesar una barrera, mientras el emblema de su pecho pulsa como símbolo de esperanza. La composición es fan art y no representa una escena canónica específica.

## Personaje y origen

Supergirl es Kara Zor-El, prima de Kal-El/Superman y superviviente de Krypton. Fue creada por Otto Binder y Al Plastino y su encarnación moderna debutó en *Action Comics #252* (1959). Según la continuidad, fue enviada para proteger a su primo, pero llegó a la Tierra después que él debido a que su nave se retrasó.

## Poderes y personalidad

Bajo un sol amarillo posee fuerza, velocidad, vuelo, invulnerabilidad, visión calorífica, visión de rayos X, superoído y aliento helado. Kara suele combinar determinación, compasión y un vínculo más directo con la cultura kryptoniana que Superman, porque vivió parte de su infancia en Krypton.

## Papel y adaptaciones

Ha formado parte de la Familia Superman y de equipos como la Legión de Superhéroes. También ha aparecido en cómics, animación, cine y televisión. La película *Supergirl* de 1984 fue protagonizada por Helen Slater; la serie televisiva de 2015–2021 tuvo a Melissa Benoist; Sasha Calle interpretó una variante en *The Flash* (2023); y Milly Alcock encarnó a Kara en *Supergirl* (2026), dirigida por Craig Gillespie y escrita por Ana Nogueira.

## Lectura visual

El azul comunica herencia kryptoniana y serenidad; el rojo concentra fuerza y determinación; el oro de las fracturas añade una sensación de renacimiento. El espacio despejado superior ayuda a que los iconos del teléfono permanezcan legibles.

## Nota editorial

Contenido visual presentado como fan art. Los personajes y marcas pertenecen a sus respectivos titulares. Texto informativo redactado para Pixora IA.

## Fuentes editoriales consultadas

- DC, ficha oficial del personaje: https://www.dc.com/characters/supergirl
- DC, evolución del origen: https://www.dc.com/blog/2026-06-17/the-evolution-of-supergirl-s-origin
- DC, ficha oficial de *Supergirl* (2026): https://www.dc.com/movies/supergirl-2026
"""
    (ROOT / "METADATA_DESCRIPCION.md").write_text(metadata, encoding="utf-8")
    (ROOT / "README.txt").write_text(
        "Private review pack. Open demo.html or load scene id supergirl_crystal_hope_parallax in Pixel Studio.\n"
        "Do not publish until Huawei and Samsung validation is approved.\n",
        encoding="utf-8",
    )

    demo = """<!doctype html><meta charset='utf-8'><title>Supergirl Crystal Hope</title>
<style>body{margin:0;background:#050b16;color:white;font-family:system-ui;display:grid;place-items:center;min-height:100vh}.phone{position:relative;width:360px;height:780px;overflow:hidden;border-radius:30px;box-shadow:0 0 40px #39c6ff;background:#000}.phone img{position:absolute;width:100%;height:100%;object-fit:cover}.far{animation:far 8s ease-in-out infinite}.hero{animation:hero 5.6s ease-in-out infinite}.near{animation:near 7s ease-in-out infinite}.glow{animation:pulse 2.4s ease-in-out infinite}@keyframes far{50%{transform:translate(3px,-2px)}}@keyframes hero{50%{transform:translate(-6px,-4px)}}@keyframes near{50%{transform:translate(10px,5px) scale(1.01)}}@keyframes pulse{50%{opacity:.28;transform:scale(.99)}}</style>
<div class='phone'><img class='far' src='layers/background_crystal_canyon.png'><img class='hero' src='layers/supergirl_fullbody.png'><img class='hero glow' src='layers/emblem_glow_2.png'></div>"""
    (ROOT / "demo.html").write_text(demo, encoding="utf-8")
    print(ROOT)


if __name__ == "__main__":
    main()
