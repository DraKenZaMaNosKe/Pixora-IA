"""Promote the approved Gatitos baile cosmico scene to production."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json

SID = "gatitos_baile_cosmico"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatitos_baile_cosmico")


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one catalog entry, found {len(matches)}")
    sprites = spec.get("sprites", [])
    if len(sprites) != 1 or sprites[0].get("frame_skip") != 2:
        raise RuntimeError("Unexpected sprite configuration; publication cancelled")
    if len(spec.get("image_layers", [])) != 3:
        raise RuntimeError("Unexpected layer count; publication cancelled")

    spec["published"] = True
    matches[0]["published"] = True
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    conn = connect()
    cur = conn.cursor()
    cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING id,published", (SID,))
    row = cur.fetchone()
    if not row:
        conn.rollback()
        raise RuntimeError("Postgres row not found")
    conn.commit()
    cur.close()
    conn.close()
    fcm = send_catalog_invalidate("wallpapers")

    remote_spec = get_json(SCENES_BUCKET, f"{SID}.json")
    remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
    remote_matches = [item for item in remote_catalog.get("items", []) if item.get("id") == SID]
    if not remote_spec.get("published") or len(remote_matches) != 1 or not remote_matches[0].get("published"):
        raise RuntimeError("Remote publication verification failed")

    receipt = {
        "scene_id": SID,
        "published_at": datetime.now(timezone.utc).isoformat(),
        "catalog_version": remote_catalog.get("version"),
        "catalog_published": True,
        "scene_spec_published": True,
        "postgres_published": bool(row[1]),
        "frame_skip": sprites[0].get("frame_skip"),
        "frames": 12,
        "fcm_catalog_invalidate": fcm,
    }
    (ROOT / "SCENE_SPEC_PRODUCTION.json").write_text(
        json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "PUBLISH_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
