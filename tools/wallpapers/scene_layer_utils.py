"""
Pixora canvas_scene image_layer helpers.

Bump `revision` on image_layers when an asset is replaced in-place (same URL).
Clients compare spec revision vs cached _meta.json and re-download without
renaming files to _v5/_v6.
"""
from __future__ import annotations

import json
import re
import urllib.request
from pathlib import Path
from typing import Any

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SCENES_BUCKET = "wallpaper-scenes"


def load_service_key(keys_path: Path | None = None) -> str:
    path = keys_path or Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
    txt = path.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt)
    if not m:
        raise RuntimeError("Service Role Key not found in KEYS_LOCAL.md")
    return m.group(1)


def find_layer(spec: dict, key: str) -> dict | None:
    for layer in spec.get("image_layers") or []:
        if isinstance(layer, dict) and layer.get("key") == key:
            return layer
    return None


def bump_layer_revisions(spec: dict, keys: list[str] | None = None) -> list[str]:
    """Increment revision on matching image_layers. Returns bumped keys."""
    key_set = set(keys) if keys else None
    bumped: list[str] = []
    for layer in spec.get("image_layers") or []:
        if not isinstance(layer, dict):
            continue
        k = layer.get("key")
        if not k or (key_set is not None and k not in key_set):
            continue
        layer["revision"] = int(layer.get("revision") or 0) + 1
        bumped.append(k)
    return bumped


def bump_layers_with_url_changes(old_spec: dict, new_layers: list[dict]) -> list[str]:
    """Bump revision only for layers whose url changed."""
    old_by_key = {
        l["key"]: l
        for l in (old_spec.get("image_layers") or [])
        if isinstance(l, dict) and l.get("key")
    }
    bumped: list[str] = []
    for layer in new_layers:
        if not isinstance(layer, dict):
            continue
        key = layer.get("key")
        if not key:
            continue
        old = old_by_key.get(key)
        if old and old.get("url") != layer.get("url"):
            layer["revision"] = int(layer.get("revision") or 0) + 1
            bumped.append(key)
    return bumped


def public_url(bucket: str, remote: str) -> str:
    return f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"


def layer_storage_target(layer: dict) -> tuple[str, str]:
    """Return (bucket, object_path) from a layer public URL."""
    url = layer.get("url") or ""
    marker = "/storage/v1/object/public/"
    if marker not in url:
        raise ValueError(f"Cannot parse layer url: {url}")
    rest = url.split(marker, 1)[1]
    bucket, _, path = rest.partition("/")
    if not bucket or not path:
        raise ValueError(f"Invalid layer url: {url}")
    return bucket, path


def fetch_scene_spec(scene_id: str, service_key: str | None = None) -> dict:
    url = public_url(SCENES_BUCKET, f"{scene_id}.json")
    with urllib.request.urlopen(url, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def put_scene_spec(scene_id: str, spec: dict, service_key: str | None = None) -> None:
    sk = service_key or load_service_key()
    payload = json.dumps(spec, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{SCENES_BUCKET}/{scene_id}.json",
        data=payload,
        method="PUT",
    )
    req.add_header("Authorization", f"Bearer {sk}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {SCENES_BUCKET}/{scene_id}.json -> {r.status}")


def put_storage_bytes(
    bucket: str,
    remote: str,
    body: bytes,
    content_type: str,
    service_key: str | None = None,
) -> int:
    sk = service_key or load_service_key()
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body,
        method="PUT",
    )
    req.add_header("Authorization", f"Bearer {sk}")
    req.add_header("Content-Type", content_type)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")
    return len(body)


def replace_scene_layer_asset(
    scene_id: str,
    layer_key: str,
    local_file: Path,
    *,
    service_key: str | None = None,
    content_type: str | None = None,
) -> dict[str, Any]:
    """
    Upsert a layer bitmap at the layer's existing URL, bump revision, save spec.
    Returns summary dict for API responses.
    """
    if not local_file.is_file():
        raise FileNotFoundError(local_file)
    sk = service_key or load_service_key()
    spec = fetch_scene_spec(scene_id, sk)
    layer = find_layer(spec, layer_key)
    if layer is None:
        raise ValueError(f"Layer {layer_key!r} not found in {scene_id}")

    bucket, remote = layer_storage_target(layer)
    body = local_file.read_bytes()
    ct = content_type or (
        "image/webp" if local_file.suffix.lower() == ".webp" else "image/png"
    )
    size = put_storage_bytes(bucket, remote, body, ct, sk)
    bumped = bump_layer_revisions(spec, [layer_key])
    put_scene_spec(scene_id, spec, sk)
    return {
        "scene_id": scene_id,
        "layer_key": layer_key,
        "bytes": size,
        "revision": layer.get("revision"),
        "bumped": bumped,
        "url": layer.get("url"),
    }


