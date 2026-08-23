"""Publica el dúo cloud traveler aprobado en Huawei, con rollback conjunto."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json

EXPECTED_CATALOG_VERSION = 270
PRODUCTION_CATALOG_VERSION = 271
BASE = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar")
SCENES = {
    "viajero_sendero_luna": BASE / "viajero_sendero_luna_20260821",
    "viajero_portal_estelar": BASE / "viajero_portal_estelar_20260821",
}


def main() -> None:
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    if int(catalog.get("version", 0) or 0) != EXPECTED_CATALOG_VERSION:
        raise RuntimeError("La versión inicial del catálogo cambió")

    specs = {}
    entries = {}
    for sid, root in SCENES.items():
        approved = json.loads((root / "SCENE_SPEC_QA.json").read_text(encoding="utf-8"))
        remote = get_json(SCENES_BUCKET, f"{sid}.json")
        if remote != approved or remote.get("published") is not False:
            raise RuntimeError(f"{sid}: el spec remoto ya no coincide con el QA oculto")
        found = [item for item in catalog.get("items", []) if item.get("id") == sid]
        if len(found) != 1 or found[0].get("published") is not False:
            raise RuntimeError(f"{sid}: catálogo oculto inesperado o duplicado")
        qa = root / "qa/HUAWEI_QA.png"
        if not qa.is_file() or qa.stat().st_size < 100_000:
            raise RuntimeError(f"{sid}: falta evidencia Huawei")
        specs[sid] = remote
        entries[sid] = found[0]

    conn = connect(); cur = conn.cursor()
    db_before = {}
    for sid in SCENES:
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (sid,))
        row = cur.fetchone()
        if row != (False,):
            cur.close(); conn.close()
            raise RuntimeError(f"{sid}: Postgres no parte oculto")
        db_before[sid] = False

    outputs = [root / name for root in SCENES.values() for name in ("SCENE_SPEC_PRODUCTION.json", "PRODUCTION_RECEIPT.json")]
    output_before = {p: p.read_bytes() if p.exists() else None for p in outputs}
    specs_before = json.loads(json.dumps(specs))
    catalog_before = json.loads(json.dumps(catalog))
    try:
        for sid, spec in specs.items():
            spec["published"] = True
            entries[sid]["published"] = True
            put_json(SCENES_BUCKET, f"{sid}.json", spec)
        catalog["version"] = PRODUCTION_CATALOG_VERSION
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        for sid in SCENES:
            cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING published", (sid,))
            if cur.fetchone() != (True,):
                raise RuntimeError(f"{sid}: no se publicó en Postgres")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM principal no confirmado")

        final_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        if int(final_catalog.get("version", 0) or 0) != PRODUCTION_CATALOG_VERSION:
            raise RuntimeError("Versión final de catálogo inesperada")
        receipts = {}
        for sid, root in SCENES.items():
            remote = get_json(SCENES_BUCKET, f"{sid}.json")
            expected = json.loads(json.dumps(specs_before[sid])); expected["published"] = True
            found = [item for item in final_catalog.get("items", []) if item.get("id") == sid]
            cur.execute("SELECT published FROM wallpapers WHERE id=%s", (sid,))
            if remote != expected or len(found) != 1 or found[0].get("published") is not True or cur.fetchone() != (True,):
                raise RuntimeError(f"{sid}: falló verificación triple o cambió el spec")
            receipt = {
                "scene_id": sid, "published_at": datetime.now(timezone.utc).isoformat(),
                "catalog_version": PRODUCTION_CATALOG_VERSION, "scene_spec_published": True,
                "catalog_published": True, "postgres_published": True, "revision": 1,
                "qa_scope": "Huawei only, per user instruction", "qa_device": "HUAWEI VNS-L53",
                "qa_capture": "qa/HUAWEI_QA.png", "fcm_catalog_invalidate": True,
            }
            (root / "SCENE_SPEC_PRODUCTION.json").write_text(json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            (root / "PRODUCTION_RECEIPT.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            receipts[sid] = receipt
    except Exception:
        conn.rollback()
        for sid, previous in specs_before.items():
            put_json(SCENES_BUCKET, f"{sid}.json", previous)
        put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        for sid, previous in db_before.items():
            cur.execute("UPDATE wallpapers SET published=%s WHERE id=%s", (previous, sid))
        conn.commit()
        for path, previous in output_before.items():
            if previous is None: path.unlink(missing_ok=True)
            else: path.write_bytes(previous)
        try:
            if not send_catalog_invalidate("wallpapers"):
                print("ADVERTENCIA: FCM compensatorio no confirmado", file=sys.stderr)
        except Exception as fcm_error:
            print(f"ADVERTENCIA: falló FCM compensatorio: {fcm_error}", file=sys.stderr)
        raise
    finally:
        cur.close(); conn.close()
    print(json.dumps(receipts, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
