"""Pixora unified content publisher.

One CLI to upload any kind of content to Supabase + maintain the canonical
catalog_index.json. Replaces the patchwork of one-off upload scripts.

Usage:
    python tools/pixora_publish.py scene docs/scenes/cherry_blossom.json
    python tools/pixora_publish.py shader android-shaders/snow_storm.glsl
    python tools/pixora_publish.py rebuild-index   # regenerates catalog_index.json
                                                    # from current bucket state
    python tools/pixora_publish.py list             # shows current catalog

Buckets:
    wallpaper-images/   ← bg images, previews, catalog_index.json
    wallpaper-scenes/   ← per-scene JSON specs
    wallpaper-shaders/  ← .glsl files + manifest.json
    wallpaper-sprites/  ← sprite ZIPs + manifest.json
    aura-audio/         ← AURA tracks (separate flow)
    ringtones/          ← MP3s + pack manifests
"""

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path
import requests

SUPABASE_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"
SERVICE_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6"
    "InZ6dXd2c21seWlnanRzZWFyeHltIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6"
    "MTc1ODY0ODcwOSwiZXhwIjoyMDc0MjI0NzA5fQ."
    "xDs_HCkdqcEVJktzTdjGIXnG-V--j86jbkrUA4SjAOs"
)
HEADERS = {"Authorization": f"Bearer {SERVICE_KEY}", "apikey": SERVICE_KEY}

CATALOG_INDEX_BUCKET = "wallpaper-images"
CATALOG_INDEX_KEY = "catalog_index.json"


# ── Generic Supabase Storage helpers ──────────────────────────────────

def _put(bucket: str, key: str, body: bytes, content_type: str) -> bool:
    url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{key}"
    h = {**HEADERS, "Content-Type": content_type, "x-upsert": "true"}
    for attempt in range(4):
        try:
            r = requests.put(url, headers=h, data=body, timeout=120)
            if r.status_code in (200, 201):
                return True
            print(f"  attempt {attempt}: HTTP {r.status_code} {r.text[:120]}",
                  file=sys.stderr)
        except Exception as e:
            print(f"  attempt {attempt}: {e}", file=sys.stderr)
        time.sleep(2 * (attempt + 1))
    return False


def _get_json(bucket: str, key: str) -> dict | None:
    url = f"{SUPABASE_URL}/storage/v1/object/public/{bucket}/{key}"
    try:
        r = requests.get(url, timeout=30)
        return r.json() if r.status_code == 200 else None
    except Exception:
        return None


def _verify(bucket: str, key: str) -> bool:
    url = f"{SUPABASE_URL}/storage/v1/object/public/{bucket}/{key}"
    try:
        return requests.head(url, timeout=15).status_code == 200
    except Exception:
        return False


def _public_url(bucket: str, key: str) -> str:
    return f"{SUPABASE_URL}/storage/v1/object/public/{bucket}/{key}"


# ── Catalog index ──────────────────────────────────────────────────────

def _load_index() -> dict:
    idx = _get_json(CATALOG_INDEX_BUCKET, CATALOG_INDEX_KEY)
    if idx is None:
        idx = {"version": 0, "updated_at": "", "items": []}
    return idx


def _save_index(idx: dict) -> bool:
    body = json.dumps(idx, indent=2, ensure_ascii=False).encode("utf-8")
    ok = _put(CATALOG_INDEX_BUCKET, CATALOG_INDEX_KEY, body, "application/json")
    if ok:
        size_kb = len(body) / 1024
        print(f"  catalog_index.json updated → v{idx['version']} "
              f"({len(idx['items'])} items, {size_kb:.1f} KB)")
    return ok


