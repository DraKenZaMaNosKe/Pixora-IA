"""Retira las brasas globales que se superponen al gato central en produccion."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import get_json, put_json, IMG_BUCKET, SCENES_BUCKET


SID = "aquelarre_nueve_bigotes_parallax"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/aquelarre_nueve_bigotes_parallax")


def main() -> None:
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1:
        raise RuntimeError(f"Entradas de catalogo encontradas: {len(matches)}")

    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    layers = spec.get("image_layers", [])
    if len(layers) != 9 or len(spec.get("cycles", [])) != 2:
        raise RuntimeError("Inventario inesperado: se cancela el fix")
    if not spec.get("published") or not matches[0].get("published"):
        raise RuntimeError("La escena ya no esta publicada: se cancela el fix")

    removed = spec.get("particles", [])
    spec["particles"] = []
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT id,published FROM wallpapers WHERE id=%s", (SID,))
    row = cur.fetchone()
    if not row or not row[1]:
        raise RuntimeError("Postgres no confirma la escena publicada")
    fcm = send_catalog_invalidate("wallpapers")

    remote_spec = get_json(SCENES_BUCKET, f"{SID}.json")
    remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
    remote_matches = [item for item in remote_catalog.get("items", []) if item.get("id") == SID]
    if remote_spec.get("particles") != [] or len(remote_matches) != 1 or not remote_matches[0].get("published"):
        raise RuntimeError("La verificacion remota del fix fallo")

    receipt = {
        "scene_id": SID,
        "fixed_at": datetime.now(timezone.utc).isoformat(),
        "issue": "global embers overlapped the central cat and resembled colored beads",
        "removed_particles": removed,
        "particles_after": remote_spec.get("particles"),
        "catalog_version": remote_catalog.get("version"),
        "catalog_published": bool(remote_matches[0].get("published")),
        "scene_spec_published": bool(remote_spec.get("published")),
        "postgres_published": bool(row[1]),
        "image_layers": len(remote_spec.get("image_layers", [])),
        "cycles": len(remote_spec.get("cycles", [])),
        "fcm_catalog_invalidate": fcm,
    }
    (ROOT / "SCENE_SPEC_PRODUCTION.json").write_text(
        json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "FIX_PARTICLES_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    cur.close()
    conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
