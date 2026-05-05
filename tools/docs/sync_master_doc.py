"""
End-to-end sync: read .docx from Drive → render Brutalist HTML → upload
to Supabase Storage as public master_doc.html. Idempotent — safe to run
on a schedule (Windows Task Scheduler / cron).

Usage: python tools/docs/sync_master_doc.py [--quiet]

Exit codes:
  0  rendered + uploaded successfully (or no changes detected)
  1  error
"""
from __future__ import annotations
import hashlib
import re
import sys
import urllib.request
import urllib.error
from pathlib import Path
from datetime import datetime
import subprocess

if sys.stdout is not None:
    sys.stdout.reconfigure(encoding="utf-8")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
SRC_DOCX = Path(r"G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx")
RENDER_SCRIPT = Path(r"D:/Orbix/Pixora-IA/tools/docs/render_master_doc_brutalist.py")
RENDERED_HTML = Path(r"D:/Orbix/Pixora-IA/docs/master_doc/index.html")
HASH_CACHE = Path(r"D:/Orbix/Pixora-IA/docs/master_doc/.last_synced_sha")
PROJECT_REF = "vzuwvsmlyigjtsearxym"
BUCKET = "wallpaper-images"
REMOTE_NAME = "master_doc.html"

QUIET = "--quiet" in sys.argv


def log(msg: str):
    if not QUIET:
        print(f"[{datetime.now():%H:%M:%S}] {msg}")


def get_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", text)
    if not m:
        raise SystemExit("Service Role Key not found in KEYS_LOCAL.md")
    return m.group(1)


def main() -> int:
    if not SRC_DOCX.exists():
        log(f"SOURCE NOT FOUND: {SRC_DOCX}")
        return 1

    # Check if .docx changed since last sync
    docx_sha = hashlib.sha256(SRC_DOCX.read_bytes()).hexdigest()
    last_sha = HASH_CACHE.read_text().strip() if HASH_CACHE.exists() else ""

    if docx_sha == last_sha:
        log("No changes in .docx since last sync — skipping")
        return 0

    log(f"Detected change in .docx (sha={docx_sha[:12]})")

    # 1. Render HTML from .docx
    log("Rendering Brutalist HTML...")
    result = subprocess.run(
        [sys.executable, str(RENDER_SCRIPT)],
        capture_output=True, text=True, encoding="utf-8",
    )
    if result.returncode != 0:
        log(f"Render failed:\n{result.stderr}")
        return 1
    log(f"Rendered: {RENDERED_HTML.stat().st_size:,} bytes")

    # 2. Upload to Supabase
    log(f"Uploading to {BUCKET}/{REMOTE_NAME}...")
    svc = get_service_key()
    body = RENDERED_HTML.read_bytes()
    url = f"https://{PROJECT_REF}.supabase.co/storage/v1/object/{BUCKET}/{REMOTE_NAME}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {svc}")
    req.add_header("Content-Type", "text/html; charset=utf-8")
    req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "max-age=300, public")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            if r.status not in (200, 201):
                log(f"Upload returned {r.status}: {r.read()[:200]}")
                return 1
    except urllib.error.HTTPError as e:
        log(f"Upload HTTP error {e.code}: {e.read()[:200]}")
        return 1

    # 3. Save the synced sha so next run is no-op until next change
    HASH_CACHE.parent.mkdir(parents=True, exist_ok=True)
    HASH_CACHE.write_text(docx_sha)

    log("OK synced")
    log(f"   Public URL: https://{PROJECT_REF}.supabase.co/storage/v1/object/public/{BUCKET}/{REMOTE_NAME}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
