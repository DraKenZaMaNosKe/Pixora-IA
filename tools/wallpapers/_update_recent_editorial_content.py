"""Sincroniza fichas editoriales extensas de escenas recientes con Postgres."""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate


BASE = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar")
CONTENT = {
    "dumbo_primer_vuelo": BASE / "dumbo_primer_vuelo" / "metadata" / "APP_DESCRIPTION_RICH.txt",
    "plancton_hamburguesa_escape": BASE / "plancton_hamburguesa_escape" / "metadata" / "APP_DESCRIPTION_RICH.txt",
}
MARKUP = re.compile(r"\[\[(\w+):(.*?)\]\]", re.DOTALL)
ALLOWED_ROLES = {"name", "place", "power", "emotion", "key"}


def validate(scene_id: str, text: str) -> dict:
    if len(text) < 1800:
        raise ValueError(f"{scene_id}: ficha demasiado corta ({len(text)})")
    roles = [m.group(1) for m in MARKUP.finditer(text)]
    unknown = sorted(set(roles) - ALLOWED_ROLES)
    if unknown:
        raise ValueError(f"{scene_id}: roles desconocidos {unknown}")
    plain = MARKUP.sub(lambda m: m.group(2), text)
    if "[[" in plain or "]]" in plain:
        raise ValueError(f"{scene_id}: markup malformado")
    return {"rich_length": len(text), "plain_length": len(plain), "roles": sorted(set(roles))}


def main() -> None:
    payload: dict[str, tuple[str, dict]] = {}
    for sid, path in CONTENT.items():
        text = path.read_text(encoding="utf-8").strip()
        payload[sid] = (text, validate(sid, text))

    conn = connect()
    cur = conn.cursor()
    before = {}
    for sid in payload:
        cur.execute(
            "SELECT published,length(coalesce(description_rich,'')) FROM wallpapers WHERE id=%s FOR UPDATE",
            (sid,),
        )
        row = cur.fetchone()
        if not row:
            conn.rollback()
            raise RuntimeError(f"No existe {sid}")
        if row[0] is not True:
            conn.rollback()
            raise RuntimeError(f"{sid} no está publicado")
        before[sid] = int(row[1])

    updated = []
    for sid, (text, info) in payload.items():
        cur.execute(
            "UPDATE wallpapers SET description_rich=%s WHERE id=%s RETURNING id,published,length(description_rich)",
            (text, sid),
        )
        row = cur.fetchone()
        updated.append({
            "scene_id": row[0], "published": bool(row[1]),
            "before_length": before[sid], "after_length": int(row[2]), **info,
        })
    conn.commit()

    # Lectura posterior: la escritura no se considera completa sin verificarla.
    for item in updated:
        cur.execute("SELECT description_rich FROM wallpapers WHERE id=%s", (item["scene_id"],))
        remote = cur.fetchone()[0]
        expected = payload[item["scene_id"]][0]
        if remote != expected:
            raise RuntimeError(f"Verificación fallida para {item['scene_id']}")

    fcm = send_catalog_invalidate("wallpapers")
    receipt = {
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "updated": updated,
        "fcm_catalog_invalidate": fcm,
        "scope": "description_rich only; media, ordering and publication unchanged",
    }
    out = BASE / "EDITORIAL_CONTENT_UPDATE_2026-08-05.json"
    out.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    cur.close()
    conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
