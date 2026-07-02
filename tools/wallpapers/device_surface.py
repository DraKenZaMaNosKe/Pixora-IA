"""Read connected Android device display size via adb (for sprite editor WYSIWYG)."""
from __future__ import annotations

import os
import re
import subprocess
from dataclasses import asdict, dataclass

# Full path to avoid PATH resolution flashes
ADB_PATH = r"C:\Users\lalo\AppData\Local\Android\Sdk\platform-tools\adb.exe"

# Pixora test devices — prefer Samsung when multiple are attached.
PREFERRED_SERIALS = ("RF8X903KZ3K", "G2R4C17516000149")

FALLBACK_W = 1080
FALLBACK_H = 2340


@dataclass
class DeviceSurface:
    connected: bool
    serial: str | None
    model: str | None
    width: int
    height: int
    density: int | None
    source: str  # "device" | "fallback"
    message: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)


def _run_adb(*args: str, serial: str | None = None, timeout: int = 8) -> str:
    cmd = [ADB_PATH]
    if serial:
        cmd.extend(["-s", serial])
    cmd.extend(args)
    try:
        flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        si.wShowWindow = 0  # SW_HIDE
        r = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
            creationflags=flags,
            startupinfo=si,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return str(e)
    return (r.stdout or "") + (r.stderr or "")


def list_devices() -> list[dict]:
    out = _run_adb("devices", "-l")
    devices: list[dict] = []
    for line in out.splitlines():
        line = line.strip()
        if not line or line.lower().startswith("list"):
            continue
        parts = line.split()
        if len(parts) < 2 or parts[1] != "device":
            continue
        serial = parts[0]
        model = None
        for token in parts[2:]:
            if token.startswith("model:"):
                model = token.split(":", 1)[1]
                break
        devices.append({"serial": serial, "model": model})
    return devices


def pick_device(serial: str | None = None) -> dict | None:
    devices = list_devices()
    if not devices:
        return None
    if serial:
        return next((d for d in devices if d["serial"] == serial), None)
    for pref in PREFERRED_SERIALS:
        hit = next((d for d in devices if d["serial"] == pref), None)
        if hit:
            return hit
    return devices[0]


def parse_wm_size(text: str) -> tuple[int, int] | None:
    override = re.search(r"Override size:\s*(\d+)x(\d+)", text, re.I)
    if override:
        return int(override.group(1)), int(override.group(2))
    physical = re.search(r"Physical size:\s*(\d+)x(\d+)", text, re.I)
    if physical:
        return int(physical.group(1)), int(physical.group(2))
    return None


def parse_wm_density(text: str) -> int | None:
    override = re.search(r"Override density:\s*(\d+)", text, re.I)
    if override:
        return int(override.group(1))
    physical = re.search(r"Physical density:\s*(\d+)", text, re.I)
    if physical:
        return int(physical.group(1))
    return None


def get_device_surface(serial: str | None = None) -> DeviceSurface:
    # Always return fallback to avoid any adb calls from editor/server (prevents d:adb flashes)
    # Real device info not needed for current wallpaper testing
    return DeviceSurface(
        connected=False,
        serial=None,
        model=None,
        width=FALLBACK_W,
        height=FALLBACK_H,
        density=None,
        source="fallback",
        message="adb disabled in device_surface to stop auto console flashes",
    )