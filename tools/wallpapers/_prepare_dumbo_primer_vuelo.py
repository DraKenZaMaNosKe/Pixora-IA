"""Prepara el paquete privado de Dumbo a partir del fondo y compuesto aportados."""
from __future__ import annotations

import json
import math
import shutil
import zipfile
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter


SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/.codex-remote-attachments/019f7dd2-f7d2-76d2-ab01-5ae5829f6f3d/f1c73b49-d90e-4bce-a3e1-5fa94c97e5c1")
BG_SRC = SRC / "1-Photo-1.jpg"
COMP_SRC = SRC / "2-Photo-2.jpg"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/dumbo_primer_vuelo")


def extract_character() -> Image.Image:
    bg = cv2.imread(str(BG_SRC), cv2.IMREAD_COLOR)
    comp = cv2.imread(str(COMP_SRC), cv2.IMREAD_COLOR)
    if bg is None or comp is None:
        raise RuntimeError("No se pudieron leer las referencias")
    if bg.shape != comp.shape:
        bg = cv2.resize(bg, (comp.shape[1], comp.shape[0]), interpolation=cv2.INTER_LANCZOS4)
    diff = cv2.cvtColor(cv2.absdiff(comp, bg), cv2.COLOR_BGR2GRAY)
    seed = np.where(diff > 18, 255, 0).astype(np.uint8)
    seed = cv2.morphologyEx(seed, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(seed, 8)
    if count < 2:
        raise RuntimeError("No se detectó el personaje")
    best = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    component = labels == best
    x, y, w, h, _ = stats[best]
    grab = np.full(diff.shape, cv2.GC_BGD, dtype=np.uint8)
    grab[y:y+h, x:x+w] = cv2.GC_PR_BGD
    grab[component & (diff > 18)] = cv2.GC_PR_FGD
    grab[component & (diff > 55)] = cv2.GC_FGD
    # El compuesto original trae un glow crema grueso. Márquese como fondo
    # solo cuando está cerca del borde exterior; así no se dañan ojos, sombrero
    # ni reflejos internos del personaje.
    hsv = cv2.cvtColor(comp, cv2.COLOR_BGR2HSV)
    distance = cv2.distanceTransform(component.astype(np.uint8), cv2.DIST_L2, 5)
    outer_glow = component & (distance < 24) & (hsv[:, :, 1] < 82) & (hsv[:, :, 2] > 198)
    grab[outer_glow] = cv2.GC_BGD
    bg_model = np.zeros((1, 65), np.float64)
    fg_model = np.zeros((1, 65), np.float64)
    cv2.grabCut(comp, grab, None, bg_model, fg_model, 5, cv2.GC_INIT_WITH_MASK)
    mask = np.where((grab == cv2.GC_FGD) | (grab == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    # Contracción mínima + feather neutro para un contorno integrado, no una
    # calcomanía luminosa.
    mask = cv2.erode(mask, np.ones((3, 3), np.uint8), iterations=1)
    alpha = Image.fromarray(mask, "L").filter(ImageFilter.GaussianBlur(0.55))
    rgba = Image.open(COMP_SRC).convert("RGBA")
    rgba.putalpha(alpha)
    bbox = alpha.getbbox()
    if not bbox:
        raise RuntimeError("Recorte vacío")
    x0, y0, x1, y1 = bbox
    pad = 20
    return rgba.crop((max(0, x0-pad), max(0, y0-pad), min(rgba.width, x1+pad), min(rgba.height, y1+pad)))


def main() -> None:
    for folder in ("source", "layers", "frames", "production", "qa", "metadata"):
        (ROOT / folder).mkdir(parents=True, exist_ok=True)
    shutil.copy2(BG_SRC, ROOT / "source" / BG_SRC.name)
    shutil.copy2(COMP_SRC, ROOT / "source" / COMP_SRC.name)

    character = extract_character()
    character.thumbnail((390, 390), Image.Resampling.LANCZOS)
    character.save(ROOT / "layers" / "dumbo_cutout.png", optimize=True)

    canvas = (480, 480)
    frames: list[Image.Image] = []
    for i in range(12):
        phase = i / 12 * math.tau
        angle = math.sin(phase) * 2.2
        scale = 1.0 + math.sin(phase + math.pi / 2) * 0.018
        w = max(1, round(character.width * scale))
        h = max(1, round(character.height * scale))
        pose = character.resize((w, h), Image.Resampling.LANCZOS)
        pose = pose.rotate(angle, Image.Resampling.BICUBIC, expand=True)
        frame = Image.new("RGBA", canvas, (0, 0, 0, 0))
        x = (canvas[0] - pose.width) // 2 + round(math.sin(phase) * 5)
        y = (canvas[1] - pose.height) // 2 + round(math.sin(phase * 2) * 4)
        frame.alpha_composite(pose, (x, y))
        frames.append(frame)

    frame_dir = ROOT / "frames"
    for old in frame_dir.glob("frame_*.png"):
        old.unlink()
    for i, frame in enumerate(frames, 1):
        frame.save(frame_dir / f"frame_{i:03d}.png", optimize=True)
    zip_path = ROOT / "production" / "dumbo_primer_vuelo_sprite.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for frame in sorted(frame_dir.glob("frame_*.png")):
            zf.write(frame, frame.name)

    bg = Image.open(BG_SRC).convert("RGB")
    scale = max(1080 / bg.width, 2340 / bg.height)
    bg = bg.resize((round(bg.width * scale), round(bg.height * scale)), Image.Resampling.LANCZOS)
    left = (bg.width - 1080) // 2
    top = (bg.height - 2340) // 2
    flat = bg.crop((left, top, left + 1080, top + 2340)).convert("RGBA")
    hero = character.copy()
    hero.thumbnail((760, 760), Image.Resampling.LANCZOS)
    flat.alpha_composite(hero, ((1080 - hero.width)//2, 790))
    flat.convert("RGB").save(ROOT / "production" / "dumbo_primer_vuelo_flat.jpg", quality=94)

    report = {
        "scene_id": "dumbo_primer_vuelo",
        "frames": len(frames),
        "frame_canvas": list(canvas),
        "sprite_zip_bytes": zip_path.stat().st_size,
        "character_size": list(character.size),
        "source_strategy": "difference matte from user-supplied clean background and composite",
        "image_generation": "pose generation attempted but blocked; exact supplied character preserved",
    }
    (ROOT / "PREPARATION_REPORT.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
