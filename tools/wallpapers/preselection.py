"""Preselección — review local content batches before uploading.

Pixel Studio tab that lets Eduardo review batches in
`ia_contenido_pipeline/wallpapers/1_por_editar` (approve/reject + notes), then
promote the approved ones to `2_listo_para_subir`. NOTHING here touches
Supabase and NOTHING is published automatically.

SECURITY: the browser never sends absolute/Drive paths. Every request is
resolved against the single authorized root and validated:
  - reject `..`, absolute paths, symlinks that escape the root
  - only serve JSON / PNG / JPG / JPEG / WebP
  - never write/delete/modify the original assets

The review is stored inside each batch as `REVISION_ESCENAS.json`, written
atomically (temp file → validate → os.replace).
"""
from __future__ import annotations

import json
import os
import shutil
import tempfile
import time
from pathlib import Path

# ── Authorized roots ─────────────────────────────────────────────────────────
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar")
READY = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/2_listo_para_subir")
DOWNLOADS = Path(r"C:/Users/lalo/Downloads")
DOWNLOADS_BATCH = "__downloads__"
DOWNLOADS_STATE = ROOT / ".preselection_downloads.json"
DOWNLOADS_INBOX = ROOT / "_entrada_downloads"

ALLOWED_EXTS = {".json", ".png", ".jpg", ".jpeg", ".webp"}
REVIEW_FILE = "REVISION_ESCENAS.json"
VALID_STATES = {"aprobada", "rechazada", "pendiente"}

TYPE_BY_SUFFIX = {
    "static": "static",
    "panorama": "panoramic",
    "panoramic": "panoramic",
    "parallax": "canvas_scene",
}
EXPECT_DIMS = {
    "static": (1080, 2340),
    "canvas_scene": (1080, 2340),
    # panoramic width varies (~4192x1024) — checked loosely
}
PARALLAX_LAYERS_EXPECTED = 6


class PreselError(Exception):
    """Raised for bad/unsafe requests; carries an HTTP status."""

    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


# ── Path safety ──────────────────────────────────────────────────────────────
def _root() -> Path:
    return ROOT.resolve()


def batch_dir(batch: str) -> Path:
    """Resolve a safe batch directory under ROOT or raise PreselError."""
    if (not batch or batch in (".", "..") or "/" in batch or "\\" in batch
            or batch.startswith(".")):
        raise PreselError("invalid batch name", 400)
    root = _root()
    try:
        d = (root / batch).resolve()
        d.relative_to(root)
    except Exception:
        raise PreselError("batch escapes root", 400)
    if os.path.islink(str(d)):
        raise PreselError("symlinked batch not allowed", 400)
    if not d.is_dir():
        raise PreselError("batch not found", 404)
    return d


def _downloads_images() -> list[Path]:
    """Return only top-level images added after the current inbox was opened."""
    if not DOWNLOADS.is_dir():
        return []
    state = _downloads_state()
    started = float(state.get("started_epoch") or 0)
    return sorted(
        (p for p in DOWNLOADS.iterdir()
         if p.is_file() and not os.path.islink(str(p))
         and p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}
         and p.stat().st_mtime >= started),
        key=lambda p: (p.stat().st_mtime, p.name.lower()), reverse=True)


