"""Prepara la revision privada V2 de Supergirl con fragmentos en tiempo lento."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter


SRC = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/"
    r"wallpapers/1_por_editar/supergirl_crystal_hope_parallax"
)
DST = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/"
    r"wallpapers/1_por_editar/supergirl_crystal_hope_parallax_v2"
)


def split_shards() -> list[dict]:
    source = np.array(Image.open(SRC / "layers/crystal_shards_near.png").convert("RGBA"))
    mask = (source[:, :, 3] > 8).astype(np.uint8)
    count, labels, stats, centers = cv2.connectedComponentsWithStats(mask, 8)
    components = []
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < 12:
            continue
        components.append({
            "label": label,
            "area": area,
            "cx": float(centers[label][0]),
            "cy": float(centers[label][1]),
        })

    # Reparto espacial determinista: mantiene fragmentos por toda la pantalla
    # y reserva los componentes mayores para el plano cercano.
    components.sort(key=lambda c: (c["area"], c["cy"]), reverse=True)
    groups = {"far": [], "mid": [], "near": []}
    for index, component in enumerate(components):
        if index < 3:
            key = "near"
        elif index < 7:
            key = "mid"
        else:
            key = "far"
        groups[key].append(component)

    report = []
    for key, members in groups.items():
        layer = np.zeros_like(source)
        wanted = {item["label"] for item in members}
        keep = np.isin(labels, list(wanted))
        layer[keep] = source[keep]
        path = DST / "layers" / f"shards_{key}_slowmo.png"
        Image.fromarray(layer, "RGBA").save(path, optimize=True)
        report.append({
            "layer": key,
            "components": len(members),
            "pixels": int(np.count_nonzero(layer[:, :, 3])),
            "file": str(path),
        })
    return report


def build_cinematic_effects() -> list[dict]:
    size = (1080, 2340)
    effects = []

    # Luz volumétrica detrás de Kara: polígonos suaves que nacen en la
    # abertura del cañón y se abren hacia el tercio inferior.
    rays = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(rays, "RGBA")
    for points, color in (
        ([(470, 0), (555, 0), (790, 1900), (580, 1850)], (86, 225, 255, 42)),
        ([(575, 0), (625, 0), (920, 1770), (735, 1820)], (105, 195, 255, 27)),
        ([(350, 0), (405, 0), (355, 1700), (180, 1650)], (70, 214, 255, 22)),
    ):
        draw.polygon(points, fill=color)
    rays = rays.filter(ImageFilter.GaussianBlur(32))
    rays.save(DST / "layers/krypton_light_rays.png", optimize=True)
    effects.append({"layer": "krypton_light_rays", "kind": "volumetric_light"})

    # Onda de energía alrededor del emblema. Tres tamaños forman un pulso
    # discreto; no tapa el rostro ni la silueta del personaje.
    cx, cy = 540, 920
    for index, (rx, ry, alpha, width) in enumerate(
        ((145, 105, 115, 10), (188, 138, 76, 8), (235, 175, 38, 6))
    ):
        ring = Image.new("RGBA", size, (0, 0, 0, 0))
        rd = ImageDraw.Draw(ring, "RGBA")
        box = (cx - rx, cy - ry, cx + rx, cy + ry)
        rd.ellipse(box, outline=(102, 235, 255, alpha), width=width)
        rd.ellipse(
            (box[0] - 8, box[1] - 8, box[2] + 8, box[3] + 8),
            outline=(255, 219, 96, alpha // 2), width=max(3, width // 2),
        )
        ring = ring.filter(ImageFilter.GaussianBlur(5 + index * 2))
        ring.save(DST / "layers" / f"energy_wave_{index}.png", optimize=True)
        effects.append({"layer": f"energy_wave_{index}", "kind": "emblem_wave"})

    # Reflejos móviles sobre cabello y capa. Son luz semitransparente, no una
    # copia del cuerpo: al oscilar no dejan extremidades duplicadas.
    hero = np.array(Image.open(SRC / "layers/supergirl_fullbody.png").convert("RGBA"))
    rgb = hero[:, :, :3]
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    alpha = hero[:, :, 3]
    yy = np.indices(alpha.shape)[0]
    xx = np.indices(alpha.shape)[1]

    hair_mask = (
        (hsv[:, :, 0] >= 8) & (hsv[:, :, 0] <= 38) &
        (hsv[:, :, 1] >= 35) & (hsv[:, :, 2] >= 115) &
        (yy < 900) & (alpha > 20)
    ).astype(np.uint8) * 255
    cape_mask = (
        (((hsv[:, :, 0] <= 10) | (hsv[:, :, 0] >= 168)) &
         (hsv[:, :, 1] >= 75) & (hsv[:, :, 2] >= 65) &
         (yy > 380) & (yy < 1100) &
         ((xx < 365) | (xx > 715)) & (alpha > 20))
    ).astype(np.uint8) * 255

    for key, mask, color in (
        ("hair_wind_glint", hair_mask, (255, 230, 142)),
        ("cape_wind_glint", cape_mask, (255, 92, 112)),
    ):
        edge = cv2.Canny(mask, 40, 110)
        edge = cv2.dilate(edge, np.ones((3, 3), np.uint8), iterations=1)
        edge = cv2.GaussianBlur(edge, (0, 0), 3.2)
        layer = np.zeros((*mask.shape, 4), dtype=np.uint8)
        layer[:, :, 0] = color[0]
        layer[:, :, 1] = color[1]
        layer[:, :, 2] = color[2]
        layer[:, :, 3] = (edge.astype(np.float32) * 0.42).astype(np.uint8)
        Image.fromarray(layer, "RGBA").save(DST / "layers" / f"{key}.png", optimize=True)
        effects.append({"layer": key, "kind": "moving_highlight"})

    return effects


def main() -> None:
    (DST / "layers").mkdir(parents=True, exist_ok=True)
    (DST / "production").mkdir(parents=True, exist_ok=True)
    (DST / "qa").mkdir(parents=True, exist_ok=True)

    for name in (
        "background_crystal_canyon.png",
        "supergirl_fullbody.png",
        "emblem_glow_0.png",
        "emblem_glow_1.png",
        "emblem_glow_2.png",
        "emblem_glow_3.png",
    ):
        shutil.copy2(SRC / "layers" / name, DST / "layers" / name)

    shutil.copy2(
        SRC / "production" / "supergirl_crystal_hope_parallax.webp",
        DST / "production" / "supergirl_crystal_hope_parallax_v2.webp",
    )
    for optional in ("METADATA_DESCRIPCION.md", "README.md"):
        if (SRC / optional).exists():
            shutil.copy2(SRC / optional, DST / optional)

    report = {
        "scene_id": "supergirl_crystal_hope_parallax_v2",
        "source_scene": "supergirl_crystal_hope_parallax",
        "effect": "fragmentos suspendidos en tiempo lento con tres profundidades",
        "shard_layers": split_shards(),
        "cinematic_effects": build_cinematic_effects(),
    }
    (DST / "PREPARATION_REPORT.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
