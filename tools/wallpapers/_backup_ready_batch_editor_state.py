"""Snapshot current Pixel Studio edits without changing remote visibility."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from apply_migration import connect
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json

READY = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/2_listo_para_subir")
SOURCE = READY / "PUBLISH_RECEIPT_2026_08_11.json"


def main() -> None:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = READY / "_backups_editor" / stamp
    specs_dir = out / "canvas_specs"
    specs_dir.mkdir(parents=True, exist_ok=False)

    ids = json.loads(SOURCE.read_text(encoding="utf-8"))["scene_ids"]
    canvas_ids = [sid for sid in ids if sid.endswith("_parallax")]
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    catalog_items = [item for item in catalog.get("items", []) if item.get("id") in set(ids)]

    specs = {}
    for sid in canvas_ids:
        spec = get_json(SCENES_BUCKET, f"{sid}.json")
        specs[sid] = spec
        (specs_dir / f"{sid}.json").write_text(
            json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    conn = connect()
    cur = conn.cursor()
    cur.execute(
        "SELECT id,name,type::text,category::text,published,sort_order,updated_at "
        "FROM wallpapers WHERE id=ANY(%s) ORDER BY id",
        (ids,),
    )
    rows = [
        {"id": r[0], "name": r[1], "type": r[2], "category": r[3],
         "published": r[4], "sort_order": r[5], "updated_at": r[6].isoformat() if r[6] else None}
        for r in cur.fetchall()
    ]
    cur.close()
    conn.close()

    (out / "catalog_entries.json").write_text(
        json.dumps({"version": catalog.get("version"), "items": catalog_items}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (out / "postgres_state.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    manifest = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source": "Pixel Studio current remote state",
        "published_changed": False,
        "canvas_specs_saved": len(specs),
        "catalog_entries_saved": len(catalog_items),
        "postgres_rows_saved": len(rows),
        "backup_path": str(out),
    }
    (out / "BACKUP_MANIFEST.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
