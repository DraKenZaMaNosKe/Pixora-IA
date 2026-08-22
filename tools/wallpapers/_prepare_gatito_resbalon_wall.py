"""Prepara assets ligeros para Gatito contra la gravedad."""
from __future__ import annotations

import json
import math
import shutil
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_resbalon_pared")
SHEET = Path(r"C:/Users/lalo/.codex/generated_images/019f7dd2-f7d2-76d2-ab01-5ae5829f6f3d/exec-9a77eb8c-f2b6-4c58-bd4b-d18b315125f5.png")
REFERENCE = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/.codex-remote-attachments/019f7dd2-f7d2-76d2-ab01-5ae5829f6f3d/b6c2b694-e3f6-4b21-b49f-907f70fa6e6f/1-Photo-1.jpg")


def remove_green(im: Image.Image) -> Image.Image:
    rgba = im.convert("RGBA")
    px = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, _ = px[x, y]
            green_strength = g - max(r, b)
            if green_strength > 80 and g > 120:
                alpha = 0
            elif green_strength > 25 and g > 95:
                alpha = max(0, min(255, int((80 - green_strength) / 55 * 255)))
            else:
                alpha = 255
            if alpha < 255:
                # Descontamina el borde verde antes de aplicar el alfa.
                g = min(g, max(r, b))
            px[x, y] = (r, g, b, alpha)
    box = rgba.getbbox()
    if not box:
        raise RuntimeError("Pose vacia tras retirar chroma")
    return rgba.crop(box)


def ease(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


def main() -> None:
    for name in ("source", "poses", "frames", "production", "qa"):
        (ROOT / name).mkdir(parents=True, exist_ok=True)
    shutil.copy2(REFERENCE, ROOT / "source" / "referencia_original.jpg")
    shutil.copy2(SHEET, ROOT / "source" / "sprite_sheet_generated.png")

    sheet = Image.open(SHEET).convert("RGBA")
    if sheet.size != (1536, 1024):
        raise RuntimeError(f"Sprite sheet inesperada: {sheet.size}")
    poses = []
    for index in range(6):
        col, row = index % 3, index // 3
        cell = sheet.crop((col * 512, row * 512, (col + 1) * 512, (row + 1) * 512))
        pose = remove_green(cell)
        pose.thumbnail((180, 235), Image.Resampling.LANCZOS)
        pose.save(ROOT / "poses" / f"pose_{index + 1}.png", optimize=True)
        poses.append(pose)

    # Fondo amplio, limpio y legible bajo iconos. Las rayas verticales sugieren pared.
    bg = Image.new("RGB", (1080, 2340), "#F6AA35")
    d = ImageDraw.Draw(bg)
    for x in range(0, 1080, 90):
        shade = "#F3A331" if (x // 90) % 2 == 0 else "#F8B13D"
        d.rectangle((x, 0, x + 44, 2340), fill=shade)
    # Sin molduras oscuras laterales: con parallax se confunden con franjas
    # negras o con una imagen que no alcanza a cubrir el viewport.
    bg.save(ROOT / "production" / "background.png", optimize=True)

    # Cada frame conserva el mismo canvas: el movimiento vertical vive dentro del sprite.
    # Pose, y normalizada dentro del canvas. Pausas duplicadas crean ritmo irregular.
    keyframes = [
        (0, 0.16), (0, 0.20), (3, 0.34), (3, 0.48),
        (4, 0.59), (5, 0.48), (1, 0.39), (2, 0.30),
        (1, 0.22), (0, 0.17),
    ]
    # 12 claves expresivas bastan para esta estetica minimalista. Con el gato
    # grande, mas frames prescalados exceden el heap de dispositivos antiguos.
    segment_counts = [2, 1, 2, 1, 1, 2, 1, 1, 1]
    frames = []
    # Canvas ajustado al personaje: evita prescalar grandes areas transparentes.
    canvas_size = (220, 370)
    for seg, count in enumerate(segment_counts):
        p0, y0 = keyframes[seg]
        p1, y1 = keyframes[seg + 1]
        for step in range(count):
            t = step / max(1, count - 1)
            y_norm = y0 + (y1 - y0) * ease(t)
            pose_index = p0 if t < 0.52 else p1
            pose = poses[pose_index]
            frame = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
            # Microtemblor solo durante el resbalon/susto.
            shake = int(round(math.sin((len(frames) + 1) * 2.4) * (4 if seg in (2, 3, 4) else 1)))
            x = (canvas_size[0] - pose.width) // 2 + shake
            y = int(y_norm * (canvas_size[1] - pose.height))
            frame.alpha_composite(pose, (x, y))
            frames.append(frame)

    frames_dir = ROOT / "frames"
    for old_frame in frames_dir.glob("frame_*.png"):
        old_frame.unlink()
    for i, frame in enumerate(frames, start=1):
        frame.save(frames_dir / f"frame_{i:03d}.png", optimize=True)
    zip_path = ROOT / "production" / "gatito_resbalon_sprite.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for frame_path in sorted(frames_dir.glob("frame_*.png")):
            zf.write(frame_path, frame_path.name)

    # Vista estatica de portada: mismo fondo y gato cerca de la pantalla.
    flat = bg.convert("RGBA")
    hero = poses[0].copy()
    hero = hero.resize((int(hero.width * 1.65), int(hero.height * 1.65)), Image.Resampling.LANCZOS)
    flat.alpha_composite(hero, ((1080 - hero.width) // 2 + 115, 930))
    flat.convert("RGB").save(ROOT / "production" / "gatito_resbalon_flat.jpg", quality=94)

    metadata = """# Gatito contra la gravedad\n\nEscena original inspirada en el humor visual de un gato que intenta aferrarse a una pared. El protagonista no pertenece a una pelicula, anime o franquicia identificada: se presenta como un personaje caricaturesco original. Sus ojos enormes convierten el peligro en comedia; las marcas de las garras cuentan el esfuerzo de cada intento.\n\nLa animacion representa perseverancia: el gato resbala lentamente, se asusta, recupera el agarre y vuelve a escalar. Se usan seis poses y un ciclo compacto para conservar fluidez y buen rendimiento en celulares modestos.\n"""
    (ROOT / "METADATA_DESCRIPCION.md").write_text(metadata, encoding="utf-8")
    report = {
        "scene_id": "gatito_resbalon_pared",
        "poses": len(poses), "frames": len(frames),
        "frame_canvas": list(canvas_size), "sprite_zip_bytes": zip_path.stat().st_size,
        "strategy": "six consistent poses plus interpolated vertical travel and irregular pauses",
    }
    (ROOT / "PREPARATION_REPORT.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
