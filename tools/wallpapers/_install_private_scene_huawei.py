"""Instala cualquier canvas_scene privada en el Huawei de QA y la activa."""
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


ADB = r"C:/Users/lalo/AppData/Local/Android/Sdk/platform-tools/adb.exe"
SERIAL = "G2R4C17516000149"
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
    parser = argparse.ArgumentParser()
    parser.add_argument("scene_id")
    parser.add_argument("--expected-layers", type=int)
    parser.add_argument("--glow", default="#FF3526")
    args = parser.parse_args()
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

        raw = adb("shell", "run-as", PKG, "cat", "shared_prefs/pixora_live.xml", capture=True).stdout
        tree = ET.ElementTree(ET.fromstring(raw)); root = tree.getroot()
        set_pref(root, "string", "wallpaper_path", f"/data/user/0/{PKG}/files/{sid}.webp")
        set_pref(root, "string", "scene_id", sid)
        set_pref(root, "string", "content_id", sid)
        set_pref(root, "string", "glow_color", args.glow)
        set_pref(root, "boolean", "interactive", "false")
        prefs = tmp / "pixora_live.xml"; tree.write(prefs, encoding="utf-8", xml_declaration=True)

        remote = f"/sdcard/Download/pixora_qa_{sid}"
        adb("shell", "mkdir", "-p", remote)
        for path in [tmp / f"{sid}.json", tmp / f"{sid}.webp", prefs, *layer_files]:
            adb("push", str(path), f"{remote}/{path.name}")
        layer_dir = f"files/scene_layers/{sid}"
        adb("shell", "run-as", PKG, "mkdir", "-p", "files/scene_specs", layer_dir)
        adb("shell", "run-as", PKG, "cp", f"{remote}/{sid}.json", f"files/scene_specs/{sid}.json")
        adb("shell", "run-as", PKG, "cp", f"{remote}/{sid}.webp", f"files/{sid}.webp")
        for path in layer_files:
            adb("shell", "run-as", PKG, "cp", f"{remote}/{path.name}", f"{layer_dir}/{path.name}")
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
