"""Prepara paquete ligero de Plancton con hamburguesa usando assets aportados."""
from __future__ import annotations

import json
import math
import shutil
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image


SRC = Path(r"C:/Users/lalo/Downloads/plancton")
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/plancton_hamburguesa_escape")
CHAR_SRC = SRC / "grok-627303df-b643-4c64-8bd4-cde21a1264d0.jpg"
BG_SRC = SRC / "grok-480084d4-11fb-47e7-a72c-a6fe1c11be97.jpg"
COMPOSITE_SRC = SRC / "1a9f38534bfb01ba812c4422f8839b97.jpg"
POSE_FILES = [
    SRC / "grok-492eed56-b527-468f-9228-18491dfcf709.jpg",  # caminar A
    SRC / "grok-94e4a9fe-1bce-4924-ab9b-e128476bb7bd.jpg",  # caminar B
    SRC / "grok-0a6fb00e-ec22-4a42-b014-0ca2145191ce.jpg",  # orgullo
    SRC / "grok-033f0bdf-cfc4-4be7-9349-e0a36b378dd7.jpg",  # victoria
    SRC / "grok-891904b7-86f1-454e-93af-1c1b47dd00d1.jpg",  # susto
]


def remove_magenta(path: Path) -> Image.Image:
    rgba = np.array(Image.open(path).convert("RGBA"), dtype=np.uint8)
    rgb = rgba[:, :, :3].astype(np.int16)
    # Distancia a la familia de magentas del fondo de Grok. El sujeto no usa magenta.
    magenta_score = rgb[:, :, 0] + rgb[:, :, 2] - 2 * rgb[:, :, 1]
    saturation_gate = (rgb[:, :, 0] > 125) & (rgb[:, :, 2] > 65)
    alpha = np.where(saturation_gate & (magenta_score > 48), 0, 255).astype(np.uint8)
    # Alfa limpio: el reescalado premultiplicado posterior crea el antialias sin
    # arrastrar el magenta oculto hacia el contorno visible.
    rgba[:, :, 3] = alpha
    rgba[alpha == 0, :3] = 0
    result = Image.fromarray(rgba, "RGBA")
    bbox = result.getbbox()
    if not bbox:
        raise RuntimeError(f"Pose vacia: {path.name}")
    pad = 16
    x0, y0, x1, y1 = bbox
    return result.crop((max(0, x0-pad), max(0, y0-pad), min(result.width, x1+pad), min(result.height, y1+pad)))


