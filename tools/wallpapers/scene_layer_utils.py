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