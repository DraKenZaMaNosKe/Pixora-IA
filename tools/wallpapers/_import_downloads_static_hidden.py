"""Recupera el lote aprobado de Downloads como wallpapers STATIC ocultos."""
from __future__ import annotations

import io
import json
import re
import shutil
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
DOWNLOADS = Path(r"C:/Users/lalo/Downloads")
PIPELINE = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar")
FILES = [
    "grok-002a9745-8fcf-4e90-90fb-3b763651f21e.jpg",
    "grok-3e583cdf-b556-4e40-b4f8-69a764f00962.jpg",
    "grok-8344b371-2a07-4a4e-a40d-274703795d30.jpg",
    "grok-9482d569-4b3c-477b-b754-65c3cf8af7fd.jpg",
    "grok-a68b5985-d13a-46d8-9fa2-2657833463fc.jpg",
    "grok-b3c15b60-3b7c-422c-bd5f-8f704c9e7e1c.jpg",
    "grok-f5f6f2ff-9bbd-4b80-b80f-2dbb9dd3831b.jpg",
    "grok-fc0b30ce-f0b8-4eee-beeb-6a676f81180a.jpg",
]

SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]


def put(remote: str, body: bytes) -> None:
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("apikey", SK); req.add_header("Content-Type", "image/webp")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=180) as response:
        if response.status not in (200, 201):
            raise RuntimeError(f"upload failed: {remote} -> {response.status}")


def webp(im: Image.Image, quality: int) -> bytes:
    out = io.BytesIO(); im.save(out, "WEBP", quality=quality, method=6)
    return out.getvalue()


def main() -> None:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    batch = PIPELINE / f"downloads_static_{stamp}"
    originals = batch / "originales"; production = batch / "production"
    originals.mkdir(parents=True); production.mkdir(parents=True)
    conn = connect(); cur = conn.cursor(); imported = []
    try:
        for index, filename in enumerate(FILES, 1):
            src = DOWNLOADS / filename
            if not src.is_file():
                raise FileNotFoundError(src)
            sid = f"downloads_curated_{stamp}_{index:02d}"
            name = f"Colección nueva {index:02d}"
            shutil.copy2(src, originals / filename)
            im = Image.open(src).convert("RGB")
            full = webp(im, 90)
            prev = im.copy(); prev.thumbnail((540, 1170), Image.Resampling.LANCZOS)
            preview = webp(prev, 84)
            put(f"{sid}.webp", full); put(f"{sid}_preview.webp", preview)
            (production / f"{sid}.webp").write_bytes(full)
            (production / f"{sid}_preview.webp").write_bytes(preview)
            cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers")
            sort_order = cur.fetchone()[0]
            cur.execute("""
                INSERT INTO wallpapers (
                  id,name,description,type,category,tags,image_path,preview_path,
                  image_size,preview_size,glow_color,badge,sort_order,featured,
                  trending_score,published,daily_eligible,author_name,media_width,media_height
                ) VALUES (%s,%s,%s,'static'::wallpaper_type,'WALLPAPERS'::wallpaper_category,%s,
                  %s,%s,%s,%s,%s,'NEW'::wallpaper_badge,%s,false,0,false,false,
                  'Pixora Studio',%s,%s)
                ON CONFLICT (id) DO UPDATE SET image_path=EXCLUDED.image_path,
                  preview_path=EXCLUDED.preview_path,image_size=EXCLUDED.image_size,
                  preview_size=EXCLUDED.preview_size,published=false,daily_eligible=false,
                  updated_at=now()
            """, (sid, name, "Imagen nueva en revisión dentro de Pixel Studio.",
                  ["preseleccion", "downloads", "por_editar"], f"{sid}.webp",
                  f"{sid}_preview.webp", len(full), len(preview), "#E879F9",
                  sort_order, im.width, im.height))
            imported.append({"id": sid, "source": filename, "type": "static",
                             "published": False, "width": im.width, "height": im.height})
        conn.commit()
    except Exception:
        conn.rollback(); raise
    finally:
        cur.close(); conn.close()
    manifest = {"operation": "downloads_approved_to_hidden_static_editor",
                "created_at": datetime.now(timezone.utc).isoformat(),
                "published": False, "items": imported}
    (batch / "IMPORT_MANIFEST.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"batch": str(batch), "count": len(imported),
                      "ids": [x["id"] for x in imported]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
