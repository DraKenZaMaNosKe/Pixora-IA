"""Hide the uploaded batch so Eduardo can activate each item in Pixel Studio."""
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
HIDE_RECEIPT = READY / "HIDE_RECEIPT_2026_08_11.json"


def main() -> None:
    source = json.loads(SOURCE_RECEIPT.read_text(encoding="utf-8"))
    ids = source["scene_ids"]
    if len(ids) != 97 or len(set(ids)) != 97:
        raise RuntimeError("Unexpected source receipt; refusing visibility change")

    canvas_ids = [sid for sid in ids if sid.endswith("_parallax")]
    if len(canvas_ids) != 23:
        raise RuntimeError(f"Expected 23 canvas IDs, found {len(canvas_ids)}")

    # Keep each canvas scene editable but hidden from end users.
    for sid in canvas_ids:
        spec = get_json(SCENES_BUCKET, f"{sid}.json")
        if spec.get("type") != "canvas_scene":
            raise RuntimeError(f"Unexpected spec type for {sid}")
        spec["published"] = False
        put_json(SCENES_BUCKET, f"{sid}.json", spec)

    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    found = 0
    present = set()
    for item in catalog.get("items", []):
        if item.get("id") in set(canvas_ids):
            item["published"] = False
            found += 1
            present.add(item.get("id"))
    # Pixel Studio may have removed an entry while editing. Restore any missing
    # canvas cartridge as hidden so it remains available for manual activation.
    for sid in sorted(set(canvas_ids) - present):
        spec = get_json(SCENES_BUCKET, f"{sid}.json")
        catalog["items"].insert(0, {
            "id": sid,
            "type": "canvas_scene",
            "schema": 1,
            "title": spec.get("title", {"es": sid}),
            "preview_url": f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{sid}_preview.webp",
            "image_url": f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{sid}.webp",
            "tags": spec.get("tags", ["original", "anime", "parallax"]),
            "category": spec.get("category", "original"),
            "featured": False,
            "glow_color": "#F472B6",
            "published": False,
            "description": "Colección Noches de Seda · pendiente de activación manual.",
            "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{sid}.json",
            "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        })
        found += 1
    if found != 23:
        raise RuntimeError(f"Expected 23 catalog canvas entries after restore, found {found}")
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    conn = connect()
    cur = conn.cursor()
    cur.execute(
        "UPDATE wallpapers SET published=false, updated_at=now() "
        "WHERE id=ANY(%s) RETURNING id,published",
        (ids,),
    )
    rows = cur.fetchall()
    if len(rows) != 97 or any(row[1] for row in rows):
        conn.rollback()
        raise RuntimeError(f"Postgres hide verification failed: {len(rows)} rows")
    conn.commit()
    cur.close()
    conn.close()

    fcm = send_catalog_invalidate("wallpapers")
    receipt = {
        "hidden_at": datetime.now(timezone.utc).isoformat(),
        "total_hidden": 97,
        "canvas_specs_hidden": 23,
        "catalog_version": catalog["version"],
        "fcm": bool(fcm),
        "activation_mode": "manual_one_by_one_in_pixel_studio",
        "scene_ids": ids,
    }
    HIDE_RECEIPT.write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({k: v for k, v in receipt.items() if k != "scene_ids"}, indent=2))


if __name__ == "__main__":
    main()
