"""Carga oculta de la rana psicodélica para QA en Huawei."""
from __future__ import annotations
import json, sys, urllib.error, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]
from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, SK, get_json, put_json, upload_scene

SID = "rana_psicodelica_loto"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/rana_psicodelica_loto_20260822")
OBJECTS = [
    (SCENES_BUCKET, f"{SID}.json"), (IMG_BUCKET, f"{SID}.webp"),
    (IMG_BUCKET, f"{SID}_preview.webp"), (IMG_BUCKET, f"{SID}_background.webp"),
    (IMG_BUCKET, f"{SID}_bioluminescent_aura.webp"), (IMG_BUCKET, f"{SID}_frog_lotus.webp"),
]


def missing(exc: urllib.error.HTTPError) -> bool:
    try: payload = json.loads(exc.read().decode("utf-8", "replace"))
    except json.JSONDecodeError: return False
    return exc.code in {400, 404} and str(payload.get("statusCode")) == "404" and payload.get("code") == "NoSuchKey"


def delete_object(bucket: str, remote: str) -> None:
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}", method="DELETE")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("apikey", SK)
    try:
        with urllib.request.urlopen(req, timeout=30): pass
    except urllib.error.HTTPError as exc:
        if not missing(exc): raise


def main() -> None:
    catalog_before = get_json(IMG_BUCKET, "catalog_index.json")
    if any(item.get("id") == SID for item in catalog_before.get("items", [])):
        raise RuntimeError("La escena ya existe en catálogo")
    try: get_json(SCENES_BUCKET, f"{SID}.json")
    except urllib.error.HTTPError as exc:
        if not missing(exc): raise
    else: raise RuntimeError("La escena ya tiene spec")
    conn = connect(); cur = conn.cursor(); cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() is not None:
        cur.close(); conn.close(); raise RuntimeError("La escena ya existe en Postgres")

    outputs = [ROOT / "SCENE_SPEC_QA.json", ROOT / "UPLOAD_QA_RECEIPT.json"]
    backups = {p: p.read_bytes() if p.exists() else None for p in outputs}
    try:
        result = upload_scene({
            "scene_id": SID, "src_dir": str(ROOT),
            "background_file": "parallax/layers/background.png",
            "bg": {"z": 0, "parallax": 0.055, "scale": 1.26},
            "layers": [
                {"key": "bioluminescent_aura", "file": "parallax/layers/bioluminescent_aura.png", "z": 8, "parallax": 0.15, "scale": 1.0, "bob": [0.7, 8.0]},
                {"key": "frog_lotus", "file": "parallax/layers/frog_lotus_canvas.png", "z": 12, "parallax": 0.15, "scale": 1.0, "bob": [0.7, 8.0]},
            ],
            "static_file": "static/wallpaper_static.png",
            "particles": [
                {"kind": "motes", "params": {"count": 9, "drift": 0.03, "vy_min": -0.014, "vy_max": -0.003, "color": "#42F5D7", "max_alpha": 48}},
                {"kind": "motes", "params": {"count": 6, "drift": 0.02, "vy_min": -0.010, "vy_max": -0.002, "color": "#FF7A45", "max_alpha": 42}},
            ],
            "cycles": [], "sprites": [],
            "title": {"es": "La guardiana del loto prismático", "en": "Guardian of the Prismatic Lotus"},
            "tags": ["rana", "loto", "psicodélico", "bioluminiscente", "fantasía", "naturaleza", "meditación", "original", "parallax"],
            "category_semantic": "fantasy", "glow": "#42F5D7",
            "name": "La guardiana del loto prismático",
            "desc_plain": "Una rana fantástica medita sobre un loto multicolor frente a un santuario bioluminiscente.",
            "desc_rich": (ROOT / "METADATA_DESCRIPCION.md").read_text(encoding="utf-8"),
            "featured": False, "published": False,
        })
        spec = get_json(SCENES_BUCKET, f"{SID}.json"); spec["published"] = False
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        remote = get_json(SCENES_BUCKET, f"{SID}.json"); catalog = get_json(IMG_BUCKET, "catalog_index.json")
        matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,)); db = cur.fetchone()
        if remote.get("published") is not False or len(matches) != 1 or matches[0].get("published") is not False or db != (False,):
            raise RuntimeError("La escena no quedó triple hidden")
        outputs[0].write_text(json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        receipt = {**result, "published": False, "triple_hidden_verified": True, "catalog_version": catalog.get("version")}
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM no confirmado")
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception as original_error:
        cleanup_errors = []
        try: put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        except Exception as cleanup_error: cleanup_errors.append(f"catálogo: {cleanup_error}")
        for bucket, remote in OBJECTS:
            try: delete_object(bucket, remote)
            except Exception as cleanup_error: cleanup_errors.append(f"{bucket}/{remote}: {cleanup_error}")
        try:
            cur.execute("DELETE FROM wallpapers WHERE id=%s", (SID,)); conn.commit()
        except Exception as cleanup_error:
            cleanup_errors.append(f"Postgres: {cleanup_error}")
        for p, previous in backups.items():
            try:
                if previous is None: p.unlink(missing_ok=True)
                else: p.write_bytes(previous)
            except Exception as cleanup_error: cleanup_errors.append(f"output {p.name}: {cleanup_error}")
        try:
            if get_json(IMG_BUCKET, "catalog_index.json") != catalog_before:
                cleanup_errors.append("catálogo no restaurado")
        except Exception as cleanup_error: cleanup_errors.append(f"verificación catálogo: {cleanup_error}")
        try:
            get_json(SCENES_BUCKET, f"{SID}.json")
        except urllib.error.HTTPError as exc:
            if not missing(exc): cleanup_errors.append(f"spec no verificable: {exc}")
        except Exception as cleanup_error: cleanup_errors.append(f"verificación spec: {cleanup_error}")
        else: cleanup_errors.append("spec residual")
        try:
            cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (SID,))
            if cur.fetchone() is not None: cleanup_errors.append("fila Postgres residual")
        except Exception as cleanup_error: cleanup_errors.append(f"verificación Postgres: {cleanup_error}")
        try:
            if not send_catalog_invalidate("wallpapers"):
                print("ADVERTENCIA: FCM compensatorio no confirmado", file=sys.stderr)
        except Exception as fcm_error:
            print(f"ADVERTENCIA: falló FCM compensatorio: {fcm_error}", file=sys.stderr)
        if cleanup_errors:
            raise RuntimeError("Rollback incompleto: " + " | ".join(cleanup_errors)) from original_error
        raise
    finally:
        cur.close(); conn.close()


if __name__ == "__main__": main()
