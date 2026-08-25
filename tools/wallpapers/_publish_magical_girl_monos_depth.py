"""Publica la escena 2.5D aprobada sin alterar su arte ni configuracion."""
from __future__ import annotations
import json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]
from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json
from sprite_pack_utils import fetch_sprite_manifest, load_service_key

SID = "magical_girl_monos_depth_live"
KEY = "magical_girl_doodles_alive_cycle"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/magical_girl_moños_vivos_20260823")
VERSION_BEFORE, VERSION_AFTER = 288, 289
QA = [ROOT/"qa/HUAWEI_DEPTH_QA.png", ROOT/"qa/SAMSUNG_DEPTH_QA_A.png", ROOT/"qa/SAMSUNG_DEPTH_QA_B.png"]


def main() -> None:
    spec_before = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog_before = get_json(IMG_BUCKET, "catalog_index.json")
    manifest_before = fetch_sprite_manifest(load_service_key())
    matches = [x for x in catalog_before.get("items", []) if x.get("id") == SID]
    if catalog_before.get("version") != VERSION_BEFORE or len(matches) != 1:
        raise RuntimeError("Catalogo/preflight inesperado")
    layer = spec_before.get("image_layers", [{}])[0]; sprite = spec_before.get("sprites", [{}])[0]
    params = {"fullscreen": False, "x": .5, "y": .5, "anchor_x": .5, "anchor_y": .5,
              "scale": .002333333, "alpha": 255, "high_res": True, "parallax_factor": .055, "z": 12}
    entry = manifest_before.get(KEY, {})
    if (spec_before.get("published") is not False or matches[0].get("published") is not False
            or layer.get("revision") != 1 or layer.get("scale") != 1.26 or layer.get("parallax_factor") != .055
            or layer.get("depth_strength") != .42 or not layer.get("depth_map_url", "").endswith(f"{SID}_background_depth.webp")
            or sprite.get("manifest_key") != KEY or sprite.get("frame_skip") != 6.0 or sprite.get("params") != params
            or entry.get("zip") != f"{KEY}.zip" or entry.get("frames") != 8 or entry.get("size") != 516509
            or any(not p.is_file() or p.stat().st_size < 100000 for p in QA)):
        raise RuntimeError("La escena ya no coincide con QA")
    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() != (False,): cur.close(); conn.close(); raise RuntimeError("DB no esta hidden")
    outputs = [ROOT/"SCENE_SPEC_PRODUCTION.json", ROOT/"PRODUCTION_RECEIPT.json"]
    backups = {p: p.read_bytes() if p.exists() else None for p in outputs}
    try:
        spec_after = json.loads(json.dumps(spec_before)); spec_after["published"] = True
        catalog_after = json.loads(json.dumps(catalog_before)); catalog_after["version"] = VERSION_AFTER
        changed = 0
        for item in catalog_after["items"]:
            if item.get("id") == SID: item["published"] = True; changed += 1
        if changed != 1: raise RuntimeError("No se pudo construir catalogo final")
        put_json(SCENES_BUCKET, f"{SID}.json", spec_after); put_json(IMG_BUCKET, "catalog_index.json", catalog_after)
        cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING published", (SID,))
        if cur.fetchone() != (True,): raise RuntimeError("DB no actualizada")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"): raise RuntimeError("FCM no confirmado")
        remote = get_json(SCENES_BUCKET, f"{SID}.json"); catalog = get_json(IMG_BUCKET, "catalog_index.json")
        rm = fetch_sprite_manifest(load_service_key()); final = [x for x in catalog.get("items", []) if x.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,)); db = cur.fetchone()
        if remote != spec_after or catalog != catalog_after or len(final) != 1 or final[0].get("published") is not True or db != (True,) or rm != manifest_before:
            raise RuntimeError("Verificacion final fallo")
        outputs[0].write_text(json.dumps(remote, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        receipt = {"scene_id": SID, "catalog_version": VERSION_AFTER, "triple_published": True,
                   "revision": 1, "depth_strength": .42, "qa": [p.name for p in QA], "fcm_catalog_invalidate": True}
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception as original:
        errors=[]
        try: conn.rollback()
        except Exception as exc: errors.append(f"db rollback: {exc}")
        for label, fn in [("spec",lambda:put_json(SCENES_BUCKET,f"{SID}.json",spec_before)),("catalog",lambda:put_json(IMG_BUCKET,"catalog_index.json",catalog_before))]:
            try: fn()
            except Exception as exc: errors.append(f"{label}: {exc}")
        try: cur.execute("UPDATE wallpapers SET published=false WHERE id=%s",(SID,)); conn.commit()
        except Exception as exc: errors.append(f"DB restore: {exc}")
        for p,old in backups.items():
            try: p.unlink(missing_ok=True) if old is None else p.write_bytes(old)
            except Exception as exc: errors.append(f"output {p.name}: {exc}")
        try:
            if get_json(SCENES_BUCKET,f"{SID}.json") != spec_before: errors.append("spec no restaurado")
        except Exception as exc: errors.append(f"verify spec: {exc}")
        try:
            if get_json(IMG_BUCKET,"catalog_index.json") != catalog_before: errors.append("catalogo no restaurado")
        except Exception as exc: errors.append(f"verify catalogo: {exc}")
        try:
            cur.execute("SELECT published FROM wallpapers WHERE id=%s",(SID,))
            if cur.fetchone() != (False,): errors.append("DB no restaurada")
        except Exception as exc: errors.append(f"verify DB: {exc}")
        for p,old in backups.items():
            try:
                if (p.read_bytes() if p.exists() else None) != old: errors.append(f"output no restaurado {p.name}")
            except Exception as exc: errors.append(f"verify output {p.name}: {exc}")
        try:
            if not send_catalog_invalidate("wallpapers"): errors.append("FCM compensatorio no confirmado")
        except Exception as exc: errors.append(f"FCM compensatorio: {exc}")
        if errors: raise RuntimeError("Rollback incompleto: "+" | ".join(errors)) from original
        raise
    finally: cur.close(); conn.close()

if __name__ == "__main__": main()
