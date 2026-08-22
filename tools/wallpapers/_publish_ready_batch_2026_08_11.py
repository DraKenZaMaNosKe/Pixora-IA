"""Publish the user-approved contents of wallpapers/2_listo_para_subir.

The script never scans `_descartadas_silla` and does not perform visual QA.
It routes metadata type static/panoramic/canvas_scene to its canonical target.
"""
from __future__ import annotations

import io
import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, get_json, put, put_json

READY = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/2_listo_para_subir")
BATCHES = ["estaticos_grok_2026_08_11", "sensual_collection_111"]
TARGET = (1080, 2340)
RECEIPT = READY / "PUBLISH_RECEIPT_2026_08_11.json"
PROGRESS = HERE / "dashboard" / "batch_publish_progress.json"


def write_progress(**changes) -> None:
    try:
        state = json.loads(PROGRESS.read_text(encoding="utf-8")) if PROGRESS.exists() else {}
    except Exception:
        state = {}
    state.update(changes)
    state["updated_at"] = datetime.now(timezone.utc).isoformat()
    temp = PROGRESS.with_suffix(".tmp")
    temp.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temp.replace(PROGRESS)


def webp(img: Image.Image, quality: int = 88) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "WEBP", quality=quality, method=6)
    return buf.getvalue()


def cover(img: Image.Image, alpha: bool = False) -> Image.Image:
    src = img.convert("RGBA")
    sw, sh = src.size
    scale = max(TARGET[0] / sw, TARGET[1] / sh)
    nw, nh = round(sw * scale), round(sh * scale)
    src = src.resize((nw, nh), Image.Resampling.LANCZOS)
    left, top = (nw - TARGET[0]) // 2, (nh - TARGET[1]) // 2
    src = src.crop((left, top, left + TARGET[0], top + TARGET[1]))
    if alpha:
        return src
    out = Image.new("RGB", TARGET, "black")
    out.paste(src, mask=src.getchannel("A"))
    return out


def preview(img: Image.Image) -> bytes:
    p = img.copy().convert("RGB")
    p.thumbnail((540, 1170), Image.Resampling.LANCZOS)
    return webp(p, 84)


def one_file(folder: Path, subdir: str) -> Path:
    files = [p for p in (folder / subdir).iterdir() if p.is_file()]
    if len(files) != 1:
        raise RuntimeError(f"{folder.name}: expected one file in {subdir}, found {len(files)}")
    return files[0]


def public_url(bucket: str, name: str) -> str:
    return f"{PROJECT}/storage/v1/object/public/{bucket}/{name}"


def upload_flat(folder: Path, meta: dict) -> dict:
    sid = meta["id"]
    source = one_file(folder, "production")
    with Image.open(source) as opened:
        original = opened.convert("RGB")
        width, height = original.size
        # Static assets keep their approved framing. Panoramas keep full width.
        body = webp(original, 88)
        prev_body = preview(original)
    put(IMG_BUCKET, f"{sid}.webp", body)
    put(IMG_BUCKET, f"{sid}_preview.webp", prev_body)
    return {
        "image_size": len(body), "preview_size": len(prev_body),
        "width": width, "height": height,
    }


