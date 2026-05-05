"""
Apply a Supabase migration file via psycopg2 using the direct Postgres
connection. Reads the password from KEYS_LOCAL.md so it never lands in
git history or in command-line arguments visible via `ps`.

Usage:
    python tools/apply_migration.py supabase/migrations/20260505_007_app_events.sql
    python tools/apply_migration.py path1.sql path2.sql ...

The script picks the first known SUPABASE-style password line in
KEYS_LOCAL.md, then connects via the IPv4-friendly transaction pooler.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

import psycopg2

KEYS = Path(__file__).resolve().parent.parent / "KEYS_LOCAL.md"
PROJECT_REF = "vzuwvsmlyigjtsearxym"


def get_password() -> str:
    if not KEYS.exists():
        raise SystemExit(f"KEYS_LOCAL.md not found at {KEYS}")
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Database password:\s*([A-Za-z0-9_!@#%^&*+=:.\-]+)", text)
    if not m:
        raise SystemExit("'Database password' not found in KEYS_LOCAL.md")
    return m.group(1)


def connect():
    """Direct connection via IPv4 add-on. The user enabled the
    'Dedicated IPv4 address' add-on (paid) on 2026-05-05 so
    `db.{PROJECT_REF}.supabase.co` now resolves to an IPv4 address."""
    pw = get_password()
    dsn = f"postgresql://postgres:{pw}@db.{PROJECT_REF}.supabase.co:5432/postgres"
    return psycopg2.connect(dsn, connect_timeout=10)


def apply_file(conn, path: Path):
    sql = path.read_text(encoding="utf-8")
    with conn.cursor() as cur:
        cur.execute(sql)
    conn.commit()
    print(f"  OK applied {path.name} ({len(sql):,} bytes)")


def main(args: list[str]):
    if not args:
        print(__doc__)
        sys.exit(1)
    files = [Path(a) for a in args]
    for f in files:
        if not f.exists():
            raise SystemExit(f"file not found: {f}")
    conn = connect()
    print(f"Connected to {PROJECT_REF}")
    try:
        for f in files:
            apply_file(conn, f)
    finally:
        conn.close()
    print("All migrations applied successfully.")


if __name__ == "__main__":
    main(sys.argv[1:])