def _downloads_state() -> dict:
    try:
        data = json.loads(DOWNLOADS_STATE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_downloads_state(state: dict) -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(state, ensure_ascii=False, indent=2).encode("utf-8")
    fd, tmp = tempfile.mkstemp(dir=str(ROOT), prefix=".downloads_", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(payload); fh.flush(); os.fsync(fh.fileno())
        os.replace(tmp, str(DOWNLOADS_STATE))
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def reset_downloads_inbox() -> dict:
    """Start a clean intake window. Existing Downloads files remain untouched."""
    state = {"started_at": _now(), "started_epoch": time.time(), "scenes": {}}
    _save_downloads_state(state)
    return state


def safe_asset(batch: str, relpath: str) -> Path:
    """Resolve batch/relpath to a real allowed file inside the batch or raise."""
    if batch == DOWNLOADS_BATCH:
        if not relpath or "/" in relpath or "\\" in relpath or relpath in (".", ".."):
            raise PreselError("invalid Downloads asset", 400)
        f = (DOWNLOADS / relpath).resolve()
        try:
            f.relative_to(DOWNLOADS.resolve())
        except Exception:
            raise PreselError("Downloads path escape blocked", 400)
        allowed = {p.name for p in _downloads_images()}
        if f.name not in allowed or not f.is_file():
            raise PreselError("Downloads asset not found", 404)
        return f
    bd = batch_dir(batch)
    if not relpath:
        raise PreselError("missing path", 400)
    rel = relpath.replace("\\", "/").lstrip("/")
    if os.path.isabs(rel) or ".." in rel.split("/"):
        raise PreselError("path traversal blocked", 400)
    try:
        f = (bd / rel).resolve()
        f.relative_to(bd)
    except Exception:
        raise PreselError("path escapes batch", 400)
    if os.path.islink(str(f)):
        raise PreselError("symlink not allowed", 400)
    if not f.is_file():
        raise PreselError("asset not found", 404)
    if f.suffix.lower() not in ALLOWED_EXTS:
        raise PreselError("file type not allowed", 400)
    return f


# ── Scene scanning ───────────────────────────────────────────────────────────
def _img_size(p: Path):
    try:
        from PIL import Image
        with Image.open(p) as im:
            return [im.width, im.height]
    except Exception:
        return None


def _detect_type(folder_name: str) -> str:
    last = folder_name.rsplit("_", 1)[-1].lower()
    return TYPE_BY_SUFFIX.get(last, "unknown")


def _first_image(d: Path):
    if not d.is_dir():
        return None
    for f in sorted(d.iterdir()):
        if f.is_file() and f.suffix.lower() in (".webp", ".png", ".jpg", ".jpeg"):
            return f
    return None


def scan_scene(bd: Path, folder_name: str, read_dims: bool = True) -> dict:
    d = bd / "scenes" / folder_name
    typ = _detect_type(folder_name)
    assets = {"metadata": None, "spec": None, "production": None,
              "qa": None, "layers": []}
    missing: list[str] = []
    problems: list[str] = []

    def rel(p: Path) -> str:
        return f"scenes/{folder_name}/{p.name}"

    if (d / "METADATA.json").is_file():
        assets["metadata"] = f"scenes/{folder_name}/METADATA.json"
    else:
        missing.append("METADATA.json")

    if (d / "SCENE_SPEC_DRAFT.json").is_file():
        assets["spec"] = f"scenes/{folder_name}/SCENE_SPEC_DRAFT.json"
    elif typ == "canvas_scene":
        missing.append("SCENE_SPEC_DRAFT.json")

    prod_img = _first_image(d / "production")
    if prod_img is not None:
        assets["production"] = f"scenes/{folder_name}/production/{prod_img.name}"
    else:
        missing.append("production image")

    qa_img = _first_image(d / "qa")
    if qa_img is not None:
        assets["qa"] = f"scenes/{folder_name}/qa/{qa_img.name}"

    layers_dir = d / "layers"
    if layers_dir.is_dir():
        for f in sorted(layers_dir.iterdir()):
            if f.is_file() and f.suffix.lower() in (".png", ".webp"):
                assets["layers"].append(
                    f"scenes/{folder_name}/layers/{f.name}")
    if typ == "canvas_scene" and len(assets["layers"]) < PARALLAX_LAYERS_EXPECTED:
        problems.append(
            f"capas incompletas ({len(assets['layers'])}/{PARALLAX_LAYERS_EXPECTED})")

    dims = _img_size(prod_img) if (read_dims and prod_img) else None
    exp = EXPECT_DIMS.get(typ)
    if dims and exp and tuple(dims) != exp:
        problems.append(f"dims {dims[0]}x{dims[1]} (esperado {exp[0]}x{exp[1]})")

    name, title = folder_name, None
    md = d / "METADATA.json"
    if md.is_file():
        try:
            m = json.loads(md.read_text(encoding="utf-8"))
            name = m.get("name") or name
            title = m.get("title")
        except Exception:
            problems.append("METADATA.json inválido")

    return {
        "id": folder_name,
        "folder": folder_name,
        "name": name,
        "title": title,
        "type": typ,
        "dims": dims,
        "assets": assets,
        "layers_count": len(assets["layers"]),
        "missing": missing,
        "problems": problems,
        "thumb": assets["qa"] or assets["production"],
    }


def _scene_folders(bd: Path) -> list[str]:
    sc = bd / "scenes"
    if not sc.is_dir():
        return []
    return sorted(p.name for p in sc.iterdir()
                  if p.is_dir() and not p.name.startswith("."))


# ── Review persistence (atomic) ──────────────────────────────────────────────
def load_review(bd: Path) -> dict:
    f = bd / REVIEW_FILE
    if not f.is_file():
        return {}
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_review_atomic(bd: Path, review: dict) -> None:
    # validate shape before touching disk
    if not isinstance(review, dict):
        raise PreselError("review must be an object", 400)
    scenes = review.get("scenes", {})
    if not isinstance(scenes, dict):
        raise PreselError("scenes must be an object", 400)
    for sid, entry in scenes.items():
        st = (entry or {}).get("status", "pendiente")
        if st not in VALID_STATES:
            raise PreselError(f"invalid status for {sid}: {st}", 400)
    payload = json.dumps(review, ensure_ascii=False, indent=2).encode("utf-8")
    # atomic: temp in same dir → replace
    fd, tmp = tempfile.mkstemp(dir=str(bd), prefix=".rev_", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(payload)
            fh.flush()
            os.fsync(fh.fileno())
        # re-parse to be sure it's valid JSON before replacing
        json.loads(Path(tmp).read_text(encoding="utf-8"))
        os.replace(tmp, str(bd / REVIEW_FILE))
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except Exception:
                pass


# ── Public API ───────────────────────────────────────────────────────────────
def list_batches() -> dict:
    root = _root()
    if not root.is_dir():
        return {"root": str(ROOT), "batches": []}
    images = _downloads_images()
    drev = (_downloads_state().get("scenes", {}) or {})
    dcounts = {"aprobada": 0, "rechazada": 0, "pendiente": 0}
    for p in images:
        st = (drev.get(p.name, {}) or {}).get("status", "pendiente")
        dcounts[st if st in dcounts else "pendiente"] += 1
    out = [{"name": DOWNLOADS_BATCH, "label": "Descargas · imágenes nuevas",
            "source": "downloads", "scenes": len(images),
            "has_review": bool(drev), "counts": dcounts,
            "thumb": images[0].name if images else None}]
    # Structured Drive batches are intentionally not listed here. Once a batch
    # reaches Drive it belongs to the sprite editor / publication workflow;
    # Preselección is now a clean inbox for newly downloaded source images.
    return {"root": str(DOWNLOADS), "batches": out}
    for d in sorted(root.iterdir()):
        if not d.is_dir() or d.name.startswith(".") or os.path.islink(str(d)):
            continue
        folders = _scene_folders(d)
        if not folders:
            continue
        rev = load_review(d)
        counts = {"aprobada": 0, "rechazada": 0, "pendiente": 0}
        for e in (rev.get("scenes", {}) or {}).values():
            st = (e or {}).get("status", "pendiente")
            if st in counts:
                counts[st] += 1
        counts["pendiente"] += max(0, len(folders) - sum(counts.values()))
        thumb = None
        if folders:
            first = scan_scene(d, folders[0], read_dims=False)
            thumb = first["thumb"]
        out.append({
            "name": d.name,
            "scenes": len(folders),
            "has_review": (d / REVIEW_FILE).is_file(),
            "counts": counts,
            "thumb": thumb,
        })
    return {"root": str(ROOT), "batches": out}


def batch_detail(batch: str) -> dict:
    if batch == DOWNLOADS_BATCH:
        review = (_downloads_state().get("scenes", {}) or {})
        scenes, counts = [], {"aprobada": 0, "rechazada": 0, "pendiente": 0}
        for p in _downloads_images():
            r = review.get(p.name, {}) or {}
            st = r.get("status", "pendiente")
            counts[st if st in counts else "pendiente"] += 1
            scenes.append({"id": p.name, "folder": p.name, "name": p.stem,
                           "title": None, "type": "source", "dims": _img_size(p),
                           "assets": {"metadata": None, "spec": None,
                                      "production": p.name, "qa": None, "layers": []},
                           "layers_count": 0, "missing": [], "problems": [],
                           "thumb": p.name,
                           "review": {"status": st, "notes": r.get("notes", ""),
                                      "updated_at": r.get("updated_at")}})
        return {"batch": batch, "source": "downloads", "label": "Descargas · imágenes nuevas",
                "manifest": {}, "totals": {"scenes": len(scenes),
                "types": {"static": 0, "panoramic": 0, "canvas_scene": 0,
                          "unknown": 0, "source": len(scenes)}, "counts": counts},
                "scenes": scenes}
    bd = batch_dir(batch)
    folders = _scene_folders(bd)
    rev_scenes = (load_review(bd).get("scenes", {}) or {})
    scenes = []
    counts = {"aprobada": 0, "rechazada": 0, "pendiente": 0}
    types = {"static": 0, "panoramic": 0, "canvas_scene": 0, "unknown": 0}
    for name in folders:
        s = scan_scene(bd, name)
        r = rev_scenes.get(name, {})
        s["review"] = {
            "status": (r or {}).get("status", "pendiente"),
            "notes": (r or {}).get("notes", ""),
            "updated_at": (r or {}).get("updated_at"),
        }
        counts[s["review"]["status"]] = counts.get(s["review"]["status"], 0) + 1
        types[s["type"]] = types.get(s["type"], 0) + 1
        scenes.append(s)

    manifest = {}
    cm = bd / "COLLECTION_MANIFEST.json"
    if cm.is_file():
        try:
            m = json.loads(cm.read_text(encoding="utf-8"))
            manifest = {
                "collection": m.get("collection"),
                "sources": m.get("sources"),
                "scenes": m.get("scenes"),
                "per_format": m.get("per_format"),
                "published": m.get("published"),
            }
        except Exception:
            pass
    return {
        "batch": batch,
        "manifest": manifest,
        "totals": {"scenes": len(folders), "types": types, "counts": counts},
        "scenes": scenes,
    }


def get_review(batch: str) -> dict:
    if batch == DOWNLOADS_BATCH:
        return _downloads_state()
    bd = batch_dir(batch)
    return load_review(bd)


def post_review(batch: str, body: dict) -> dict:
    """Upsert one scene's review, or replace the whole 'scenes' map.

    body = {"scene": "<id>", "status": "...", "notes": "..."}  (single upsert)
      or  {"scenes": {...}}                                     (bulk replace)
    """
    is_downloads = batch == DOWNLOADS_BATCH
    bd = None if is_downloads else batch_dir(batch)
    review = _downloads_state() if is_downloads else load_review(bd)
    review.setdefault("batch", batch)
    review.setdefault("scenes", {})

    if "scenes" in body and isinstance(body["scenes"], dict):
        review["scenes"] = body["scenes"]
    else:
        sid = body.get("scene")
        if not sid or not isinstance(sid, str):
            raise PreselError("missing scene id", 400)
        # scene must actually exist in the batch
        exists = sid in {p.name for p in _downloads_images()} if is_downloads else (bd / "scenes" / sid).is_dir()
        if not exists:
            raise PreselError("scene not found in batch", 404)
        status = body.get("status", "pendiente")
        if status not in VALID_STATES:
            raise PreselError(f"invalid status: {status}", 400)
        notes = body.get("notes", "")
        if not isinstance(notes, str):
            raise PreselError("notes must be a string", 400)
        review["scenes"][sid] = {
            "status": status,
            "notes": notes[:4000],
            "updated_at": _now(),
        }

    counts = {"aprobada": 0, "rechazada": 0, "pendiente": 0}
    for e in review["scenes"].values():
        st = (e or {}).get("status", "pendiente")
        if st in counts:
            counts[st] += 1
    review["counts"] = counts
    review["updated_at"] = _now()
    (_save_downloads_state(review) if is_downloads else save_review_atomic(bd, review))
    return {"ok": True, "counts": counts, "updated_at": review["updated_at"]}


def set_status_bulk(batch: str, ids, status: str) -> dict:
    """Set the same status on many scenes at once (preserving each note).

    ids = list of scene ids, or "all"/"*"/None to target every scene folder.
    Used for 'default todas validadas' and bulk validate/reject on selection.
    """
    if status not in VALID_STATES:
        raise PreselError(f"invalid status: {status}", 400)
    is_downloads = batch == DOWNLOADS_BATCH
    bd = None if is_downloads else batch_dir(batch)
    review = _downloads_state() if is_downloads else load_review(bd)
    review.setdefault("batch", batch)
    review.setdefault("scenes", {})
    folders = ({p.name for p in _downloads_images()} if is_downloads
               else set(_scene_folders(bd)))
    if ids in (None, "*", "all"):
        target = list(folders)
    else:
        if not isinstance(ids, list):
            raise PreselError("ids must be a list", 400)
        target = [i for i in ids if isinstance(i, str) and i in folders]
    now = _now()
    for sid in target:
        prev = review["scenes"].get(sid, {}) or {}
        review["scenes"][sid] = {
            "status": status,
            "notes": prev.get("notes", ""),
            "updated_at": now,
        }
    counts = {"aprobada": 0, "rechazada": 0, "pendiente": 0}
    for e in review["scenes"].values():
        st = (e or {}).get("status", "pendiente")
        if st in counts:
            counts[st] += 1
    review["counts"] = counts
    review["updated_at"] = now
    (_save_downloads_state(review) if is_downloads else save_review_atomic(bd, review))
    return {"ok": True, "counts": counts, "updated_at": now, "changed": len(target)}


def promote_plan(batch: str) -> dict:
    """List what 'Pasar aprobadas a listo' would copy (no writes)."""
    if batch == DOWNLOADS_BATCH:
        review = (_downloads_state().get("scenes", {}) or {})
        available = {p.name: p for p in _downloads_images()}
        approved = [sid for sid, e in review.items()
                    if (e or {}).get("status") == "aprobada" and sid in available]
        files = [{"scene": sid, "rel": sid, "bytes": available[sid].stat().st_size,
                  "name": sid} for sid in approved]
        return {"batch": batch, "approved": approved, "files": files,
                "count_scenes": len(approved), "count_files": len(files),
                "total_bytes": sum(x["bytes"] for x in files)}
    bd = batch_dir(batch)
    rev_scenes = (load_review(bd).get("scenes", {}) or {})
    approved = [sid for sid, e in rev_scenes.items()
                if (e or {}).get("status") == "aprobada"
                and (bd / "scenes" / sid).is_dir()]
    files = []
    total_bytes = 0
    for sid in approved:
        for f in (bd / "scenes" / sid).rglob("*"):
            if f.is_file() and not os.path.islink(str(f)):
                size = f.stat().st_size
                total_bytes += size
                files.append({
                    "scene": sid,
                    "rel": str(f.relative_to(bd)).replace("\\", "/"),
                    "bytes": size,
                    "name": f.name,
                })
    return {"batch": batch, "approved": approved, "files": files,
            "count_scenes": len(approved), "count_files": len(files),
            "total_bytes": total_bytes}


def promote_iter(batch: str):
    """Copy approved scenes to READY/<batch>/, yielding progress dicts per file.

    Preserves originals (copy, never move/delete). Never overwrites silently:
    if the destination scene already exists, it is skipped and reported. Writes
    a PROMOTE_MANIFEST.json in the destination. Yields NDJSON-friendly dicts.
    """
    if batch == DOWNLOADS_BATCH:
        plan = promote_plan(batch)
        stamp = time.strftime("%Y%m%d_%H%M%S", time.localtime())
        dest_root = DOWNLOADS_INBOX / f"lote_{stamp}"
        dest_root.resolve().relative_to(ROOT.resolve())
        dest_root.mkdir(parents=True, exist_ok=False)
        yield {"event": "start", "count_files": plan["count_files"],
               "count_scenes": plan["count_scenes"], "total_bytes": plan["total_bytes"],
               "dest": str(dest_root), "destination_kind": "drive_inbox"}
        done = 0
        for sid in plan["approved"]:
            src = safe_asset(batch, sid); out = dest_root / sid
            shutil.copy2(str(src), str(out)); size = src.stat().st_size; done += size
            yield {"event": "file", "scene": sid, "name": sid, "bytes": size,
                   "done_bytes": done, "total_bytes": plan["total_bytes"]}
        manifest = {"operation": "copy_approved_downloads_to_drive",
                    "created_at": _now(), "source": str(DOWNLOADS),
                    "files": plan["approved"], "review": _downloads_state().get("scenes", {})}
        (dest_root / "DOWNLOADS_MANIFEST.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        reset_downloads_inbox()
        yield {"event": "done", "copied_scenes": len(plan["approved"]),
               "skipped_scenes": 0, "files_copied": len(plan["approved"]),
               "total_bytes": done, "dest": str(dest_root),
               "destination_kind": "drive_inbox"}
        return
    bd = batch_dir(batch)
    plan = promote_plan(batch)
    dest_root = (READY / batch)
    dest_root_r = dest_root.resolve()
    # safety: dest must be under READY
    dest_root_r.relative_to(READY.resolve())
    dest_root.mkdir(parents=True, exist_ok=True)

    yield {"event": "start", "count_files": plan["count_files"],
           "count_scenes": plan["count_scenes"],
           "total_bytes": plan["total_bytes"], "dest": str(dest_root)}

    copied, skipped, done_bytes = [], [], 0
    manifest_scenes = []
    for sid in plan["approved"]:
        src_scene = bd / "scenes" / sid
        dst_scene = dest_root / "scenes" / sid
        if dst_scene.exists():
            skipped.append(sid)
            yield {"event": "skip", "scene": sid, "reason": "ya existe en destino"}
            continue
        scene_files = [f for f in src_scene.rglob("*")
                       if f.is_file() and not os.path.islink(str(f))]
        for f in scene_files:
            rel = f.relative_to(src_scene)
            out = dst_scene / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(f), str(out))
            done_bytes += f.stat().st_size
            copied.append(str(f.relative_to(bd)).replace("\\", "/"))
            yield {"event": "file", "scene": sid, "name": f.name,
                   "bytes": f.stat().st_size, "done_bytes": done_bytes,
                   "total_bytes": plan["total_bytes"]}
        manifest_scenes.append(sid)

    man = {
        "operation": "promote_approved_to_ready",
        "source_batch": batch,
        "created_at": _now(),
        "scenes_copied": manifest_scenes,
        "scenes_skipped": skipped,
        "files_copied": len(copied),
        "total_bytes": done_bytes,
    }
    try:
        (dest_root / "PROMOTE_MANIFEST.json").write_text(
            json.dumps(man, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass
    yield {"event": "done", "copied_scenes": len(manifest_scenes),
           "skipped_scenes": len(skipped), "files_copied": len(copied),
           "total_bytes": done_bytes, "manifest": man}


def prepare_sprite(batch: str, scene: str) -> dict:
    """Explain (do NOT perform) the hidden-upload step for the sprite editor.

    We never publish or make anything visible automatically. This just returns
    the plan so the UI can send the scene through the existing hidden-upload +
    sprite editor flow under EXPLICIT user action.
    """
    bd = batch_dir(batch)
    if not (bd / "scenes" / scene).is_dir():
        raise PreselError("scene not found in batch", 404)
    s = scan_scene(bd, scene)
    return {
        "batch": batch,
        "scene": scene,
        "type": s["type"],
        "next_steps": [
            "Subir la escena OCULTA (published=false) al Storage/catálogo.",
            "Editarla en el editor de sprites.",
            "Aprobación final → recién ahí se hace visible en producción.",
        ],
        "warning": "Este paso NO publica nada. La subida oculta y el hacerla "
                   "visible son acciones separadas y explícitas.",
        "assets": s["assets"],
    }


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def content_type_for(p: Path) -> str:
    return {
        ".json": "application/json; charset=utf-8",
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
    }.get(p.suffix.lower(), "application/octet-stream")