def upload_canvas(folder: Path, meta: dict, catalog: dict) -> tuple[dict, dict]:
    sid = meta["id"]
    draft = json.loads((folder / "SCENE_SPEC_DRAFT.json").read_text(encoding="utf-8"))
    flat_info = upload_flat(folder, meta)
    remote_layers = []
    for layer in draft.get("image_layers", []):
        local = folder / layer["file"]
        if not local.is_file():
            raise RuntimeError(f"{sid}: missing layer {layer['file']}")
        with Image.open(local) as opened:
            baked = cover(opened, alpha=(layer.get("key") != "background"))
        remote = f"{sid}_{layer['key']}.webp"
        body = webp(baked, 92)
        put(IMG_BUCKET, remote, body)
        item = dict(layer)
        item.pop("file", None)
        item["url"] = public_url(IMG_BUCKET, remote)
        item.setdefault("offset_x_px", 0)
        item.setdefault("offset_y_px", 0)
        remote_layers.append(item)

    spec = dict(draft)
    spec["published"] = True
    spec["image_layers"] = remote_layers
    spec["background"] = {
        "url": public_url(IMG_BUCKET, f"{sid}.webp"),
        "preview_url": public_url(IMG_BUCKET, f"{sid}_preview.webp"),
        "scroll": False,
    }
    spec.setdefault("tags", ["original", "anime", "noches_de_seda", "parallax"])
    spec.setdefault("featured", False)
    spec.setdefault("sprites", [])
    spec.setdefault("events", [])
    put_json(SCENES_BUCKET, f"{sid}.json", spec)

    old_created = next((x.get("created_at") for x in catalog.get("items", [])
                        if x.get("id") == sid and x.get("created_at")), None)
    entry = {
        "id": sid, "type": "canvas_scene", "schema": 1,
        "title": spec.get("title", {"es": meta.get("title", meta.get("name", sid))}),
        "preview_url": public_url(IMG_BUCKET, f"{sid}_preview.webp"),
        "image_url": public_url(IMG_BUCKET, f"{sid}.webp"),
        "tags": spec["tags"], "category": spec.get("category", "original"),
        "featured": False, "glow_color": "#F472B6", "published": True,
        "description": meta.get("description_rich", ""),
        "spec_url": public_url(SCENES_BUCKET, f"{sid}.json"),
        "created_at": old_created or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    return flat_info, entry


def folders() -> list[Path]:
    result = []
    for batch in BATCHES:
        base = READY / batch / "scenes"
        result.extend(sorted((p for p in base.iterdir() if p.is_dir()), key=lambda p: p.name))
    return result


def main() -> None:
    scene_folders = folders()
    if len(scene_folders) != 97:
        raise RuntimeError(f"Expected exactly 97 approved scenes, found {len(scene_folders)}")
    metas = [(d, json.loads((d / "METADATA.json").read_text(encoding="utf-8"))) for d in scene_folders]
    counts = {}
    for _, m in metas:
        counts[m["type"]] = counts.get(m["type"], 0) + 1
    if counts != {"static": 51, "panoramic": 23, "canvas_scene": 23}:
        raise RuntimeError(f"Unexpected type distribution: {counts}")

    write_progress(
        status="running", total=97, completed=0, percent=0,
        current="Preparando catálogo", current_type="setup",
        counts=counts, completed_by_type={"static": 0, "panoramic": 0, "canvas_scene": 0},
        published_ids=[], error=None,
    )

    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    catalog_entries = {x.get("id"): x for x in catalog.get("items", [])}
    conn = connect()
    cur = conn.cursor()
    published = []
    try:
        for index, (folder, meta) in enumerate(metas, 1):
            sid, kind = meta["id"], meta["type"]
            write_progress(
                status="running", current=sid, current_type=kind,
                step=index, percent=round(((index - 1) / 97) * 100, 1),
            )
            print(f"[{index:02d}/97] {kind:12} {sid}", flush=True)
            if kind == "canvas_scene":
                info, entry = upload_canvas(folder, meta, catalog)
                catalog_entries[sid] = entry
                db_type, category = "static", "SCENES"
            else:
                info = upload_flat(folder, meta)
                db_type = kind
                category = "PANORAMIC" if kind == "panoramic" else (
                    "WALLPAPERS" if meta.get("collection", "").startswith("Estaticos Grok") else "ANIME"
                )
            cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers")
            sort_order = cur.fetchone()[0]
            rich_description = meta.get("description_rich") or (
                f"{meta.get('title', meta.get('name', sid))}, parte de la colección "
                f"{meta.get('collection', 'Pixora IA')}."
            )
            # public.wallpapers keeps the card summary deliberately short;
            # the complete editorial copy belongs in description_rich.
            description = (
                f"{meta.get('name', meta.get('title', sid))} · "
                f"{meta.get('title', meta.get('collection', 'Pixora IA'))}. "
                f"Colección {meta.get('collection', 'Pixora IA')}."
            )[:240]
            tags = [kind, "pixora", "original"]
            cur.execute(
                """
                INSERT INTO wallpapers (
                    id,name,description,description_rich,type,category,tags,
                    image_path,preview_path,image_size,preview_size,glow_color,badge,
                    sort_order,featured,trending_score,published,daily_eligible,
                    author_name,media_width,media_height
                ) VALUES (
                    %s,%s,%s,%s,%s::wallpaper_type,%s::wallpaper_category,%s,
                    %s,%s,%s,%s,%s,'NEW'::wallpaper_badge,%s,false,0,true,true,
                    'Pixora Studio',%s,%s
                ) ON CONFLICT (id) DO UPDATE SET
                    name=EXCLUDED.name,description=EXCLUDED.description,
                    description_rich=EXCLUDED.description_rich,type=EXCLUDED.type,
                    category=EXCLUDED.category,tags=EXCLUDED.tags,
                    image_path=EXCLUDED.image_path,preview_path=EXCLUDED.preview_path,
                    image_size=EXCLUDED.image_size,preview_size=EXCLUDED.preview_size,
                    glow_color=EXCLUDED.glow_color,published=true,
                    media_width=EXCLUDED.media_width,media_height=EXCLUDED.media_height,
                    updated_at=now()
                RETURNING id,published
                """,
                (sid, meta.get("name", meta.get("title", sid)), description, rich_description,
                 db_type, category, tags, f"{sid}.webp", f"{sid}_preview.webp",
                 info["image_size"], info["preview_size"], "#F472B6", sort_order,
                 info["width"], info["height"]),
            )
            row = cur.fetchone()
            if not row or not row[1]:
                raise RuntimeError(f"Postgres did not publish {sid}")
            published.append(sid)
            completed_types = {"static": 0, "panoramic": 0, "canvas_scene": 0}
            published_set = set(published)
            for _, done_meta in metas:
                if done_meta["id"] in published_set:
                    completed_types[done_meta["type"]] += 1
            write_progress(
                completed=len(published), percent=round((len(published) / 97) * 100, 1),
                completed_by_type=completed_types, published_ids=published[-12:],
            )

        # One atomic catalog update after every canvas object is available.
        existing_order = [x.get("id") for x in catalog.get("items", [])]
        new_canvas = [m["id"] for _, m in metas if m["type"] == "canvas_scene"]
        ordered = [catalog_entries[sid] for sid in new_canvas]
        ordered += [catalog_entries[sid] for sid in existing_order if sid not in set(new_canvas)]
        catalog["items"] = ordered
        catalog["version"] = int(catalog.get("version", 0) or 0) + 1
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        conn.commit()
    except Exception as exc:
        conn.rollback()
        write_progress(status="error", error=str(exc), current_type="error")
        raise
    finally:
        cur.close()
        conn.close()

    fcm = send_catalog_invalidate("wallpapers")
    receipt = {
        "published_at": datetime.now(timezone.utc).isoformat(),
        "total": len(published), "counts": counts,
        "catalog_version": catalog["version"], "fcm": bool(fcm),
        "scene_ids": published,
    }
    RECEIPT.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_progress(
        status="complete", completed=97, percent=100, current="Lote publicado",
        current_type="complete", completed_by_type=counts, published_ids=published[-12:],
        catalog_version=catalog["version"], fcm=bool(fcm), error=None,
    )
    print(json.dumps(receipt, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