def _upsert_index_entry(idx: dict, entry: dict) -> dict:
    """Insert or replace an entry in the index. Bumps version + updated_at."""
    items = [it for it in idx.get("items", []) if it.get("id") != entry["id"]]
    items.append(entry)
    items.sort(key=lambda it: (it.get("type", ""), it.get("id", "")))
    idx["items"] = items
    idx["version"] = int(idx.get("version", 0)) + 1
    idx["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    return idx


# ── Subcommand: scene ──────────────────────────────────────────────────

def cmd_scene(spec_path: Path) -> int:
    """Upload a canvas_scene/shader_scene JSON spec + register in index."""
    if not spec_path.is_file():
        print(f"FAIL: {spec_path} not found"); return 1
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    sid = spec.get("id")
    stype = spec.get("type")
    schema = spec.get("schema_version", 1)
    if not sid or not stype:
        print("FAIL: spec missing id or type"); return 1
    if stype not in ("canvas_scene", "shader_scene"):
        print(f"FAIL: unsupported type {stype}"); return 1

    print(f"Publishing {stype}: {sid}")
    body = json.dumps(spec, indent=2, ensure_ascii=False).encode("utf-8")
    if not _put("wallpaper-scenes", f"{sid}.json", body, "application/json"):
        print(f"FAIL upload"); return 1
    spec_url = _public_url("wallpaper-scenes", f"{sid}.json")
    print(f"  spec → {spec_url}")

    title = spec.get("title", {"en": sid})
    bg = spec.get("background", {})
    preview_url = (
        bg.get("preview_url")
        or bg.get("url", "").replace("pixora_", "").replace(".webp", "_preview.webp")
        or ""
    )
    entry = {
        "id": sid,
        "type": stype,
        "schema": schema,
        "title": title,
        "preview_url": preview_url,
        "tags": spec.get("tags", []),
        "category": spec.get("category"),
        "featured": spec.get("featured", False),
        "spec_url": spec_url,
    }
    idx = _load_index()
    _upsert_index_entry(idx, entry)
    if not _save_index(idx): return 1
    return 0


# ── Subcommand: shader ─────────────────────────────────────────────────

def cmd_shader(glsl_path: Path) -> int:
    """Upload a .glsl shader + update wallpaper-shaders/manifest.json."""
    if not glsl_path.is_file():
        print(f"FAIL: {glsl_path} not found"); return 1
    name = glsl_path.stem
    raw = glsl_path.read_bytes()
    if not _put("wallpaper-shaders", glsl_path.name, raw, "text/plain"):
        return 1
    manifest = _get_json("wallpaper-shaders", "manifest.json") or {}
    manifest[name] = {
        "url": _public_url("wallpaper-shaders", glsl_path.name),
        "size": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest()[:16],
    }
    _put("wallpaper-shaders", "manifest.json",
         json.dumps(manifest, indent=2).encode("utf-8"),
         "application/json")
    print(f"  shader {name} ({len(raw)} B) — manifest now has {len(manifest)} entries")
    return 0


# ── Subcommand: rebuild-index ──────────────────────────────────────────

def cmd_rebuild_index() -> int:
    """Walk wallpaper-scenes/ and rebuild catalog_index.json from scratch."""
    print("Listing wallpaper-scenes/ …")
    url = f"{SUPABASE_URL}/storage/v1/object/list/wallpaper-scenes"
    r = requests.post(url, headers={**HEADERS, "Content-Type": "application/json"},
                      json={"prefix": "", "limit": 1000}, timeout=30)
    if r.status_code != 200:
        print(f"FAIL list: {r.status_code} {r.text[:200]}"); return 1
    files = [f for f in r.json() if f["name"].endswith(".json")]
    print(f"  {len(files)} scene specs found")

    items = []
    for f in files:
        spec = _get_json("wallpaper-scenes", f["name"])
        if not spec:
            print(f"  SKIP {f['name']} — fetch failed"); continue
        sid = spec.get("id"); stype = spec.get("type")
        if not sid or not stype:
            print(f"  SKIP {f['name']} — missing id/type"); continue
        bg = spec.get("background", {})
        items.append({
            "id": sid, "type": stype,
            "schema": spec.get("schema_version", 1),
            "title": spec.get("title", {"en": sid}),
            "preview_url": bg.get("preview_url",
                bg.get("url", "").replace(".webp", "_preview.webp")),
            "tags": spec.get("tags", []),
            "category": spec.get("category"),
            "featured": spec.get("featured", False),
            "spec_url": _public_url("wallpaper-scenes", f["name"]),
        })
    items.sort(key=lambda it: (it["type"], it["id"]))
    idx = {
        "version": int(_load_index().get("version", 0)) + 1,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "items": items,
    }
    if not _save_index(idx): return 1
    return 0


# ── Subcommand: list ───────────────────────────────────────────────────

def cmd_list() -> int:
    idx = _load_index()
    print(f"catalog_index.json — v{idx.get('version', 0)} "
          f"updated {idx.get('updated_at', 'unknown')}")
    print(f"  {len(idx.get('items', []))} items:")
    for it in idx.get("items", []):
        title = it.get("title", {}).get("en") or it.get("id")
        print(f"    [{it.get('type','?'):14s}] {it['id']:20s} — {title}")
    return 0


# ── Main ────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(prog="pixora_publish",
        description="Publish content to Supabase + maintain catalog_index.json")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scene", help="upload a scene JSON spec")
    s.add_argument("path", type=Path)
    s = sub.add_parser("shader", help="upload a .glsl shader")
    s.add_argument("path", type=Path)
    sub.add_parser("rebuild-index", help="regenerate catalog_index.json")
    sub.add_parser("list", help="print current catalog index")
    args = p.parse_args()
    if args.cmd == "scene":
        return cmd_scene(args.path)
    if args.cmd == "shader":
        return cmd_shader(args.path)
    if args.cmd == "rebuild-index":
        return cmd_rebuild_index()
    if args.cmd == "list":
        return cmd_list()
    return 1


if __name__ == "__main__":
    sys.exit(main())
