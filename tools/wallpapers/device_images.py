"""List and pull image files from a connected Android device (adb)."""
from __future__ import annotations

import os
import re
import subprocess
import time
from dataclasses import asdict, dataclass
from pathlib import Path

from device_surface import PREFERRED_SERIALS, _run_adb, pick_device

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif"}
PACK_EXTS = {".zip"}
MEDIA_EXTS = IMAGE_EXTS | PACK_EXTS

# Pixora/inbox first — user can Share/Save images here from the phone.
SCAN_DIRS = (
    "/sdcard/Pixora/inbox",
    "/sdcard/DCIM/Camera",
    "/sdcard/Download",
    "/sdcard/Pictures",
    "/sdcard/Screenshots",
)

CACHE_DIR = Path(__file__).parent / "_device_image_cache"


@dataclass
class DeviceImage:
    path: str
    name: str
    folder: str
    size: int | None
    mtime: float | None
    kind: str = "image"  # image | sprite_pack

    def to_dict(self) -> dict:
        return asdict(self)


def ensure_pixora_inbox(serial: str | None = None) -> None:
    _run_adb("shell", "mkdir", "-p", "/sdcard/Pixora/inbox", serial=serial)


def _parse_ls_line(line: str, folder: str) -> DeviceImage | None:
    # -rw-rw---- 1 u0_a123 media_rw 2456789 2026-06-28 15:30 IMG_20250628.jpg
    m = re.match(
        r"^-[\w-]+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+"
        r"(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\s+(.+)$",
        line.strip(),
    )
    if not m:
        return None
    size = int(m.group(1))
    name = m.group(4).strip()
    if name in (".", ".."):
        return None
    ext = Path(name).suffix.lower()
    if ext not in MEDIA_EXTS:
        return None
    kind = "sprite_pack" if ext in PACK_EXTS else "image"
    path = f"{folder.rstrip('/')}/{name}"
    try:
        ts = time.mktime(time.strptime(f"{m.group(2)} {m.group(3)}", "%Y-%m-%d %H:%M"))
    except Exception:
        ts = None
    return DeviceImage(path=path, name=name, folder=folder, size=size, mtime=ts, kind=kind)


def list_device_images(serial: str | None = None, limit: int = 48) -> list[DeviceImage]:
    dev = pick_device(serial)
    if not dev:
        return []
    ser = dev["serial"]
    ensure_pixora_inbox(ser)

    found: dict[str, DeviceImage] = {}
    for folder in SCAN_DIRS:
        out = _run_adb("shell", "ls", "-lt", folder, serial=ser, timeout=12)
        for line in out.splitlines():
            img = _parse_ls_line(line, folder)
            if img:
                found[img.path] = img
        if len(found) >= limit * 2:
            break

    # Fallback: find stray files one level deeper in inbox
    if len(found) < 8:
        out = _run_adb(
            "shell", "find", "/sdcard/Pixora/inbox", "-maxdepth", "2",
            "-type", "f", serial=ser, timeout=12,
        )
        for line in out.splitlines():
            p = line.strip()
            ext = Path(p).suffix.lower()
            if not p or ext not in MEDIA_EXTS:
                continue
            if p not in found:
                found[p] = DeviceImage(
                    path=p, name=Path(p).name, folder="/sdcard/Pixora/inbox",
                    size=None, mtime=None,
                    kind="sprite_pack" if ext in PACK_EXTS else "image",
                )

    items = list(found.values())
    items.sort(key=lambda x: (x.mtime or 0, x.size or 0), reverse=True)
    return items[:limit]


def pull_device_image(
    device_path: str,
    serial: str | None = None,
    dest: Path | None = None,
) -> Path:
    dev = pick_device(serial)
    if not dev:
        raise RuntimeError("no adb device connected")
    ser = dev["serial"]
    device_path = device_path.strip()
    if not device_path.startswith("/"):
        raise ValueError("device_path must be absolute")
    ext = Path(device_path).suffix.lower()
    if ext not in MEDIA_EXTS:
        raise ValueError(f"unsupported file type: {ext}")

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", device_path)[:120]
    local = dest or (CACHE_DIR / f"{ser}_{safe}")
    if local.suffix.lower() not in IMAGE_EXTS:
        local = local.with_suffix(ext or ".jpg")

    if local.exists():
        local.unlink()
    ADB = r"C:\Users\lalo\AppData\Local\Android\Sdk\platform-tools\adb.exe"
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    r = subprocess.run(
        [ADB, "-s", ser, "pull", device_path, str(local)],
        capture_output=True,
        creationflags=flags,
        text=True,
        timeout=120,
        encoding="utf-8",
        errors="replace",
    )
    if r.returncode != 0 or not local.is_file():
        raise RuntimeError(f"adb pull failed: {(r.stderr or r.stdout or '').strip()[:200]}")
    return local


def list_devices_brief() -> list[dict]:
    from device_surface import list_devices
    return list_devices()


def preview_cache_path(device_path: str, serial: str) -> Path:
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", device_path)[:100]
    return CACHE_DIR / f"prev_{serial}_{safe}.jpg"


def pull_device_preview(
    device_path: str,
    serial: str | None = None,
    max_side: int = 720,
) -> Path:
    """Pull device image and write a JPEG preview for the editor grid."""
    dev = pick_device(serial)
    if not dev:
        raise RuntimeError("no adb device connected")
    ser = dev["serial"]
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    preview = preview_cache_path(device_path, ser)
    if preview.exists() and preview.stat().st_size > 0:
        age = time.time() - preview.stat().st_mtime
        if age < 3600:
            return preview

    raw = pull_device_image(device_path, serial=ser)
    try:
        from PIL import Image
        img = Image.open(raw)
        if img.mode not in ("RGB", "RGBA"):
            img = img.convert("RGB")
        elif img.mode == "RGBA":
            bg = Image.new("RGB", img.size, (0, 0, 0))
            bg.paste(img, mask=img.split()[3])
            img = bg
        img.thumbnail((max_side, max_side), Image.LANCZOS)
        img.save(preview, "JPEG", quality=82, optimize=True)
    except Exception:
        # Fallback: serve raw file copy
        preview.write_bytes(raw.read_bytes())
    return preview