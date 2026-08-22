"""Activate the edited ready batch without re-uploading or rebuilding assets."""
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

READY = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/2_listo_para_subir")
SOURCE_RECEIPT = READY / "PUBLISH_RECEIPT_2026_08_11.json"
RECEIPT = READY / "ACTIVATE_AFTER_EDITOR_RECEIPT_2026_08_11.json"


def canvas_entry(sid: str, spec: dict) -> dict:
    return {
        "id": sid,
        "type": "canvas_scene",
        "schema": 1,
        "title": spec.get("title", {"es": sid}),
        "preview_url": f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{sid}_preview.webp",
        "image_url": f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{sid}.webp",
        "tags": spec.get("tags", ["original", "anime", "parallax"]),
        "category": spec.get("category", "original"),
        "featured": bool(spec.get("featured", False)),
        "glow_color": "#F472B6",
        "published": True,
        "description": "Colección Noches de Seda · edición aprobada en Pixel Studio.",
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{sid}.json",
        "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def main() -> None:
    source = json.loads(SOURCE_RECEIPT.read_text(encoding="utf-8"))
    ids = source["scene_ids"]
    if len(ids) != 97 or len(set(ids)) != 97:
        raise RuntimeError("Unexpected batch receipt")
    canvas_ids = [sid for sid in ids if sid.endswith("_parallax")]
    if len(canvas_ids) != 23:
        raise RuntimeError("Unexpected canvas count")

    # Preserve every editor adjustment: only flip the visibility field.
    current_specs = {}
    for sid in canvas_ids:
        spec = get_json(SCENES_BUCKET, f"{sid}.json")
        if spec.get("type") != "canvas_scene" or len(spec.get("image_layers", [])) != 6:
            raise RuntimeError(f"Invalid edited spec: {sid}")
        spec["published"] = True
        put_json(SCENES_BUCKET, f"{sid}.json", spec)
        current_specs[sid] = spec

    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    by_id = {item.get("id"): item for item in catalog.get("items", [])}
    restored = []
    for sid in canvas_ids:
        if sid in by_id:
            by_id[sid]["published"] = True
        else:
            item = canvas_entry(sid, current_specs[sid])
            catalog["items"].insert(0, item)
            by_id[sid] = item
            restored.append(sid)
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    conn = connect()
    cur = conn.cursor()
    cur.execute(
        "UPDATE wallpapers SET published=true, updated_at=now() "
        "WHERE id=ANY(%s) RETURNING id,published",
        (ids,),
    )
    rows = cur.fetchall()
    if len(rows) != 97 or any(not row[1] for row in rows):
        conn.rollback()
        raise RuntimeError(f"Postgres activation failed: {len(rows)} rows")
    conn.commit()
    cur.close()
    conn.close()

    fcm = send_catalog_invalidate("wallpapers")
    receipt = {
        "activated_at": datetime.now(timezone.utc).isoformat(),
        "total_public": 97,
        "canvas_public": 23,
        "catalog_version": catalog["version"],
        "restored_catalog_entries": restored,
        "preserved_editor_specs": True,
        "fcm": bool(fcm),
        "scene_ids": ids,
    }
    RECEIPT.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in receipt.items() if k != "scene_ids"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
