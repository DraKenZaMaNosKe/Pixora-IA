"""Separa personaje_completo.png en partes por hueso usando los polígonos
`region` del RIG_SPEC, con dilatación (anti-huecos) + feather (anti-costuras).
Emite las partes, el manifest con offsets, el bloque `rigs` del spec, y dos
imágenes de control para validar el recorte ANTES de compilar nada.

Ver diseño: docs/superpowers/specs/2026-07-25-bone-rigging-2d-design.md
"""
import json, sys
import numpy as np
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
CHAR = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/heroina_candy_mecha_rig_v1")
OUT = CHAR / "rig_parts"
(OUT / "parts").mkdir(parents=True, exist_ok=True)
DILATE = 29   # MaxFilter impar -> radio ~14 px (solape compartido)
FEATHER = 5   # blur del borde alfa
PAD = 4

# hueso RIG_SPEC -> (id corto, parent, z). root no genera parte (sprite null).
MAP = {
    "root":        ("root",     None,    None),
    "raised_leg":  ("leg_up",   "root",  1),
    "bent_leg":    ("leg_bent", "root",  2),
    "torso":       ("torso",    "root",  3),
    "gauntlet_arm":("arm",      "torso", 4),
    "head_hair":   ("head",     "torso", 5),
}

spec = json.loads((CHAR / "RIG_SPEC_V1.json").read_text(encoding="utf-8"))
img = Image.open(CHAR / "personaje_completo.png").convert("RGBA")
W, H = img.size
print(f"personaje: {W}x{H}")
alpha_orig = np.array(img.split()[3], dtype=np.uint8)
kf = spec.get("animation", {}).get("keyframes", {})

bones_by_id = {b["id"]: b for b in spec["bones"]}
manifest, rig_bones = {}, []
union = np.zeros((H, W), dtype=bool)
recompose = Image.new("RGBA", (W, H), (0, 0, 0, 0))
debug = img.copy().convert("RGBA")
ddraw = ImageDraw.Draw(debug, "RGBA")
try: fnt = ImageFont.truetype("arialbd.ttf", 34)
except Exception: fnt = ImageFont.load_default()

# procesar en orden z (para recompose correcto); root primero (sin parte)
order = sorted(MAP.items(), key=lambda kv: (kv[1][2] is None and -1 or kv[1][2]))
for rig_name, (bid, parent, z) in order:
    b = bones_by_id.get(rig_name)
    if not b:
        print(f"[!] {rig_name} no está en RIG_SPEC"); continue
    pivot_px = [round(b["pivot"][0] * W), round(b["pivot"][1] * H)]
    entry = {"id": bid, "parent": parent, "pivot_px": pivot_px}
    if z is not None: entry["z"] = z
    entry["sprite"] = None if bid == "root" else f"rig_{bid}"
    # keyframes: copiar del RIG_SPEC (torso: quieto)
    if rig_name in kf:
        entry["keyframes"] = kf[rig_name]
    elif bid == "torso":
        entry["keyframes"] = [{"t": 0, "rotation": 0}, {"t": 1, "rotation": 0}]

    if bid == "root":
        rig_bones.append(entry)
        continue

    # --- recorte de la parte ---
    pts = [(round(u * W), round(v * H)) for u, v in b["region"]]
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    mask_dil = mask.filter(ImageFilter.MaxFilter(DILATE))
    union |= (np.array(mask_dil) > 0)
    mask_soft = mask_dil.filter(ImageFilter.GaussianBlur(FEATHER))
    part_alpha = np.minimum(alpha_orig, np.array(mask_soft, dtype=np.uint8))
    part = img.copy(); part.putalpha(Image.fromarray(part_alpha, "L"))
    bbox = Image.fromarray((part_alpha > 8).astype(np.uint8) * 255, "L").getbbox()
    if not bbox:
        print(f"[!] {bid}: recorte vacío"); continue
    l, t, r, btm = bbox
    l, t = max(0, l - PAD), max(0, t - PAD)
    r, btm = min(W, r + PAD), min(H, btm + PAD)
    crop = part.crop((l, t, r, btm))
    (OUT / "parts" / bid).mkdir(parents=True, exist_ok=True)
    crop.save(OUT / "parts" / bid / "frame_001.png")
    entry["offset_px"] = [l, t]
    entry["size_px"] = [r - l, btm - t]
    manifest[bid] = {"offset_px": [l, t], "size_px": [r - l, btm - t], "pivot_px": pivot_px}
    rig_bones.append(entry)
    # recompose + debug
    recompose.alpha_composite(crop, (l, t))
    ddraw.polygon(pts, outline=(0, 255, 255, 255), width=4)
    cx = sum(p[0] for p in pts) // len(pts); cy = sum(p[1] for p in pts) // len(pts)
    ddraw.text((cx - 40, cy), bid, fill=(255, 46, 154, 255), font=fnt)
    ddraw.ellipse([pivot_px[0]-7, pivot_px[1]-7, pivot_px[0]+7, pivot_px[1]+7], fill=(255, 210, 0, 255))
    print(f"  ✓ {bid:9} offset={entry['offset_px']} size={entry['size_px']} pivot={pivot_px} z={z}")

# assert de cobertura
char_px = alpha_orig > 16
orphan = int((char_px & ~union).sum())
total = int(char_px.sum())
print(f"\ncobertura: huérfanos {orphan}/{total} = {100*orphan/max(1,total):.2f}% (idealmente ~0)")

# salidas
(OUT / "debug_regions.png").write_bytes(b""); debug.save(OUT / "debug_regions.png")
# recompose sobre fondo para comparar
bg = Image.open(CHAR / "fondo_limpio.png").convert("RGBA").resize((W, H))
comp = bg.copy(); comp.alpha_composite(recompose); comp.convert("RGB").save(OUT / "debug_recompose.png")
rig_block = {"name": "heroina", "z": 10, "anchor": [0.5, 0.55], "char_size": [W, H],
             "scale": 1.15, "loop_seconds": spec.get("animation", {}).get("duration_ms", 4200)/1000.0,
             "easing": "smooth", "bones": rig_bones}
(OUT / "rig_parts_manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
(OUT / "rig_block.json").write_text(json.dumps({"rigs": [rig_block]}, indent=2, ensure_ascii=False), encoding="utf-8")
print(f"\n[OK] partes + debug_regions.png + debug_recompose.png + rig_block.json en {OUT}")
