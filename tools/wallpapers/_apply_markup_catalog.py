"""Validate + apply color markup produced by the editorial agents.

Reads every markup_out_*.json from scratchpad. For each {id, markup}:
  - strip the markup and require it to be BYTE-IDENTICAL to the current DB
    description (agents must not alter the text, only wrap fragments).
  - roles must be in {name, place, power, emotion}.
  - balanced markers, length <= 700.

Valid rows are backed up (id -> old description) then UPDATEd. Invalid rows
are reported and skipped (they keep their plain description — safe).

Rollback: _markup_backup_2026_07_05.json.
"""
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

SC = Path(r"C:/Users/lalo/AppData/Local/Temp/claude/D--orbix-Pixora-IA/fa81966f-f4a6-45cf-b4cc-44b40ae071d9/scratchpad")
BACKUP = Path(__file__).parent / "_markup_backup_2026_07_05.json"
INVENTORY = SC / "markup_inventory.json"

MARKUP = re.compile(r"\[\[(\w+):(.*?)\]\]", re.DOTALL)
ROLES = {"name", "place", "power", "emotion"}


def strip(raw):
    return MARKUP.sub(lambda m: m.group(2), raw)


# Original descriptions keyed by id (source of truth for the identity check).
orig = {x["id"]: x["description"] for x in json.load(open(INVENTORY, encoding="utf-8"))}

candidates = {}
for f in sorted(SC.glob("markup_out_*.json")):
    try:
        data = json.load(open(f, encoding="utf-8"))
    except Exception as e:
        print(f"SKIP {f.name}: parse error {e}")
        continue
    for it in data:
        wid = it.get("id")
        mk = it.get("markup")
        if wid and mk:
            candidates[wid] = mk

print(f"Candidatos totales: {len(candidates)}")

valid, invalid = {}, []
for wid, mk in candidates.items():
    if wid not in orig:
        invalid.append((wid, "id no está en inventario"))
        continue
    # balance de marcas
    if mk.count("[[") != mk.count("]]") or mk.count("[[") != len(MARKUP.findall(mk)):
        invalid.append((wid, "marcas desbalanceadas/malformadas"))
        continue
    # roles válidos
    bad = [r for r, _ in MARKUP.findall(mk) if r not in ROLES]
    if bad:
        invalid.append((wid, f"rol inválido: {bad[:3]}"))
        continue
    # identidad del texto
    if strip(mk) != orig[wid]:
        invalid.append((wid, "texto alterado (strip != original)"))
        continue
    # longitud
    if len(mk) > 700:
        invalid.append((wid, f"len {len(mk)} > 700"))
        continue
    # que tenga al menos una marca (si no, no aporta)
    if not MARKUP.search(mk):
        invalid.append((wid, "sin marcas"))
        continue
    valid[wid] = mk

print(f"Válidos: {len(valid)}  ·  Inválidos: {len(invalid)}")
for wid, why in invalid[:40]:
    print(f"  ✗ {wid}: {why}")

if "--dry" in sys.argv:
    raise SystemExit("dry-run, no se aplicó nada.")

if not valid:
    raise SystemExit("Nada válido para aplicar.")

conn = connect()
cur = conn.cursor()

# Backup (merge con backup previo si existe, para no perder rollback de tandas)
backup = {}
if BACKUP.exists():
    backup = json.load(open(BACKUP, encoding="utf-8"))
cur.execute("SELECT id, description FROM wallpapers WHERE id = ANY(%s);", (list(valid.keys()),))
for wid, desc in cur.fetchall():
    backup.setdefault(wid, desc)  # no sobrescribir el original ya respaldado
json.dump(backup, open(BACKUP, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"Backup acumulado: {len(backup)} filas -> {BACKUP.name}")

updated = 0
for wid, mk in valid.items():
    cur.execute("UPDATE wallpapers SET description = %s WHERE id = %s;", (mk, wid))
    updated += cur.rowcount
conn.commit()
cur.close()
conn.close()
print(f"\nDONE — {updated} descripciones con markup aplicadas.")
