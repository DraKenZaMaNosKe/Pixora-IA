"""
One-shot: procesa los 4 assets de Bulma (Desktop/wallPapers_repo/)
para cumplir specs de Pixora. NO sube nada — solo prepara.

Output directory: tools/wallpapers/_bulma_processed/
"""
from __future__ import annotations
import sys, os, subprocess
from pathlib import Path
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo")
OUT = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_bulma_processed")
OUT.mkdir(parents=True, exist_ok=True)

FFMPEG = r"C:/Users/lalo/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1.1-full_build/bin/ffmpeg.exe"

def kb(n):
    return f"{n/1024:.0f} KB" if n < 1024*1024 else f"{n/(1024*1024):.2f} MB"

def save_webp(img: Image.Image, out_path: Path, quality: int):
    if img.mode == "RGBA":
        bg = Image.new("RGB", img.size, (255, 255, 255))
        bg.paste(img, mask=img.split()[3])
        img = bg
    img.save(out_path, "WEBP", quality=quality, method=6)

print("=" * 60)
print("FASE A — Procesamiento de assets Bulma")
print("=" * 60)

# ─── PANORAMIC 00 ───────────────────────────────────────────────
print("\n[1/6] Panoramic 00 — convert PNG to WebP")
src = SRC / "bulma_sexy_00_panoramico_00.png"
img = Image.open(src)
print(f"  Input:  {src.name}  {img.width}x{img.height}  {kb(src.stat().st_size)}")
out = OUT / "bulma_sexy_panoramico_00.webp"
save_webp(img, out, quality=90)
print(f"  Output: {out.name}  {img.width}x{img.height}  {kb(out.stat().st_size)}")

# Preview panorámica: 720x176 (mantiene 4:1)
print("\n[2/6] Panoramic 00 — preview (720x176)")
prev = img.resize((720, 176), Image.LANCZOS)
prev_out = OUT / "bulma_sexy_panoramico_00_preview.webp"
save_webp(prev, prev_out, quality=85)
print(f"  Output: {prev_out.name}  720x176  {kb(prev_out.stat().st_size)}")

# ─── PANORAMIC 01 ───────────────────────────────────────────────
print("\n[3/6] Panoramic 01 — convert PNG to WebP")
src = SRC / "bulma_sexy_00_panoramico_01.png"
img = Image.open(src)
print(f"  Input:  {src.name}  {img.width}x{img.height}  {kb(src.stat().st_size)}")
out = OUT / "bulma_sexy_panoramico_01.webp"
save_webp(img, out, quality=90)
print(f"  Output: {out.name}  {img.width}x{img.height}  {kb(out.stat().st_size)}")

print("\n[4/6] Panoramic 01 — preview (720x176)")
prev = img.resize((720, 176), Image.LANCZOS)
prev_out = OUT / "bulma_sexy_panoramico_01_preview.webp"
save_webp(prev, prev_out, quality=85)
print(f"  Output: {prev_out.name}  720x176  {kb(prev_out.stat().st_size)}")

# ─── STATIC WALLPAPER (upscale 656x1584 -> 1080x2340) ────────────
print("\n[5/6] Static wallpaper — upscale + WebP")
src = SRC / "bulma_sexy_00_wallpaperestatico.png"
img = Image.open(src)
print(f"  Input:  {src.name}  {img.width}x{img.height}  {kb(src.stat().st_size)}  format={img.format}")
# Target: 1080 wide, scale height proportionally then center-crop to 2340
new_w = 1080
new_h = int(img.height * (new_w / img.width))
img_up = img.resize((new_w, new_h), Image.LANCZOS)
# If new_h != 2340, center crop or pad. 656x1584 -> 1080x2607 (extra 267px)
# Center crop to 1080x2340
if new_h > 2340:
    top = (new_h - 2340) // 2
    img_up = img_up.crop((0, top, 1080, top + 2340))
elif new_h < 2340:
    # pad with edge color (rare)
    bg = Image.new("RGB", (1080, 2340), (0, 0, 0))
    bg.paste(img_up, (0, (2340 - new_h) // 2))
    img_up = bg
out = OUT / "bulma_sexy_estatico.webp"
save_webp(img_up, out, quality=90)
print(f"  Output: {out.name}  1080x2340  {kb(out.stat().st_size)}")

# Preview estática: 540x1170
print("  Preview (540x1170)…")
prev = img_up.resize((540, 1170), Image.LANCZOS)
prev_out = OUT / "bulma_sexy_estatico_preview.webp"
save_webp(prev, prev_out, quality=80)
print(f"  Output: {prev_out.name}  540x1170  {kb(prev_out.stat().st_size)}")

# ─── VIDEO (strip audio + reencode for Live wallpaper) ───────────
print("\n[6/6] Video — strip audio + reencode H.264 baseline")
src = SRC / "bulma_sexy_00_video.mp4"
out = OUT / "bulma_sexy_live.mp4"
print(f"  Input:  {src.name}  {kb(src.stat().st_size)}")
cmd = [
    FFMPEG, "-y", "-i", str(src),
    "-an",                        # NO audio (Pixora requirement)
    "-c:v", "libx264",
    "-profile:v", "baseline",     # baseline for max compatibility
    "-level", "3.1",
    "-pix_fmt", "yuv420p",        # for compatibility with MediaPlayer
    "-preset", "slow",
    "-crf", "23",
    "-movflags", "+faststart",
    str(out)
]
r = subprocess.run(cmd, capture_output=True, text=True)
if r.returncode != 0:
    print(f"  FFMPEG ERROR:\n{r.stderr[-500:]}")
    sys.exit(1)
print(f"  Output: {out.name}  {kb(out.stat().st_size)}")

# Generate preview frame (1s in, square crop)
print("  Preview (720x720 frame at 1s)…")
prev_out = OUT / "bulma_sexy_live_preview.webp"
cmd = [
    FFMPEG, "-y", "-ss", "1.0", "-i", str(out),
    "-vframes", "1",
    "-vf", "scale=720:720:force_original_aspect_ratio=increase,crop=720:720",
    "-q:v", "85",
    str(prev_out)
]
r = subprocess.run(cmd, capture_output=True, text=True)
if r.returncode != 0:
    print(f"  Preview error: {r.stderr[-300:]}")
else:
    print(f"  Output: {prev_out.name}  720x720  {kb(prev_out.stat().st_size)}")

print("\n" + "=" * 60)
print("✅ FASE A COMPLETA — todos los archivos en:")
print(f"   {OUT}")
print("=" * 60)
print("\nResumen final:")
for f in sorted(OUT.iterdir()):
    print(f"  {f.name:<45} {kb(f.stat().st_size)}")
