"""Instala la revision privada Supergirl slow-motion en el Huawei conectado."""
from __future__ import annotations

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
SID = "supergirl_crystal_hope_parallax_v2"
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public"


def adb(*args: str, capture: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        [ADB, "-s", SERIAL, *args], check=True,
        capture_output=capture, text=False,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )


def fetch(url: str) -> bytes:
    separator = "&" if "?" in url else "?"
    url = f"{url}{separator}nc={time.time_ns()}"
    req = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read()


def set_pref(root: ET.Element, tag: str, name: str, value: str) -> None:
    current = next((node for node in root if node.get("name") == name), None)
    if current is not None:
        root.remove(current)
    node = ET.SubElement(root, tag, {"name": name})
    if tag == "string":
        node.text = value
    else:
        node.set("value", value)


def main() -> None:
    spec_url = f"{PROJECT}/wallpaper-scenes/{SID}.json?qa=1"
    spec_bytes = fetch(spec_url)
    spec = json.loads(spec_bytes.decode("utf-8"))
    if spec.get("published") is not False:
        raise RuntimeError("La escena QA no esta marcada como privada")
    if len(spec.get("image_layers", [])) != 15:
        raise RuntimeError("Inventario inesperado de capas")

    with tempfile.TemporaryDirectory(prefix="pixora_supergirl_v2_") as temp_name:
        temp = Path(temp_name)
        (temp / f"{SID}.json").write_bytes(spec_bytes)
        flat = fetch(f"{PROJECT}/wallpaper-images/{SID}.webp?qa=1")
        (temp / f"{SID}.webp").write_bytes(flat)

        layer_files = []
        for layer in spec["image_layers"]:
            target = temp / f"{layer['key']}.webp"
            target.write_bytes(fetch(f"{layer['url']}?qa=1"))
            layer_files.append(target)

        prefs_raw = adb(
            "shell", "run-as", PKG, "cat", "shared_prefs/pixora_live.xml",
            capture=True,
        ).stdout
        prefs_tree = ET.ElementTree(ET.fromstring(prefs_raw))
        root = prefs_tree.getroot()
        set_pref(root, "string", "wallpaper_path", f"/data/user/0/{PKG}/files/{SID}.webp")
        set_pref(root, "string", "scene_id", SID)
        set_pref(root, "string", "content_id", SID)
        set_pref(root, "string", "glow_color", "#55DDF5")
        set_pref(root, "boolean", "interactive", "false")
        prefs_path = temp / "pixora_live.xml"
        prefs_tree.write(prefs_path, encoding="utf-8", xml_declaration=True)

        remote = "/sdcard/Download/pixora_supergirl_v2"
        adb("shell", "mkdir", "-p", remote)
        adb("push", str(temp / f"{SID}.json"), f"{remote}/{SID}.json")
        adb("push", str(temp / f"{SID}.webp"), f"{remote}/{SID}.webp")
        adb("push", str(prefs_path), f"{remote}/pixora_live.xml")
        for file in layer_files:
            adb("push", str(file), f"{remote}/{file.name}")

        layer_dir = f"files/scene_layers/{SID}"
        adb("shell", "run-as", PKG, "mkdir", "-p", "files/scene_specs", layer_dir)
        adb("shell", "run-as", PKG, "cp", f"{remote}/{SID}.json", f"files/scene_specs/{SID}.json")
        adb("shell", "run-as", PKG, "cp", f"{remote}/{SID}.webp", f"files/{SID}.webp")
        for file in layer_files:
            adb("shell", "run-as", PKG, "cp", f"{remote}/{file.name}", f"{layer_dir}/{file.name}")

        adb("shell", "am", "force-stop", PKG)
        adb("shell", "run-as", PKG, "cp", f"{remote}/pixora_live.xml", "shared_prefs/pixora_live.xml")
        adb("shell", "run-as", PKG, "chmod", "660", "shared_prefs/pixora_live.xml")

        pid = subprocess.run(
            [ADB, "-s", SERIAL, "shell", "pidof", f"{PKG}:wallpaper"],
            capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW,
        ).stdout.strip()
        if pid:
            adb("shell", "run-as", PKG, "kill", pid)
        adb("shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")

    print(json.dumps({
        "device": SERIAL,
        "scene_id": SID,
        "layers": len(spec["image_layers"]),
        "private_qa": True,
    }, indent=2))


if __name__ == "__main__":
    main()
