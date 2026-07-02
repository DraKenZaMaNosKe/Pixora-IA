"""
Upload sprite ZIP packs to wallpaper-sprites + patch manifest + scene spec.

Used by the sprite editor after GIF/video frame extraction workflows.
Frame naming: frame_001.png, frame_002.png, ... (PNG with alpha).
"""
from __future__ import annotations

import io
import json
import re
import zipfile
from pathlib import Path
from typing import Any

from scene_layer_utils import fetch_scene_spec, load_service_key, put_scene_spec, put_storage_bytes

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SPRITES_BUCKET = "wallpaper-sprites"
MANIFEST_KEY = "manifest.json"

_SAFE_KEY_RE = re.compile(r"^[a-z0-9_]{1,48}$")


def _public_url(bucket: str, remote: str) -> str:
    return f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"


def fetch_sprite_manifest(service_key: str | None = None) -> dict:
    import urllib.request

    url = _public_url(SPRITES_BUCKET, MANIFEST_KEY)
    with urllib.request.urlopen(url, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def put_sprite_manifest(manifest: dict, service_key: str | None = None) -> None:
    body = json.dumps(manifest, indent=2, ensure_ascii=False).encode("utf-8")
    put_storage_bytes(SPRITES_BUCKET, MANIFEST_KEY, body, "application/json", service_key)


def inspect_sprite_zip(zip_path: Path) -> dict[str, Any]:
    if not zip_path.is_file():
        raise FileNotFoundError(zip_path)
    with zipfile.ZipFile(zip_path, "r") as zf:
        pngs = sorted(n for n in zf.namelist() if n.lower().endswith(".png") and not n.startswith("__"))
    if not pngs:
        raise ValueError("ZIP must contain at least one PNG frame")
    return {
        "frame_count": len(pngs),
        "zip_size": zip_path.stat().st_size,
        "frames": pngs[:5],
    }


def normalize_sprite_zip(src: Path, dest: Path | None = None) -> Path:
    """
    Re-pack ZIP with canonical frame_001.png naming if needed.
    Returns path to upload-ready zip (may be src if already canonical).
    """
    out = dest or src
    with zipfile.ZipFile(src, "r") as zf:
        pngs = sorted(
            n for n in zf.namelist()
            if n.lower().endswith(".png") and not n.startswith("__")
        )
        if not pngs:
            raise ValueError("no PNG frames in zip")

        canonical = all(re.search(r"frame_\d+\.png$", n, re.I) for n in pngs)
        if canonical and (dest is None or dest == src):
            return src

        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out_zf:
            for i, name in enumerate(pngs, start=1):
                data = zf.read(name)
                out_zf.writestr(f"frame_{i:03d}.png", data)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(buf.getvalue())
    return out


def upload_sprite_pack(
    manifest_key: str,
    zip_path: Path,
    *,
    service_key: str | None = None,
) -> dict[str, Any]:
    if not _SAFE_KEY_RE.match(manifest_key):
        raise ValueError(f"invalid manifest_key: {manifest_key}")

    normalized = normalize_sprite_zip(zip_path)
    info = inspect_sprite_zip(normalized)
    zip_remote = f"{manifest_key}.zip"
    put_storage_bytes(
        SPRITES_BUCKET,
        zip_remote,
        normalized.read_bytes(),
        "application/zip",
        service_key,
    )

    manifest = fetch_sprite_manifest(service_key)
    manifest[manifest_key] = {
        "zip": zip_remote,
        "frames": info["frame_count"],
        "size": info["zip_size"],
    }
    put_sprite_manifest(manifest, service_key)
    return {
        "manifest_key": manifest_key,
        "zip": zip_remote,
        "frames": info["frame_count"],
        "bytes": info["zip_size"],
    }


def find_sprite_by_manifest(spec: dict, manifest_key: str) -> dict | None:
    for sp in spec.get("sprites") or []:
        if isinstance(sp, dict) and sp.get("manifest_key") == manifest_key:
            return sp
    return None


def default_sprite_entry(name: str, manifest_key: str, frame_skip: float = 2.0) -> dict:
    return {
        "name": name,
        "manifest_key": manifest_key,
        "behavior": "static",
        "frame_skip": frame_skip,
        "params": {
            "x": 0.5,
            "y": 0.5,
            "scale": 0.001,
            "alpha": 255,
            "high_res": True,
        },
    }


def import_sprite_pack_to_scene(
    scene_id: str,
    zip_path: Path,
    action: str,
    *,
    manifest_key: str | None = None,
    sprite_name: str | None = None,
    frame_skip: float = 2.0,
    service_key: str | None = None,
) -> dict[str, Any]:
    """
    action: replace_sprite | add_sprite
    replace_sprite requires manifest_key of existing sprite in spec.
    add_sprite uses manifest_key or {scene_id}_{sprite_name}.
    """
    sk = service_key or load_service_key()
    spec = fetch_scene_spec(scene_id, sk)

    if action == "replace_sprite":
        if not manifest_key:
            raise ValueError("manifest_key required for replace_sprite")
        if not find_sprite_by_manifest(spec, manifest_key):
            raise ValueError(f"sprite {manifest_key!r} not in scene spec")
        pack = upload_sprite_pack(manifest_key, zip_path, service_key=sk)
        put_scene_spec(scene_id, spec, sk)
        return {
            "action": action,
            "scene_id": scene_id,
            "sprites": spec.get("sprites"),
            **pack,
        }

    if action == "add_sprite":
        name = (sprite_name or "sprite").strip().lower().replace(" ", "_")
        name = re.sub(r"[^a-z0-9_]", "_", name)[:32] or "sprite"
        mk = manifest_key or f"{scene_id}_{name}"
        if not _SAFE_KEY_RE.match(mk):
            raise ValueError(f"invalid manifest_key: {mk}")
        if find_sprite_by_manifest(spec, mk):
            raise ValueError(f"sprite {mk!r} already exists — use replace_sprite")

        pack = upload_sprite_pack(mk, zip_path, service_key=sk)
        entry = default_sprite_entry(name, mk, frame_skip=frame_skip)
        spec.setdefault("sprites", []).append(entry)
        put_scene_spec(scene_id, spec, sk)
        return {
            "action": action,
            "scene_id": scene_id,
            "sprite": entry,
            "sprites": spec.get("sprites"),
            **pack,
        }

    raise ValueError(f"unknown action: {action}")