"""Move the color markup out of `description` into a new `description_rich`
column, so OLD app versions (which render `description` as plain text) never
see raw `[[name:...]]` markup, while the NEW app reads `description_rich`.

Steps:
  1. ADD COLUMN description_rich text (nullable).
  2. For every row whose description has markup: copy it to description_rich,
     and set description = stripped(markup)  (plain, byte-identical original).
  3. Recreate wallpapers_v with description_rich appended (CREATE OR REPLACE,
     new column at the end — no DROP, keeps dependencies intact).

Idempotent: re-running only touches rows that still have markup in description.
"""
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

MARKUP = re.compile(r"\[\[(\w+):(.*?)\]\]", re.DOTALL)


def strip(raw):
    return MARKUP.sub(lambda m: m.group(2), raw)


VIEW_SQL = """
CREATE OR REPLACE VIEW wallpapers_v AS
 SELECT id,
    name,
    description,
    type,
    category,
    tags,
    image_path,
    preview_path,
    image_size,
    preview_size,
    media_width,
    media_height,
    wp_storage_base() || image_path AS image_url,
    wp_storage_base() || preview_path AS preview_url,
    glow_color,
    badge,
    sort_order,
    featured,
    trending_score,
    view_count,
    install_count,
    share_count,
    favorite_count,
    published,
    author_name,
    author_user_id,
    tsv,
    created_at,
    updated_at,
    daily_eligible,
    description_rich
   FROM wallpapers
  WHERE published = true;
"""

conn = connect()
cur = conn.cursor()

# 1) nueva columna
cur.execute("ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS description_rich text;")

# 2) mover markup → rich, restaurar plano en description
cur.execute("SELECT id, description FROM wallpapers WHERE description LIKE '%[[%';")
rows = cur.fetchall()
print(f"Filas con markup a separar: {len(rows)}")
moved = 0
for wid, rich in rows:
    plain = strip(rich)
    cur.execute(
        "UPDATE wallpapers SET description_rich = %s, description = %s WHERE id = %s;",
        (rich, plain, wid),
    )
    moved += cur.rowcount

# 3) recrear vista con description_rich
cur.execute(VIEW_SQL)

conn.commit()

# verificación
cur.execute("SELECT count(*) FROM wallpapers WHERE description LIKE '%[[%';")
still_plain_bad = cur.fetchone()[0]
cur.execute("SELECT count(*) FROM wallpapers WHERE description_rich LIKE '%[[%';")
rich_count = cur.fetchone()[0]
cur.execute("SELECT description, description_rich FROM wallpapers_v WHERE id='serenity_endymion_amor';")
r = cur.fetchone()

cur.close()
conn.close()

print(f"Movidas: {moved}")
print(f"description con markup restante (debe ser 0): {still_plain_bad}")
print(f"description_rich con markup: {rich_count}")
if r:
    print("sample plain:", (r[0] or "")[:70])
    print("sample rich :", (r[1] or "")[:70])
print("\nDONE — markup separado en description_rich; description queda plano.")