def thumbnail_rgba_premultiplied(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Reduce RGBA sin contaminar bordes transparentes con el color del fondo."""
    scale = min(size[0] / image.width, size[1] / image.height, 1.0)
    target = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    arr = np.asarray(image.convert("RGBA"), dtype=np.float32)
    alpha = arr[:, :, 3:4] / 255.0
    premult = np.concatenate((arr[:, :, :3] * alpha, arr[:, :, 3:4]), axis=2)
    channels = [
        np.asarray(Image.fromarray(premult[:, :, i], mode="F").resize(target, Image.Resampling.LANCZOS))
        for i in range(4)
    ]
    resized = np.stack(channels, axis=2)
    out_alpha = np.clip(resized[:, :, 3:4], 0, 255)
    denom = np.maximum(out_alpha / 255.0, 1e-6)
    out_rgb = np.where(out_alpha > 0.5, resized[:, :, :3] / denom, 0)
    out = np.concatenate((np.clip(out_rgb, 0, 255), out_alpha), axis=2).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def main() -> None:
    for folder in ("source", "layers", "frames", "production", "qa", "metadata"):
        (ROOT / folder).mkdir(parents=True, exist_ok=True)
    for src in (CHAR_SRC, BG_SRC, COMPOSITE_SRC, *POSE_FILES):
        shutil.copy2(src, ROOT / "source" / src.name)

    poses = []
    for index, pose_file in enumerate(POSE_FILES, 1):
        pose = remove_magenta(pose_file)
        pose = thumbnail_rgba_premultiplied(pose, (290, 470))
        pose.save(ROOT / "layers" / f"pose_{index}.png", optimize=True)
        poses.append(pose)

    # Ciclo: pasos cortos, pausa orgullosa y protección de la hamburguesa.
    pose_sequence = [0, 0, 1, 0, 1, 2, 2, 3, 3, 2, 4, 4, 0, 1, 2]
    frame_count = len(pose_sequence)
    canvas_size = (360, 540)
    frames = []
    for index, pose_index in enumerate(pose_sequence):
        phase = index / frame_count * math.tau
        pose = poses[pose_index]
        frame = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
        x = (canvas_size[0] - pose.width)//2 + int(math.sin(phase)*5)
        y = (canvas_size[1] - pose.height)//2 + int(abs(math.sin(phase))*6)
        frame.alpha_composite(pose, (x, y))
        frames.append(frame)
    frames_dir = ROOT / "frames"
    for old in frames_dir.glob("frame_*.png"):
        old.unlink()
    for i, frame in enumerate(frames, 1):
        frame.save(frames_dir / f"frame_{i:03d}.png", optimize=True)
    zip_path = ROOT / "production" / "plancton_hamburguesa_sprite.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for frame in sorted(frames_dir.glob("frame_*.png")):
            zf.write(frame, frame.name)

    # Portada: integra el recorte exacto sobre el fondo entregado.
    bg = Image.open(BG_SRC).convert("RGB").resize((1080, 1920), Image.Resampling.LANCZOS)
    flat = bg.convert("RGBA")
    front = poses[2].copy()
    front = thumbnail_rgba_premultiplied(front, (600, 960))
    flat.alpha_composite(front, ((1080-front.width)//2 + 95, 710))
    flat.convert("RGB").save(ROOT / "production" / "plancton_hamburguesa_flat.jpg", quality=94)

    metadata = """# Sheldon J. Plankton — El pequeño genio del Balde de Carnada

## Identidad y papel

Sheldon J. Plankton es uno de los antagonistas principales de *Bob Esponja*. Es un diminuto copépodo de un solo ojo, propietario del restaurante Balde de Carnada (Chum Bucket). Su meta recurrente es robar la fórmula secreta de la Cangreburger para superar al Crustáceo Cascarudo.

## Personalidad, carisma y contradicción

Es brillante, teatral, perseverante, orgulloso y obsesivo. Construye robots y planes complejos, pero su ego y su impaciencia suelen sabotearlo. Su carisma nace de una contradicción: habla como un conquistador gigantesco aunque físicamente sea uno de los habitantes más pequeños de Fondo de Bikini. También tiene momentos de vulnerabilidad, soledad y deseo de ser respetado.

## Relaciones

- **Karen Plankton:** esposa computadora, socia, estratega y la voz pragmática que corrige sus planes.
- **Don Cangrejo:** antiguo amigo convertido en archirrival comercial; protege la fórmula que Plancton desea.
- **Bob Esponja:** obstáculo habitual, pero ocasional compañero; su bondad desarma muchos planes de Plancton.
- **Patricio y Calamardo:** suelen ser obstáculos, herramientas accidentales o testigos de sus fracasos.

## Historia y curiosidades verificadas

- Fue creado y diseñado por Stephen Hillenburg, biólogo marino y animador.
- Debutó en el episodio “Plankton!”, estrenado el 31 de julio de 1999; allí intenta controlar a Bob Esponja para obtener una Cangreburger.
- Su nombre completo canónico es Sheldon J. Plankton.
- Es interpretado en inglés por Mr. Lawrence; Karen por Jill Talley.
- Karen recibió su nombre en homenaje a Karen Hillenburg, esposa del creador.
- La ficha oficial de Nickelodeon lo presenta como fundador del restaurante menos popular bajo el mar y confirma a Don Cangrejo como su archirrival.

## Lectura de esta escena

La imagen imagina una victoria imposible: Plancton sostiene una hamburguesa enorme con orgullo, como si por fin hubiera conseguido el premio que persigue. El balanceo del cuerpo y las burbujas convierten su escape en una celebración nerviosa: está feliz, pero todavía teme que alguien se la quite.

## Fuentes

- Nickelodeon, “Sheldon J. Plankton”: https://www.nick.com/info-page/4965u5/sheldon-j-plankton
- Nickelodeon, “Mr. Krabs”: https://www.nick.com/info-page/0vq4xx/mr-krabs
- Paramount+, episodio de temporada 1 “Jellyfishing / Plankton!”: https://www.intl.paramountplus.com/mx/shows/spongebob-squarepants/
"""
    (ROOT / "metadata" / "HISTORIA_PERSONAJE_Y_ESCENA.md").write_text(metadata, encoding="utf-8")
    report = {
        "scene_id": "plancton_hamburguesa_escape", "frames": frame_count,
        "frame_canvas": list(canvas_size), "sprite_zip_bytes": zip_path.stat().st_size,
        "valid_poses": len(poses), "excluded_pose": "grok-663e6128... (incorrectly generated with two eyes)",
        "generation_fallback": "user-provided Grok pose set after image generation moderation block",
    }
    (ROOT / "PREPARATION_REPORT.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
