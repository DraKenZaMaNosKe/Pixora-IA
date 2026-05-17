# -*- coding: utf-8 -*-
"""Seed the 4 smoke-test strings for the 3D - TILT section.

Inserts one app_section (WALLPAPERS), one app_component
(ParallaxWallpapersPage), and four app_strings.

Idempotent: re-running updates the strings to the values defined here.
"""
import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

import re
from pathlib import Path
import psycopg2

KEYS = Path(__file__).resolve().parent.parent.parent / "KEYS_LOCAL.md"
pw = re.search(r"Database password:\s*([A-Za-z0-9_!@#%^&*+=:.\-]+)", KEYS.read_text(encoding="utf-8")).group(1)

DSN = f"postgresql://postgres:{pw}@db.vzuwvsmlyigjtsearxym.supabase.co:5432/postgres"

SECTION_NAME = "WALLPAPERS"
COMPONENT = {
    "name": "ParallaxWallpapersPage",
    "file_path": "lib/features/parallax_wallpapers/presentation/pages/parallax_wallpapers_page.dart",
    "description": "Pantalla 3D - TILT (parallax wallpapers grid + editorial header)",
}

STRINGS = [
    {
        "key": "wallpapers.tilt_3d.badge_count_label",
        "es": "piezas curadas",
        "en": "curated pieces",
    },
    {
        "key": "wallpapers.tilt_3d.title_part1",
        "es": "Profundidad",
        "en": "Curated",
    },
    {
        "key": "wallpapers.tilt_3d.title_part2",
        "es": "curada.",
        "en": "depth.",
    },
    {
        "key": "wallpapers.tilt_3d.subtitle",
        "es": "el equipo de Pixora elige - semanal",
        "en": "Pixora's team picks - weekly",
    },
]


def main():
    conn = psycopg2.connect(DSN, connect_timeout=15)
    cur = conn.cursor()

    # Upsert section
    cur.execute(
        """INSERT INTO app_sections (name, order_index) VALUES (%s, %s)
           ON CONFLICT (name) DO UPDATE SET order_index = EXCLUDED.order_index
           RETURNING id""",
        (SECTION_NAME, 1),
    )
    section_id = cur.fetchone()[0]
    print(f"section_id={section_id} ({SECTION_NAME})")

    # Upsert component
    cur.execute(
        """INSERT INTO app_components (section_id, name, file_path, description)
           VALUES (%s, %s, %s, %s)
           ON CONFLICT (section_id, name) DO UPDATE
             SET file_path = EXCLUDED.file_path,
                 description = EXCLUDED.description
           RETURNING id""",
        (section_id, COMPONENT["name"], COMPONENT["file_path"], COMPONENT["description"]),
    )
    component_id = cur.fetchone()[0]
    print(f"component_id={component_id} ({COMPONENT['name']})")

    # Upsert strings
    for s in STRINGS:
        cur.execute(
            """INSERT INTO app_strings (component_id, key, es, en)
               VALUES (%s, %s, %s, %s)
               ON CONFLICT (key) DO UPDATE
                 SET es = EXCLUDED.es, en = EXCLUDED.en, component_id = EXCLUDED.component_id""",
            (component_id, s["key"], s["es"], s["en"]),
        )
        print(f"  string {s['key']:40} ES={s['es'][:30]!r}")

    conn.commit()
    cur.close()
    conn.close()
    print("OK - seed applied")


if __name__ == "__main__":
    main()
