"""Upload the two user-approved cloud traveler scenes hidden for Huawei QA."""
from __future__ import annotations
import json, sys, urllib.error, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]
from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, SK, get_json, put_json, upload_scene

BASE = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar")
SCENES = [
    {
        "sid": "viajero_sendero_luna", "folder": "viajero_sendero_luna_20260821",
        "title": {"es": "Viajero del sendero lunar", "en": "Traveler on the Moonlit Path"},
        "name": "Viajero del sendero lunar", "glow": "#BFEFFF", "pf": 0.17, "bob": [0.7, 7.8],
        "desc": "Un pequeño héroe contempla un sendero de nubes que asciende hacia una luna creciente.",
        "tags": ["viajero", "link", "zelda", "fan art", "luna", "nubes", "estrellas", "aventura", "parallax"],
        "particles": [{"kind": "motes", "params": {"count": 14, "drift": 0.04, "vy_min": -0.018, "vy_max": -0.004, "color": "#BFEFFF", "max_alpha": 50}}],
    },
    {
        "sid": "viajero_portal_estelar", "folder": "viajero_portal_estelar_20260821",
        "title": {"es": "Viajero ante el portal de estrellas", "en": "Traveler Before the Star Portal"},
        "name": "Viajero ante el portal de estrellas", "glow": "#FFE78A", "pf": 0.18, "bob": [0.8, 7.2],
        "desc": "Entre islas de nubes, un viajero extiende la mano hacia una estrella bajo un portal celeste.",
        "tags": ["viajero", "link", "zelda", "fan art", "portal", "cometa", "nubes", "estrellas", "parallax"],
        "particles": [
            {"kind": "motes", "params": {"count": 8, "drift": 0.035, "vy_min": -0.016, "vy_max": -0.003, "color": "#BFEFFF", "max_alpha": 46}},
            {"kind": "motes", "params": {"count": 6, "drift": 0.025, "vy_min": -0.012, "vy_max": -0.002, "color": "#FFE78A", "max_alpha": 54}},
        ],
    },
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


def upload_one(cfg: dict) -> dict:
    sid, root = cfg["sid"], BASE / cfg["folder"]
    outputs = [root / "SCENE_SPEC_QA.json", root / "UPLOAD_QA_RECEIPT.json"]
    backups = {p: p.read_bytes() if p.exists() else None for p in outputs}
    old_catalog = get_json(IMG_BUCKET, "catalog_index.json")
    if any(i.get("id") == sid for i in old_catalog.get("items", [])):
        raise RuntimeError(f"{sid} ya existe en catálogo")
    try: get_json(SCENES_BUCKET, f"{sid}.json")
    except urllib.error.HTTPError as exc:
        if not missing(exc): raise
    else: raise RuntimeError(f"{sid} ya tiene spec")
    conn = connect(); cur = conn.cursor(); cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (sid,))
    if cur.fetchone() is not None:
        cur.close(); conn.close(); raise RuntimeError(f"{sid} ya existe en DB")
    try:
        result = upload_scene({
            "scene_id": sid, "src_dir": str(root),
            "background_file": "parallax/layers/background.png",
            "bg": {"z": 0, "parallax": 0.06, "scale": 1.26},
            "layers": [
                {"key": "traveler_aura", "file": "parallax/layers/traveler_aura.png", "z": 8, "parallax": cfg["pf"], "scale": 1.0, "bob": cfg["bob"]},
                {"key": "traveler", "file": "parallax/layers/traveler_canvas.png", "z": 12, "parallax": cfg["pf"], "scale": 1.0, "bob": cfg["bob"]},
            ],
            "static_file": "static/wallpaper_static.png", "particles": cfg["particles"], "cycles": [], "sprites": [],
            "title": cfg["title"], "tags": cfg["tags"], "category_semantic": "fantasy",
            "glow": cfg["glow"], "name": cfg["name"], "desc_plain": cfg["desc"],
            "desc_rich": (root / "METADATA_DESCRIPCION.md").read_text(encoding="utf-8"),
            "featured": False, "published": False,
        })
        spec = get_json(SCENES_BUCKET, f"{sid}.json"); spec["published"] = False; put_json(SCENES_BUCKET, f"{sid}.json", spec)
        spec = get_json(SCENES_BUCKET, f"{sid}.json"); catalog = get_json(IMG_BUCKET, "catalog_index.json")
        matches = [i for i in catalog.get("items", []) if i.get("id") == sid]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (sid,)); db = cur.fetchone()
        if spec.get("published") is not False or len(matches) != 1 or matches[0].get("published") is not False or db != (False,):
            raise RuntimeError(f"{sid} no quedó triple hidden")
        outputs[0].write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        outputs[1].write_text(json.dumps({**result, "published": False, "triple_hidden_verified": True}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return {"scene_id": sid, "catalog_version": catalog.get("version"), "triple_hidden": True}
    except Exception:
        put_json(IMG_BUCKET, "catalog_index.json", old_catalog)
        for bucket, remote in [(SCENES_BUCKET, f"{sid}.json"), (IMG_BUCKET, f"{sid}.webp"), (IMG_BUCKET, f"{sid}_preview.webp"), (IMG_BUCKET, f"{sid}_background.webp"), (IMG_BUCKET, f"{sid}_traveler_aura.webp"), (IMG_BUCKET, f"{sid}_traveler.webp")]:
            delete_object(bucket, remote)
        cur.execute("DELETE FROM wallpapers WHERE id=%s", (sid,)); conn.commit()
        for p, previous in backups.items():
            if previous is None: p.unlink(missing_ok=True)
            else: p.write_bytes(previous)
        raise
    finally:
        cur.close(); conn.close()


def main() -> None:
    initial_catalog = get_json(IMG_BUCKET, "catalog_index.json")
    output_paths = [BASE / cfg["folder"] / name for cfg in SCENES for name in ("SCENE_SPEC_QA.json", "UPLOAD_QA_RECEIPT.json")]
    output_backups = {p: p.read_bytes() if p.exists() else None for p in output_paths}
    created_sids: list[str] = []
    try:
        receipts = []
        for cfg in SCENES:
            receipts.append(upload_one(cfg))
            created_sids.append(cfg["sid"])
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM no confirmó invalidación")
        catalog = get_json(IMG_BUCKET, "catalog_index.json")
        conn = connect(); cur = conn.cursor()
        try:
            for cfg in SCENES:
                sid = cfg["sid"]
                spec = get_json(SCENES_BUCKET, f"{sid}.json")
                matches = [i for i in catalog.get("items", []) if i.get("id") == sid]
                cur.execute("SELECT published FROM wallpapers WHERE id=%s", (sid,))
                if spec.get("published") is not False or len(matches) != 1 or matches[0].get("published") is not False or cur.fetchone() != (False,):
                    raise RuntimeError(f"{sid} no quedó triple hidden en verificación conjunta")
        finally:
            cur.close(); conn.close()
        print(json.dumps(receipts, ensure_ascii=False, indent=2))
    except Exception:
        put_json(IMG_BUCKET, "catalog_index.json", initial_catalog)
        conn = connect(); cur = conn.cursor()
        try:
            for sid in created_sids:
                for bucket, remote in [
                    (SCENES_BUCKET, f"{sid}.json"), (IMG_BUCKET, f"{sid}.webp"),
                    (IMG_BUCKET, f"{sid}_preview.webp"), (IMG_BUCKET, f"{sid}_background.webp"),
                    (IMG_BUCKET, f"{sid}_traveler_aura.webp"), (IMG_BUCKET, f"{sid}_traveler.webp"),
                ]:
                    delete_object(bucket, remote)
                cur.execute("DELETE FROM wallpapers WHERE id=%s", (sid,))
            conn.commit()
        finally:
            cur.close(); conn.close()
        for p, previous in output_backups.items():
            if previous is None: p.unlink(missing_ok=True)
            else: p.write_bytes(previous)
        restored_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        if restored_catalog != initial_catalog:
            raise RuntimeError("Rollback global no restauró el catálogo inicial")
        conn = connect(); cur = conn.cursor()
        try:
            for sid in created_sids:
                cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (sid,))
                if cur.fetchone() is not None:
                    raise RuntimeError(f"Rollback global dejó fila DB para {sid}")
                try:
                    get_json(SCENES_BUCKET, f"{sid}.json")
                except urllib.error.HTTPError as exc:
                    if not missing(exc):
                        raise
                else:
                    raise RuntimeError(f"Rollback global dejó spec para {sid}")
        finally:
            cur.close(); conn.close()
        try:
            if not send_catalog_invalidate("wallpapers"):
                print("ADVERTENCIA: FCM compensatorio no confirmado", file=sys.stderr)
        except Exception as fcm_error:
            print(f"ADVERTENCIA: falló FCM compensatorio: {fcm_error}", file=sys.stderr)
        raise


if __name__ == "__main__": main()
