"""
One-shot: inserta los 3 wallpapers de Bulma (static + 2 panoramic) en la
tabla `wallpapers` de Postgres. Los archivos en Storage ya están subidos
(via _upload_bulma_assets.py); solo falta el registro Postgres porque la
app ahora lee de wallpapers_v (no del JSON legacy donde sí estaban).

Idempotente: usa Prefer: resolution=merge-duplicates así que correrlo dos
veces solo refresca los rows existentes en vez de fallar.
"""
from __future__ import annotations
import sys, re, json, urllib.request
from pathlib import Path
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
SERVICE_KEY = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", KEYS).group(1)

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def upsert(rows: list[dict]) -> None:
    """POST a la tabla wallpapers con upsert (merge si ID existe)."""
    body = json.dumps(rows, ensure_ascii=False).encode("utf-8")
    url = f"{PROJECT}/rest/v1/wallpapers"
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("apikey", SERVICE_KEY)
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Prefer", "resolution=merge-duplicates,return=representation")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            resp = json.loads(r.read().decode("utf-8"))
            for row in resp:
                print(f"  ✓ {row.get('id')} ({row.get('category')}, type={row.get('type')})")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"  ✗ HTTP {e.code}: {err_body[:500]}")
        sys.exit(1)


rows = [
    {
        "id": "bulma_portrait",
        "type": "static",
        "name": "Bulma - Cyan Hair Portrait",
        "description": "Bulma, la genio cientifica de cabello turquesa de Dragon Ball",
        "category": "ANIME",
        "tags": ["bulma", "dragon_ball", "anime", "girl", "blue_hair", "scifi", "portrait"],
        "image_path": "bulma_portrait.webp",
        "preview_path": "bulma_portrait_preview.webp",
        "image_size": 199718,
        "preview_size": 53384,
        "glow_color": "#00E5FF",
        "badge": "NEW",
        "sort_order": 1,
        "featured": True,
        "published": True,
        "author_name": "Pixora Studio",
    },
    {
        "id": "bulma_bedroom_pano",
        "type": "panoramic",
        "name": "Bulma - Holographic Bedroom",
        "description": "Ultra-wide panoramic de la habitacion futurista de Bulma con pantallas holograficas al atardecer",
        "category": "PANORAMIC",
        "tags": ["bulma", "dragon_ball", "anime", "panoramic", "scifi", "bedroom", "holographic"],
        "image_path": "bulma_bedroom_pano.webp",
        "preview_path": "bulma_bedroom_pano_preview.webp",
        "image_size": 431156,
        "preview_size": 22820,
        "glow_color": "#FF80AB",
        "badge": "NEW",
        "sort_order": 1,
        "featured": True,
        "published": True,
        "author_name": "Pixora Studio",
    },
    {
        "id": "bulma_vanity_pano",
        "type": "panoramic",
        "name": "Bulma - Rose Gold Vanity",
        "description": "Ultra-wide panoramic de Bulma en su tocador glamuroso de oro rosa con orquideas",
        "category": "PANORAMIC",
        "tags": ["bulma", "dragon_ball", "anime", "panoramic", "vanity", "glamour", "pink"],
        "image_path": "bulma_vanity_pano.webp",
        "preview_path": "bulma_vanity_pano_preview.webp",
        "image_size": 501136,
        "preview_size": 25790,
        "glow_color": "#FFB6C1",
        "badge": "NEW",
        "sort_order": 1,
        "featured": True,
        "published": True,
        "author_name": "Pixora Studio",
    },
]

print("[1/2] Upserting 3 Bulma rows into wallpapers table…")
upsert(rows)

print("\n[2/2] Verifying via wallpapers_v…")
url = f"{PROJECT}/rest/v1/wallpapers_v?select=id,name,category,type,published,image_url,preview_url&id=in.(bulma_portrait,bulma_bedroom_pano,bulma_vanity_pano)"
req = urllib.request.Request(url)
req.add_header("apikey", SERVICE_KEY)
req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
with urllib.request.urlopen(req, timeout=15) as r:
    rows = json.loads(r.read().decode("utf-8"))
print(f"  Encontrados {len(rows)}/3:")
for row in rows:
    print(f"    {row['id']:<20}  {row['category']:<10}  {row['type']:<10}  published={row['published']}")

print("\nOK — Bulma visible en wallpapers_v. Ya debe aparecer en la app en sección ANIME y PANORAMIC.")
print("Tip: si la app no refresca, dispara FCM con: python tools/wallpapers/_fcm_push.py catalog all")
