"""Instala cualquier canvas_scene privada en un dispositivo Android de QA."""
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from io import BytesIO
from pathlib import Path


ADB = r"C:/Users/lalo/AppData/Local/Android/Sdk/platform-tools/adb.exe"
DEFAULT_SERIAL = "G2R4C17516000149"
SERIAL = DEFAULT_SERIAL
PKG = "com.orbix.pixora"
PUBLIC = "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public"


def adb(*args: str, capture: bool = False, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        [ADB, "-s", SERIAL, *args], check=check,
        capture_output=capture, text=False,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )


def fetch(url: str) -> bytes:
    sep = "&" if "?" in url else "?"
    req = urllib.request.Request(f"{url}{sep}nc={time.time_ns()}", headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=90) as response:
        return response.read()


def set_pref(root: ET.Element, tag: str, name: str, value: str) -> None:
    old = next((node for node in root if node.get("name") == name), None)
    if old is not None:
        root.remove(old)
    node = ET.SubElement(root, tag, {"name": name})
    if tag == "string": node.text = value
    else: node.set("value", value)


def main() -> None:
    global SERIAL
    parser = argparse.ArgumentParser()
    parser.add_argument("scene_id")
    parser.add_argument("--serial", default=DEFAULT_SERIAL)
    parser.add_argument("--expected-layers", type=int)
    parser.add_argument("--glow", default="#FF3526")
    args = parser.parse_args()
    SERIAL = args.serial
    sid = args.scene_id

    spec_bytes = fetch(f"{PUBLIC}/wallpaper-scenes/{sid}.json")
    spec = json.loads(spec_bytes.decode("utf-8"))
    layers = spec.get("image_layers", [])
    if spec.get("published") is not False:
        raise RuntimeError("La escena no esta marcada como privada")
    if args.expected_layers is not None and len(layers) != args.expected_layers:
        raise RuntimeError(f"Capas esperadas={args.expected_layers}, encontradas={len(layers)}")

    with tempfile.TemporaryDirectory(prefix=f"pixora_{sid}_") as tmp_name:
        tmp = Path(tmp_name)
        (tmp / f"{sid}.json").write_bytes(spec_bytes)
        (tmp / f"{sid}.webp").write_bytes(fetch(f"{PUBLIC}/wallpaper-images/{sid}.webp"))
        layer_files = []
        for layer in layers:
            path = tmp / f"{layer['key']}.webp"
            path.write_bytes(fetch(layer["url"]))
            layer_files.append(path)

        sprite_packs = []
        manifest_keys = {
            item.get("manifest_key") for item in spec.get("sprites", [])
            if isinstance(item, dict) and item.get("manifest_key")
        }
        if manifest_keys:
            manifest = json.loads(fetch(f"{PUBLIC}/wallpaper-sprites/manifest.json").decode("utf-8"))
            for key in sorted(manifest_keys):
                info = manifest.get(key)
                if not isinstance(info, dict) or not info.get("zip"):
                    raise RuntimeError(f"Sprite manifest incompleto para {key}")
                pack_dir = tmp / "sprites" / key
                pack_dir.mkdir(parents=True, exist_ok=True)
                with zipfile.ZipFile(BytesIO(fetch(f"{PUBLIC}/wallpaper-sprites/{info['zip']}"))) as archive:
                    for member in archive.infolist():
                        if not member.is_dir() and member.filename.lower().endswith(".png"):
                            (pack_dir / Path(member.filename).name).write_bytes(archive.read(member))
                (pack_dir / ".pixora_sprite_meta.json").write_text(
                    json.dumps({"frames": int(info.get("frames", 0)), "zip_size": int(info.get("size", 0))}),
                    encoding="utf-8",
                )
                sprite_packs.append((key, pack_dir))

        pref_read = adb(
            "shell", "run-as", PKG, "cat", "shared_prefs/pixora_live.xml",
            capture=True, check=False,
        )
        raw = pref_read.stdout.strip()
        root = ET.fromstring(raw) if pref_read.returncode == 0 and raw else ET.Element("map")
        tree = ET.ElementTree(root)
        set_pref(root, "string", "wallpaper_path", f"/data/user/0/{PKG}/files/{sid}.webp")
        set_pref(root, "string", "scene_id", sid)
        set_pref(root, "string", "content_id", sid)
        set_pref(root, "string", "glow_color", args.glow)
        set_pref(root, "boolean", "interactive", "false")
        prefs = tmp / "pixora_live.xml"; tree.write(prefs, encoding="utf-8", xml_declaration=True)

        remote = f"/data/local/tmp/pixora_qa_{sid}"
        adb("shell", "mkdir", "-p", remote)
        for path in [tmp / f"{sid}.json", tmp / f"{sid}.webp", prefs, *layer_files]:
            adb("push", str(path), f"{remote}/{path.name}")
        layer_dir = f"files/scene_layers/{sid}"
        adb("shell", "run-as", PKG, "mkdir", "-p", "files/scene_specs", layer_dir)
        adb("shell", "run-as", PKG, "cp", f"{remote}/{sid}.json", f"files/scene_specs/{sid}.json")
        adb("shell", "run-as", PKG, "cp", f"{remote}/{sid}.webp", f"files/{sid}.webp")
        for path in layer_files:
            adb("shell", "run-as", PKG, "cp", f"{remote}/{path.name}", f"{layer_dir}/{path.name}")
        for key, pack_dir in sprite_packs:
            sprite_dir = f"files/sprites/{key}"
            adb("shell", "run-as", PKG, "mkdir", "-p", sprite_dir)
            for path in pack_dir.iterdir():
                remote_name = f"sprite_{key.replace('/', '_')}_{path.name}"
                adb("push", str(path), f"{remote}/{remote_name}")
                adb("shell", "run-as", PKG, "cp", f"{remote}/{remote_name}", f"{sprite_dir}/{path.name}")
        adb("shell", "am", "force-stop", PKG)
        adb("shell", "run-as", PKG, "cp", f"{remote}/pixora_live.xml", "shared_prefs/pixora_live.xml")
        adb("shell", "run-as", PKG, "chmod", "660", "shared_prefs/pixora_live.xml")
        adb("shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")

    adb("shell", "am", "start", "-a", "android.service.wallpaper.CHANGE_LIVE_WALLPAPER",
        "--ecn", "android.service.wallpaper.extra.LIVE_WALLPAPER_COMPONENT",
        f"{PKG}/.PixoraWallpaperService")
    time.sleep(3)
    adb("shell", "input", "tap", "540", "1740")
    time.sleep(5)
    adb("shell", "input", "keyevent", "3")
    print(json.dumps({"device": SERIAL, "scene_id": sid, "layers": len(layers), "private_qa": True}, indent=2))


if __name__ == "__main__":
    main()