IMG_BUCKET = "wallpaper-images"


def prepare_image_webp(src: Path, dest: Path | None = None, *, quality: int = 88) -> Path:
    """Convert any supported image to WebP (RGBA preserved)."""
    try:
        from PIL import Image
    except ImportError as e:
        raise RuntimeError("Pillow required for image import") from e

    out = dest or src.with_suffix(".webp")
    img = Image.open(src)
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGBA")
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "WEBP", quality=quality, method=6)
    return out


def _upload_prepared_webp(
    scene_id: str,
    remote_name: str,
    webp_path: Path,
    service_key: str | None = None,
) -> tuple[str, int]:
    body = webp_path.read_bytes()
    put_storage_bytes(IMG_BUCKET, remote_name, body, "image/webp", service_key)
    return public_url(IMG_BUCKET, remote_name), len(body)


def add_scene_layer(
    scene_id: str,
    layer_key: str,
    local_file: Path,
    *,
    z: int = 1,
    layer_defaults: dict[str, Any] | None = None,
    service_key: str | None = None,
) -> dict[str, Any]:
    """Upload a new layer asset and append it to the scene spec."""
    sk = service_key or load_service_key()
    spec = fetch_scene_spec(scene_id, sk)
    if find_layer(spec, layer_key):
        raise ValueError(f"Layer {layer_key!r} already exists — use replace")

    webp = prepare_image_webp(local_file)
    remote = f"{scene_id}_{layer_key}.webp"
    url, size = _upload_prepared_webp(scene_id, remote, webp, sk)

    layer: dict[str, Any] = {
        "key": layer_key,
        "url": url,
        "z": z,
        "parallax_factor": 0.5,
        "scroll_factor": 0.5,
        "scale": 1.0,
        "offset_x_px": 0,
        "offset_y_px": 0,
        "revision": 1,
    }
    if layer_defaults:
        layer.update(layer_defaults)
    spec.setdefault("image_layers", []).append(layer)
    put_scene_spec(scene_id, spec, sk)
    return {
        "action": "add_layer",
        "scene_id": scene_id,
        "layer_key": layer_key,
        "bytes": size,
        "url": url,
        "revision": 1,
        "image_layers": spec.get("image_layers"),
    }


def replace_background_flat(
    scene_id: str,
    local_file: Path,
    *,
    service_key: str | None = None,
) -> dict[str, Any]:
    """Replace spec.background.url flat composite (same naming convention as publishers)."""
    sk = service_key or load_service_key()
    spec = fetch_scene_spec(scene_id, sk)
    webp = prepare_image_webp(local_file)
    remote = f"{scene_id}.webp"
    url, size = _upload_prepared_webp(scene_id, remote, webp, sk)
    bg = spec.setdefault("background", {})
    bg["url"] = url
    if not bg.get("preview_url"):
        prev_remote = f"pixora_{scene_id}_preview.webp"
        prev_url, _ = _upload_prepared_webp(scene_id, prev_remote, webp, sk)
        bg["preview_url"] = prev_url
    put_scene_spec(scene_id, spec, sk)
    return {
        "action": "background",
        "scene_id": scene_id,
        "bytes": size,
        "url": url,
        "background": bg,
    }


def import_image_to_scene(
    scene_id: str,
    local_file: Path,
    action: str,
    *,
    layer_key: str | None = None,
    new_layer_key: str | None = None,
    z: int = 1,
    service_key: str | None = None,
) -> dict[str, Any]:
    """
    action: replace_layer | add_layer | background
    """
    if action == "replace_layer":
        if not layer_key:
            raise ValueError("layer_key required for replace_layer")
        webp = prepare_image_webp(local_file)
        summary = replace_scene_layer_asset(
            scene_id, layer_key, webp, service_key=service_key, content_type="image/webp",
        )
        summary["action"] = action
        spec = fetch_scene_spec(scene_id, service_key or load_service_key())
        summary["image_layers"] = spec.get("image_layers")
        summary["background"] = spec.get("background")
        return summary
    if action == "add_layer":
        key = new_layer_key or layer_key
        if not key:
            raise ValueError("new_layer_key required for add_layer")
        return add_scene_layer(scene_id, key, local_file, z=z, service_key=service_key)
    if action == "background":
        return replace_background_flat(scene_id, local_file, service_key=service_key)
    raise ValueError(f"unknown action: {action}")