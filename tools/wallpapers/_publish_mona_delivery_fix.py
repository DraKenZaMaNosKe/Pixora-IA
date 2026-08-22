"""Publish Mona after Huawei validation of the stable sprite delivery hotfix."""
from __future__ import annotations
import json, sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]
from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json

SID = "mona_lisa_gatito_museo"
KEY = "mona_lisa_gatito_museo_pair"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/mona_lisa_gatito_museo_20260818")
BEFORE, AFTER = 267, 268


def main() -> None:
    approved = json.loads((ROOT / "SCENE_SPEC_DELIVERY_FIX_QA.json").read_text(encoding="utf-8"))
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    if spec != approved or spec.get("published") is not False:
        raise RuntimeError("Spec remoto no coincide con QA aprobado")
    cat = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [i for i in cat.get("items", []) if i.get("id") == SID]
    if int(cat.get("version", 0)) != BEFORE or len(matches) != 1 or matches[0].get("published") is not False:
        raise RuntimeError("Catálogo no parte oculto en v267")
    manifest = get_json("wallpaper-sprites", "manifest.json")
    pack = manifest.get(KEY) or {}
    if int(pack.get("frames", 0)) != 5 or int(pack.get("size", 0)) != 6702749:
        raise RuntimeError("Paquete estable inesperado")
    qas = [ROOT / "qa/HUAWEI_DELIVERY_FIX_QA.png"] + [ROOT / f"qa/HUAWEI_DELIVERY_BLINK_{i}.png" for i in range(1, 6)]
    if any(not p.is_file() or p.stat().st_size < 100_000 for p in qas):
        raise RuntimeError("Falta evidencia Huawei")

    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() != (False,):
        cur.close(); conn.close(); raise RuntimeError("DB no parte oculta")
    spec_before = json.loads(json.dumps(spec)); cat_before = json.loads(json.dumps(cat))
    outputs = [ROOT / "SCENE_SPEC_PRODUCTION_DELIVERY_FIX.json", ROOT / "PRODUCTION_RECEIPT_DELIVERY_FIX.json"]
    backups = {p: p.read_bytes() if p.exists() else None for p in outputs}
    try:
        spec["published"] = True; matches[0]["published"] = True; cat["version"] = AFTER
        put_json(SCENES_BUCKET, f"{SID}.json", spec); put_json(IMG_BUCKET, "catalog_index.json", cat)
        cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING published", (SID,))
        if cur.fetchone() != (True,): raise RuntimeError("DB no publicó")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"): raise RuntimeError("FCM falló")
        rs = get_json(SCENES_BUCKET, f"{SID}.json")
        expected = json.loads(json.dumps(approved)); expected["published"] = True
        rc = get_json(IMG_BUCKET, "catalog_index.json")
        rm = [i for i in rc.get("items", []) if i.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,)); rd = cur.fetchone()
        if rs != expected or int(rc.get("version", 0)) != AFTER or len(rm) != 1 or rm[0].get("published") is not True or rd != (True,):
            raise RuntimeError("Verificación final falló")
        receipt = {"scene_id": SID, "published_at": datetime.now(timezone.utc).isoformat(),
                   "catalog_version": AFTER, "triple_published": True, "manifest_key": KEY,
                   "frames": 5, "delivery_fix": "stable_manifest_key_restored",
                   "qa_device": "HUAWEI VNS-L53", "qa_captures": [str(p.relative_to(ROOT)).replace('\\', '/') for p in qas],
                   "fcm_catalog_invalidate": True}
        outputs[0].write_text(json.dumps(rs, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception as original:
        conn.rollback(); put_json(SCENES_BUCKET, f"{SID}.json", spec_before); put_json(IMG_BUCKET, "catalog_index.json", cat_before)
        cur.execute("UPDATE wallpapers SET published=false WHERE id=%s", (SID,)); conn.commit()
        for p, data in backups.items():
            if data is None: p.unlink(missing_ok=True)
            else: p.write_bytes(data)
        try:
            if not send_catalog_invalidate("wallpapers"): print("ADVERTENCIA: FCM compensatorio false", file=sys.stderr)
        except Exception as exc: print(f"ADVERTENCIA: FCM compensatorio: {exc}", file=sys.stderr)
        raise original
    finally:
        cur.close(); conn.close()


if __name__ == "__main__": main()
