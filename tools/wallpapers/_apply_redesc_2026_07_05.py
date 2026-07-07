"""Apply the 2026-07-05 mass re-description to Postgres.

Reads the out_*.json files produced by the editorial analysis agents
(one per category batch), validates each entry, backs up the current
name/description of every touched row, and UPDATEs wallpapers.

Rollback: _redesc_backup_2026_07_05.json holds the previous values.
"""
import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

SCRATCH = Path(r"C:/Users/lalo/AppData/Local/Temp/claude/D--orbix-Pixora-IA/fa81966f-f4a6-45cf-b4cc-44b40ae071d9/scratchpad")
BACKUP = Path(__file__).parent / "_redesc_backup_2026_07_05.json"

BANNED = ["hermoso wallpaper", "perfecto para tu pantalla", "increíble diseño",
          "beautiful wallpaper", "stunning"]

entries = {}
for f in sorted(SCRATCH.glob("out_*.json")):
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"SKIP {f.name}: parse error {e}")
        continue
    ok = 0
    for it in data:
        wid = it.get("id")
        name = (it.get("new_name") or "").strip()
        desc = (it.get("new_description") or "").strip()
        if not wid or not name or not desc:
            print(f"  SKIP {wid}: missing fields ({f.name})")
            continue
        if not (100 <= len(desc) <= 700):
            print(f"  SKIP {wid}: desc len {len(desc)} out of range ({f.name})")
            continue
        low = desc.lower()
        if any(b in low for b in BANNED):
            print(f"  SKIP {wid}: banned generic phrase ({f.name})")
            continue
        entries[wid] = (name, desc)
        ok += 1
    print(f"{f.name}: {ok}/{len(data)} valid")

print(f"\nTotal valid entries: {len(entries)}")
if not entries:
    raise SystemExit("Nothing to apply.")

conn = connect()
cur = conn.cursor()

# Backup current values
cur.execute(
    "SELECT id, name, description FROM wallpapers WHERE id = ANY(%s);",
    (list(entries.keys()),),
)
backup = {r[0]: {"name": r[1], "description": r[2]} for r in cur.fetchall()}
BACKUP.write_text(json.dumps(backup, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"Backup of {len(backup)} rows -> {BACKUP.name}")

missing = [wid for wid in entries if wid not in backup]
if missing:
    print(f"WARN: {len(missing)} ids not found in DB (skipped): {missing[:5]}...")

updated = 0
for wid, (name, desc) in entries.items():
    if wid not in backup:
        continue
    cur.execute(
        "UPDATE wallpapers SET name = %s, description = %s WHERE id = %s;",
        (name, desc, wid),
    )
    updated += cur.rowcount

conn.commit()
cur.close()
conn.close()
print(f"\nDONE — {updated} wallpapers actualizados (titulo + descripcion).")
