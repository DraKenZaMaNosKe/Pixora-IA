"""Publish approved Andromeda V2 static and depth variants with rollback."""
from __future__ import annotations

import json
import sys
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json

SID = "andromeda_cadena_nebular_depth"
STATIC_ID = "andromeda_cadena_nebular_static"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/andromeda_cadena_nebular_20260824")
QA_FILES = [ROOT / "qa/HUAWEI_V2_HORNS_STARS_QA.png", ROOT / "qa/SAMSUNG_V2_HORNS_STARS_QA.png"]


def validate_spec(spec: dict, published: bool) -> None:
    if spec.get("id") != SID or spec.get("published") is not published:
        raise RuntimeError("Unexpected spec publication state")
    layers = spec.get("image_layers", [])
    if len(layers) != 5 or len(spec.get("cycles", [])) != 1:
        raise RuntimeError("Unexpected approved layer inventory")
    bg = next((x for x in layers if x.get("key") == "background"), None)
    if not bg or int(bg.get("revision", 0)) != 6:
        raise RuntimeError("Approved revision changed")
    if abs(float(bg.get("depth_strength", 0)) - 0.28) > 0.001:
        raise RuntimeError("Approved depth strength changed")
    if abs(float(bg.get("parallax_factor", 0)) - 0.04) > 0.001:
        raise RuntimeError("Approved parallax changed")


def main() -> None:
    approved = json.loads((ROOT / "SCENE_SPEC_QA.json").read_text(encoding="utf-8"))
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    validate_spec(spec, False)
    if spec != approved:
        raise RuntimeError("Remote spec differs from approved QA spec")
    if any(not p.is_file() or p.stat().st_size < 100_000 for p in QA_FILES):
        raise RuntimeError("Missing Huawei or Samsung QA evidence")

    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [x for x in catalog.get("items", []) if x.get("id") == SID]
    if len(matches) != 1 or matches[0].get("published") is not False:
        raise RuntimeError("Canvas catalog entry is not hidden")
    spec_before, catalog_before = deepcopy(spec), deepcopy(catalog)
    next_version = int(catalog.get("version", 0)) + 1
    outputs = [ROOT / "SCENE_SPEC_PRODUCTION.json", ROOT / "PRODUCTION_RECEIPT.json"]
    output_before = {p: p.read_bytes() if p.exists() else None for p in outputs}

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT id,published FROM wallpapers WHERE id IN (%s,%s) ORDER BY id", (SID, STATIC_ID))
    if cur.fetchall() != [(SID, False), (STATIC_ID, False)]:
        cur.close(); conn.close()
        raise RuntimeError("Postgres variants are not both hidden")
    try:
        spec["published"] = True
        matches[0]["published"] = True
        catalog["version"] = next_version
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute("UPDATE wallpapers SET published=true WHERE id IN (%s,%s) RETURNING id,published", (SID, STATIC_ID))
        rows = sorted(cur.fetchall())
        if rows != [(SID, True), (STATIC_ID, True)]:
            raise RuntimeError("Postgres did not publish both variants")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM invalidation was not confirmed")

        remote = get_json(SCENES_BUCKET, f"{SID}.json")
        remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        remote_matches = [x for x in remote_catalog.get("items", []) if x.get("id") == SID]
        cur.execute("SELECT id,published FROM wallpapers WHERE id IN (%s,%s) ORDER BY id", (SID, STATIC_ID))
        db_rows = cur.fetchall()
        validate_spec(remote, True)
        expected = deepcopy(approved); expected["published"] = True
        if remote != expected or len(remote_matches) != 1 or remote_matches[0].get("published") is not True:
            raise RuntimeError("Remote publication verification failed")
        if db_rows != [(SID, True), (STATIC_ID, True)]:
            raise RuntimeError("Postgres publication verification failed")

        receipt = {
            "scene_id": SID,
            "static_id": STATIC_ID,
            "published_at": datetime.now(timezone.utc).isoformat(),
            "catalog_version": next_version,
            "triple_published": True,
            "static_published": True,
            "revision": 6,
            "depth_strength": 0.28,
            "star_frames": 4,
            "qa_devices": ["HUAWEI VNS-L53", "Samsung SM-A155M"],
            "qa_captures": ["qa/HUAWEI_V2_HORNS_STARS_QA.png", "qa/SAMSUNG_V2_HORNS_STARS_QA.png"],
            "fcm_catalog_invalidate": True,
        }
        outputs[0].write_text(json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception as original:
        errors = []
        try: conn.rollback()
        except Exception as exc: errors.append(f"db rollback: {exc}")
        try: put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        except Exception as exc: errors.append(f"spec rollback: {exc}")
        try: put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        except Exception as exc: errors.append(f"catalog rollback: {exc}")
        try:
            cur.execute("UPDATE wallpapers SET published=false WHERE id IN (%s,%s)", (SID, STATIC_ID)); conn.commit()
        except Exception as exc: errors.append(f"db restore: {exc}")
        for path, previous in output_before.items():
            try: path.unlink(missing_ok=True) if previous is None else path.write_bytes(previous)
            except Exception as exc: errors.append(f"output restore {path.name}: {exc}")
        try: send_catalog_invalidate("wallpapers")
        except Exception as exc: errors.append(f"FCM compensatory: {exc}")
        if errors:
            raise RuntimeError("Incomplete rollback: " + " | ".join(errors)) from original
        raise
    finally:
        cur.close(); conn.close()


if __name__ == "__main__":
    main()
