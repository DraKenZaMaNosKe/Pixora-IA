"""Extract frames from an aquarium GIF into Android assets.

Features:
- Auto-skips fully transparent "disposal" frames (prevents the vanish-reappear glitch).
- Optional bbox cropping (pass --crop) — computes the union bbox across all frames,
  pads 6 px, and crops each frame to that size. Saves massive RAM for sprites with
  lots of empty space (small schooling fish like neon tetra).
- Reports final frame count, disk size, and estimated decoded RAM.

Usage:
    python extract_aquarium_gif.py <gif_path> <sprite_name> [--crop]

Example:
    python extract_aquarium_gif.py C:/Users/lalo/Desktop/shrimp.gif shrimp --crop
    # writes to android/app/src/main/assets/aquarium/shrimp/frame_XXX.png
"""
import argparse
import sys
from pathlib import Path
from PIL import Image

ASSETS_ROOT = Path(__file__).parent / "android/app/src/main/assets/aquarium"


def extract(gif_path: Path, sprite_name: str, crop: bool):
    dst = ASSETS_ROOT / sprite_name
    dst.mkdir(parents=True, exist_ok=True)

    # Wipe previous frames for this sprite to avoid stale mixing
    for old in dst.glob("frame_*.png"):
        old.unlink()

    g = Image.open(gif_path)
    n = g.n_frames
    print(f"Source: {gif_path.name} — {g.size}, {n} frames")

    # Pass 1: identify non-empty frames + compute union bbox
    valid_indices = []
    union = None
    for i in range(n):
        g.seek(i)
        frame = g.convert("RGBA")
        bb = frame.getbbox()
        if bb is None:
            print(f"  skip frame {i+1}: fully transparent (disposal frame)")
            continue
        valid_indices.append(i)
        if union is None:
            union = list(bb)
        else:
            union[0] = min(union[0], bb[0])
            union[1] = min(union[1], bb[1])
            union[2] = max(union[2], bb[2])
            union[3] = max(union[3], bb[3])

    if not valid_indices:
        print("FAIL: no non-empty frames found")
        sys.exit(1)

    if crop:
        pad = 6
        union[0] = max(0, union[0] - pad)
        union[1] = max(0, union[1] - pad)
        union[2] = min(g.size[0], union[2] + pad)
        union[3] = min(g.size[1], union[3] + pad)
        cw, ch = union[2] - union[0], union[3] - union[1]
        print(f"Crop bbox: {tuple(union)} -> {cw}x{ch} (from {g.size[0]}x{g.size[1]})")
    else:
        cw, ch = g.size

    # Pass 2: write valid frames
    for out_idx, src_idx in enumerate(valid_indices, start=1):
        g.seek(src_idx)
        frame = g.convert("RGBA")
        if crop:
            frame = frame.crop(tuple(union))
        frame.save(dst / f"frame_{out_idx:03d}.png", "PNG", optimize=True)

    files = sorted(dst.glob("frame_*.png"))
    total_disk = sum(f.stat().st_size for f in files)
    ram_kb = cw * ch * 4 * len(files) / 1024
    print(f"\nWrote {len(files)} frames to {dst.relative_to(Path(__file__).parent)}")
    print(f"Disk: {total_disk:,} bytes ({total_disk/1024:.0f} KB)")
    print(f"RAM (ARGB decoded): {ram_kb:.0f} KB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gif", type=Path, help="path to source GIF")
    ap.add_argument("name", help="sprite subfolder name (e.g. betta, angel, neon, shrimp)")
    ap.add_argument("--crop", action="store_true",
                    help="crop to content bbox — recommended for small sprites with lots of empty space")
    args = ap.parse_args()

    if not args.gif.exists():
        print(f"FAIL: {args.gif} not found")
        sys.exit(1)

    extract(args.gif, args.name, args.crop)


if __name__ == "__main__":
    main()
