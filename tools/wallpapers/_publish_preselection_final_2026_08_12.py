"""Publish only the final approved sensual_collection_111 selection.

Preserves all Pixel Studio layer edits. Rejected scenes are explicitly kept
hidden. The review file in Drive is the allowlist/source of truth.
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, get_json, put_json

PIPELINE = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers")
REVIEW = PIPELINE / "1_por_editar/sensual_collection_111/REVISION_ESCENAS.json"
READY = PIPELINE / "2_listo_para_subir"
RECEIPT = READY / "PUBLISH_FINAL_SELECTION_2026_08_12.json"


def meta_id(folder_id: str) -> str:
    meta = READY / "sensual_collection_111/scenes" / folder_id / "METADATA.json"
    return json.loads(meta.read_text(encoding="utf-8"))["id"]


def catalog_entry(sid: str, spec: dict, old: dict | None) -> dict:
    bg = spec.get("background", {}) or {}
    item = dict(old or {})
    item.update({
        "id": sid,
        "type": "canvas_scene",
        "schema": spec.get("schema_version", 1),
        "title": spec.get("title", {"es": sid}),
        "preview_url": bg.get("preview_url") or
            f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{sid}_preview.webp",
        "image_url": bg.get("url") or
            f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{sid}.webp",
        "tags": spec.get("tags", ["original", "anime", "parallax"]),
        "category": spec.get("category", "original"),
        "featured": bool(spec.get("featured", False)),
        "published": True,
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{sid}.json",
    })
    item.setdefault("created_at", datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    if spec.get("description"):
        item["description"] = spec["description"]
    if spec.get("description_rich"):
        item["description_rich"] = spec["description_rich"]
    return item


def main() -> None:
    review = json.loads(REVIEW.read_text(encoding="utf-8"))["scenes"]
    approved_folders = [k for k, v in review.items() if v.get("status") == "aprobada"]
    rejected_folders = [k for k, v in review.items() if v.get("status") == "rechazada"]
    approved = [meta_id(x) for x in approved_folders]
    rejected = [meta_id(x) for x in rejected_folders]
    counts = {
        "static": sum(x.endswith("_static") for x in approved),
        "panoramic": sum(x.endswith("_panorama") for x in approved),
        "canvas_scene": sum(x.endswith("_parallax") for x in approved),
    }
    if len(approved) != 47 or len(rejected) != 22 or counts != {
        "static": 18, "panoramic": 15, "canvas_scene": 14,
    }:
        raise RuntimeError(f"Unexpected final selection: {len(approved)=} {len(rejected)=} {counts=}")

    canvas_approved = [x for x in approved if x.endswith("_parallax")]
    canvas_rejected = [x for x in rejected if x.endswith("_parallax")]
    specs = {}
    for sid in canvas_approved + canvas_rejected:
        spec = get_json(SCENES_BUCKET, f"{sid}.json")
        if spec.get("type") != "canvas_scene" or len(spec.get("image_layers", [])) != 6:
            raise RuntimeError(f"Invalid edited spec: {sid}")
        spec["published"] = sid in canvas_approved
        put_json(SCENES_BUCKET, f"{sid}.json", spec)
        specs[sid] = spec

    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    existing = {x.get("id"): x for x in catalog.get("items", [])}
    remove = set(canvas_approved + canvas_rejected)
    items = [x for x in catalog.get("items", []) if x.get("id") not in remove]
    items = [catalog_entry(sid, specs[sid], existing.get(sid)) for sid in canvas_approved] + items
    catalog["items"] = items
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1
    catalog["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    conn = connect()
    cur = conn.cursor()
    try:
        cur.execute(
            "UPDATE wallpapers SET published=true, updated_at=now() "
            "WHERE id=ANY(%s) RETURNING id,published", (approved,),
        )
        on = cur.fetchall()
        cur.execute(
            "UPDATE wallpapers SET published=false, daily_eligible=false, featured=false, updated_at=now() "
            "WHERE id=ANY(%s) RETURNING id,published", (rejected,),
        )
        off = cur.fetchall()
        if len(on) != 47 or any(not x[1] for x in on):
            raise RuntimeError(f"Approved activation failed: {len(on)}")
        if len(off) != 22 or any(x[1] for x in off):
            raise RuntimeError(f"Rejected hiding failed: {len(off)}")
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()

    fcm = bool(send_catalog_invalidate("wallpapers"))
    receipt = {
        "published_at": datetime.now(timezone.utc).isoformat(),
        "approved_total": 47,
        "rejected_total": 22,
        "counts": counts,
        "catalog_version": catalog["version"],
        "preserved_editor_specs": True,
        "fcm": fcm,
        "approved_ids": approved,
        "rejected_ids": rejected,
    }
    RECEIPT.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in receipt.items() if not k.endswith("_ids")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
