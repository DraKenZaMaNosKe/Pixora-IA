"""
Extract PNG frames from a GIF or MP4 into a sprite ZIP (frame_001.png …).

Output is ready for the sprite editor: IMPORT → Sprite pack → PC or push to
/sdcard/Pixora/inbox/ on the connected device.

Examples:
  python tools/wallpapers/extract_sprite_pack.py --gif ryu_.gif --frames 12
  python tools/wallpapers/extract_sprite_pack.py --video clip.mp4 --frames 15 --push-device
"""
from __future__ import annotations

import argparse
import io
import os
import subprocess
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))


def extract_from_gif(src: Path, frames: int, pad: int = 0) -> list[bytes]:
    from PIL import Image

    gif = Image.open(src)
    total = 0
    try:
        while True:
            gif.seek(total)
            total += 1
    except EOFError:
        pass
    if total < 1:
        raise SystemExit(f"GIF vacío: {src}")
    indices = [int(i * total / frames) for i in range(frames)]
    out: list[bytes] = []
    for src_i in indices:
        gif.seek(src_i)
        frame = gif.convert("RGBA")
        if pad > 0:
            bbox = frame.getbbox()
            if bbox:
                x0 = max(0, bbox[0] - pad)
                y0 = max(0, bbox[1] - pad)
                x1 = min(frame.width, bbox[2] + pad)
                y1 = min(frame.height, bbox[3] + pad)
                frame = frame.crop((x0, y0, x1, y1))
        buf = io.BytesIO()
        frame.save(buf, "PNG", optimize=True)
        out.append(buf.getvalue())
    return out


def extract_from_video(src: Path, frames: int, work: Path) -> list[bytes]:
    work.mkdir(parents=True, exist_ok=True)
    pattern = work / "frame_%03d.png"
    cmd = [
        "ffmpeg", "-y", "-i", str(src),
        "-vf", f"select='not(mod(n\\,{max(1, 30 // max(frames, 1))}))',scale=-1:-1",
        "-vsync", "vfr", "-frames:v", str(frames),
        str(pattern),
    ]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"ffmpeg failed: {r.stderr[-400:]}")
    pngs = sorted(work.glob("frame_*.png"))
    if not pngs:
        raise SystemExit("ffmpeg no produjo frames")
    return [p.read_bytes() for p in pngs[:frames]]


def write_zip(frame_bytes: list[bytes], dest: Path) -> None:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for i, data in enumerate(frame_bytes, start=1):
            zf.writestr(f"frame_{i:03d}.png", data)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(buf.getvalue())
    print(f"ZIP {dest} ({len(frame_bytes)} frames, {dest.stat().st_size:,} B)")


def push_to_device(zip_path: Path, serial: str | None = None) -> None:
    from device_images import ensure_pixora_inbox
    from device_surface import pick_device

    dev = pick_device(serial)
    if not dev:
        raise SystemExit("no adb device — conecta el Samsung")
    ser = dev["serial"]
    ensure_pixora_inbox(ser)
    remote = f"/sdcard/Pixora/inbox/{zip_path.name}"
    ADB = r"C:\Users\lalo\AppData\Local\Android\Sdk\platform-tools\adb.exe"
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    subprocess.run([ADB, "-s", ser, "push", str(zip_path), remote], check=True, creationflags=flags)
    print(f"Pushed → {remote}")
    print("En el editor: IMPORT → Sprite pack → Cel → selecciona el ZIP")


def main() -> None:
    ap = argparse.ArgumentParser(description="Extract sprite frame pack (ZIP)")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--gif", type=Path, help="Source GIF")
    g.add_argument("--video", type=Path, help="Source MP4/video")
    ap.add_argument("--frames", type=int, default=12)
    ap.add_argument("--pad", type=int, default=0, help="Alpha bbox padding (GIF)")
    ap.add_argument("-o", "--out", type=Path, help="Output .zip (default: <name>_pack.zip)")
    ap.add_argument("--push-device", action="store_true", help="adb push to Pixora/inbox")
    ap.add_argument("--serial", help="adb device serial")
    args = ap.parse_args()

    src = args.gif or args.video
    if not src.is_file():
        raise SystemExit(f"not found: {src}")

    out = args.out or src.with_name(f"{src.stem}_pack.zip")
    work = out.parent / f"_tmp_extract_{src.stem}"

    if args.gif:
        frames = extract_from_gif(src, args.frames, pad=args.pad)
    else:
        frames = extract_from_video(src, args.frames, work)

    write_zip(frames, out)
    if args.push_device:
        push_to_device(out, args.serial)


if __name__ == "__main__":
    main()