"""Publica la rana psicodélica aprobada en Huawei."""
from __future__ import annotations
import json, sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]
from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json

SID = "rana_psicodelica_loto"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/rana_psicodelica_loto_20260822")
EXPECTED_VERSION = 272
FINAL_VERSION = 273


def main() -> None:
    approved = json.loads((ROOT / "SCENE_SPEC_QA.json").read_text(encoding="utf-8"))
    remote = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    if remote != approved or remote.get("published") is not False:
        raise RuntimeError("El spec remoto no coincide con el QA oculto")
    if int(catalog.get("version", 0) or 0) != EXPECTED_VERSION:
        raise RuntimeError("La versión inicial del catálogo cambió")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1 or matches[0].get("published") is not False:
        raise RuntimeError("Catálogo oculto inesperado o duplicado")
    qa = ROOT / "qa/HUAWEI_QA.png"
    if not qa.is_file() or qa.stat().st_size < 100_000:
        raise RuntimeError("Falta captura QA Huawei")

    conn = connect(); cur = conn.cursor(); cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() != (False,):
        cur.close(); conn.close(); raise RuntimeError("Postgres no parte oculto")
    outputs = [ROOT / "SCENE_SPEC_PRODUCTION.json", ROOT / "PRODUCTION_RECEIPT.json"]
    output_before = {p: p.read_bytes() if p.exists() else None for p in outputs}
    catalog_before = json.loads(json.dumps(catalog)); spec_before = json.loads(json.dumps(remote))
    try:
        remote["published"] = True; matches[0]["published"] = True
        put_json(SCENES_BUCKET, f"{SID}.json", remote)
        catalog["version"] = FINAL_VERSION; put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING published", (SID,))
        if cur.fetchone() != (True,): raise RuntimeError("No se publicó en Postgres")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"): raise RuntimeError("FCM principal no confirmado")
        final_spec = get_json(SCENES_BUCKET, f"{SID}.json"); expected = json.loads(json.dumps(spec_before)); expected["published"] = True
        final_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        found = [item for item in final_catalog.get("items", []) if item.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        if final_spec != expected or int(final_catalog.get("version", 0) or 0) != FINAL_VERSION or len(found) != 1 or found[0].get("published") is not True or cur.fetchone() != (True,):
            raise RuntimeError("Falló la verificación final")
        receipt = {"scene_id": SID, "published_at": datetime.now(timezone.utc).isoformat(), "catalog_version": FINAL_VERSION,
                   "scene_spec_published": True, "catalog_published": True, "postgres_published": True,
                   "revision": 1, "qa_scope": "Huawei only, per user instruction", "qa_capture": "qa/HUAWEI_QA.png",
                   "fcm_catalog_invalidate": True}
        outputs[0].write_text(json.dumps(final_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except Exception as original_error:
        cleanup_errors = []
        try: conn.rollback()
        except Exception as cleanup_error: cleanup_errors.append(f"rollback DB: {cleanup_error}")
        try: put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        except Exception as cleanup_error: cleanup_errors.append(f"spec: {cleanup_error}")
        try: put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        except Exception as cleanup_error: cleanup_errors.append(f"catálogo: {cleanup_error}")
        try:
            cur.execute("UPDATE wallpapers SET published=false WHERE id=%s", (SID,)); conn.commit()
        except Exception as cleanup_error: cleanup_errors.append(f"Postgres: {cleanup_error}")
        for p, previous in output_before.items():
            try:
                if previous is None: p.unlink(missing_ok=True)
                else: p.write_bytes(previous)
            except Exception as cleanup_error: cleanup_errors.append(f"output {p.name}: {cleanup_error}")
        try:
            if get_json(SCENES_BUCKET, f"{SID}.json") != spec_before: cleanup_errors.append("spec no restaurado")
        except Exception as cleanup_error: cleanup_errors.append(f"verificación spec: {cleanup_error}")
        try:
            if get_json(IMG_BUCKET, "catalog_index.json") != catalog_before: cleanup_errors.append("catálogo no restaurado")
        except Exception as cleanup_error: cleanup_errors.append(f"verificación catálogo: {cleanup_error}")
        try:
            cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
            if cur.fetchone() != (False,): cleanup_errors.append("Postgres no restaurado")
        except Exception as cleanup_error: cleanup_errors.append(f"verificación Postgres: {cleanup_error}")
        try:
            if not send_catalog_invalidate("wallpapers"): print("ADVERTENCIA: FCM compensatorio no confirmado", file=sys.stderr)
        except Exception as fcm_error: print(f"ADVERTENCIA: falló FCM compensatorio: {fcm_error}", file=sys.stderr)
        if cleanup_errors: raise RuntimeError("Rollback incompleto: " + " | ".join(cleanup_errors)) from original_error
        raise
    finally:
        cur.close(); conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__": main()
