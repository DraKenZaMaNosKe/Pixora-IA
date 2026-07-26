"""Apply long rich descriptions (from Fable) to the 14 canvas_scene wallpapers.

Reads descriptions_14.json ({scene_id: rich_text_with_[[tags]]}), derives the
plain version by stripping the [[type:...]] markup, and updates:
  - Postgres wallpapers.description (plain) + description_rich (with markup)
  - catalog_index.json entry.description (plain)   [in wallpaper-images]

Works for BOTH the already-published 7 and the hidden new 7. Does NOT change the
`published` flag — visibility stays exactly as it is.
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET = "wallpaper-images"

SK = re.findall(
    r"eyJ[A-Za-z0-9_\-\.]{100,500}",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
)[0]

DESC_JSON = Path(
    r"C:/Users/lalo/AppData/Local/Temp/claude/D--Orbix-Pixora-IA/"
    r"fa81966f-f4a6-45cf-b4cc-44b40ae071d9/scratchpad/descriptions_14.json"
)

# [[type:visible text]] -> visible text   (keeps the human-readable words)
TAG_RE = re.compile(r"\[\[(?:name|place|power|emotion):([^\]]*)\]\]")


def strip_markup(rich):
    return TAG_RE.sub(r"\1", rich)


def plain_for_column(rich, limit=700):
    """Plain text for the `description` column (CHECK: 1..700 chars).
    The full long text lives in `description_rich`; this is only the
    card/search/share snippet, so trim at the last sentence boundary that
    fits, falling back to a word boundary."""
    plain = strip_markup(rich)
    if len(plain) <= limit:
        return plain
    window = plain[:limit]
    cut = max(window.rfind(". "), window.rfind("? "), window.rfind("! "))
    if cut >= 200:                      # keep a substantial snippet
        return window[: cut + 1]
    cut = window.rfind(" ")
    return (window[:cut] if cut > 0 else window).rstrip() + "…"


def get_json(bucket, remote):
    import time
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}?nc={time.time()}"
    req = urllib.request.Request(url)
    req.add_header("Cache-Control", "no-cache")
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


def put_json(bucket, remote, data):
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}", data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("apikey", SK)
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "no-cache, max-age=0")
    with urllib.request.urlopen(req, timeout=180) as r:
        print(f"    PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


def main():
    descs = json.loads(DESC_JSON.read_text(encoding="utf-8"))
    print(f"Loaded {len(descs)} descriptions")

    # sanity: no leftover markup after stripping
    for sid, rich in descs.items():
        leftover = re.findall(r"\[\[", strip_markup(rich))
        if leftover:
            print(f"  !! {sid}: leftover markup after strip")

    # --- Postgres ---
    from apply_migration import connect
    conn = connect()
    conn.set_client_encoding("UTF8")
    cur = conn.cursor()
    updated = []
    for sid, rich in descs.items():
        plain = plain_for_column(rich)
        cur.execute(
            "UPDATE wallpapers SET description = %s, description_rich = %s "
            "WHERE id = %s RETURNING id, published;",
            (plain, rich, sid),
        )
        row = cur.fetchone()
        if row:
            updated.append((sid, row[1]))
            print(f"  PG  {sid:42} published={row[1]}  "
                  f"(plain {len(plain)} / rich {len(rich)} chars)")
        else:
            print(f"  !! PG no row for {sid}")
    conn.commit()
    cur.close()
    conn.close()

    # --- catalog_index (plain description shown on cards) ---
    print("\nUpdating catalog_index...")
    cat = get_json(IMG_BUCKET, "catalog_index.json")
    cat["version"] = (cat.get("version", 0) or 0) + 1
    idx = {it.get("id"): it for it in cat.get("items", [])}
    touched = 0
    for sid, rich in descs.items():
        if sid in idx:
            idx[sid]["description"] = plain_for_column(rich)
            touched += 1
    put_json(IMG_BUCKET, "catalog_index.json", cat)
    print(f"  catalog v{cat['version']} — {touched}/{len(descs)} entries touched")

    print(f"\nDONE — {len(updated)} Postgres rows updated")


if __name__ == "__main__":
    main()
