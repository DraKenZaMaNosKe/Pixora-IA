"""
Generic helper: attach a `cultural` editorial block to a live wallpaper in
the catalog. Use this every time you ship a new mythological wallpaper —
no APK rebuild needed; the Flutter app reads the catalog at startup and
renders the Códice layout when `cultural` is present.

Usage:
  1. Edit the WALLPAPER_ID and CULTURAL dict below.
  2. Run: python tools/wallpapers/add_cultural_data.py
  3. The catalog is patched + re-uploaded to Supabase.
  4. User closes / reopens Pixora to refresh the catalog cache (~6h TTL).

Schema reference (matches lib/features/hot_wallpapers/data/models/cultural_content.dart):
  cultural = {
    "chapter":      "Capítulo IX · Mictlán",          # eyebrow above title
    "subtitle":     "Señor del Inframundo",            # italic gold line under name
    "pronunciation":"[mik · tlan · te · KU · tli]",    # phonetic in muted text
    "lead":         "...",                              # ~30 word intro w/ drop cap
    "facts": [                                          # 2-col grid (best in pairs)
      {"key": "Cultura",     "value": "Mexica · Tolteca"},
      {"key": "Reino",       "value": "Mictlán · 9 niveles"},
      {"key": "Esposa",      "value": "Mictecacíhuatl"},
      {"key": "Mensajero",   "value": "Xolotl · perro guía"},
      {"key": "Animales",    "value": "Búho · murciélago · araña"},
      {"key": "Día Sagrado", "value": "14 de noviembre"},
    ],
    "ofrenda": {                                        # gold-tinted card
      "label": "Ofrenda",
      "text":  "Cempasúchil, copal, sangre y la primera comida del año..."
    },
    "cta": "Invocar al Señor"                           # currently unused, future
  }

All fields are OPTIONAL. Omit any key you don't have data for and the layout
will simply skip rendering that section.
"""
from __future__ import annotations
import json, re, sys, urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
PROJECT_REF = "vzuwvsmlyigjtsearxym"
BUCKET = "wallpaper-videos"
CATALOG_KEY = "live_wallpaper_catalog.json"

# ─── EDIT THESE TWO PER WALLPAPER ───────────────────────────────────────────
WALLPAPER_ID = "mictlantecuhtli"

CULTURAL = {
    "chapter": "Capítulo IX · Mictlán",
    "subtitle": "Señor del Inframundo",
    "pronunciation": "[mik · tlan · te · KU · tli]",
    "lead": "Esposo de Mictecacíhuatl, gobierna los nueve niveles del Mictlán. Recibe a las almas que mueren de causa natural; junto a Quetzalcóatl creó al hombre de huesos antiguos.",
    "facts": [
        {"key": "Cultura",     "value": "Mexica · Tolteca"},
        {"key": "Reino",       "value": "Mictlán · 9 niveles"},
        {"key": "Esposa",      "value": "Mictecacíhuatl"},
        {"key": "Mensajero",   "value": "Xolotl · perro guía"},
        {"key": "Animales",    "value": "Búho · murciélago · araña"},
        {"key": "Día Sagrado", "value": "14 de noviembre"},
    ],
    "ofrenda": {
        "label": "Ofrenda",
        "text":  "Cempasúchil, copal, sangre y la primera comida del año. Las almas tardaban cuatro años en cruzar los nueve ríos del inframundo."
    },
    "cta": "Invocar al Señor",
}
# ─────────────────────────────────────────────────────────────────────────────


def get_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", text)
    if not m:
        raise SystemExit("Service Role Key not found in KEYS_LOCAL.md")
    return m.group(1)


def main():
    SVC = get_service_key()

    url = f"https://{PROJECT_REF}.supabase.co/storage/v1/object/public/{BUCKET}/{CATALOG_KEY}"
    with urllib.request.urlopen(url, timeout=30) as r:
        catalog = json.loads(r.read())

    found = False
    for w in catalog.get("wallpapers", []):
        if w.get("id") == WALLPAPER_ID:
            w["cultural"] = CULTURAL
            found = True
            print(f"  Patched {WALLPAPER_ID}: cultural block attached")
            print(f"    chapter:  {CULTURAL.get('chapter')!r}")
            print(f"    subtitle: {CULTURAL.get('subtitle')!r}")
            print(f"    facts:    {len(CULTURAL.get('facts', []))}")
            break
    if not found:
        raise SystemExit(f"Wallpaper id {WALLPAPER_ID!r} not found in catalog")

    body = json.dumps(catalog, ensure_ascii=False, indent=2).encode("utf-8")
    put = urllib.request.Request(
        f"https://{PROJECT_REF}.supabase.co/storage/v1/object/{BUCKET}/{CATALOG_KEY}",
        data=body, method="PUT")
    put.add_header("Authorization", f"Bearer {SVC}")
    put.add_header("Content-Type", "application/json")
    put.add_header("x-upsert", "true")
    with urllib.request.urlopen(put, timeout=30) as r:
        print(f"  Catalog re-uploaded: status {r.status}, {len(body)} bytes")
    print()
    print("Done. User must close / reopen Pixora to invalidate the 6h catalog cache.")


if __name__ == "__main__":
    main()
