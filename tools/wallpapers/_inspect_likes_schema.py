"""
Inspeccion directa a Postgres para entender el schema de likes.

Verifica:
1. Definicion de RPC increment_likes y decrement_likes
2. Si wallpaper_stats es VIEW o TABLE
3. Si esta en la publication de realtime
4. Triggers que actualizan wallpaper_stats
"""
import re
import sys
from pathlib import Path
import psycopg2

REPO = Path(__file__).resolve().parent.parent.parent
KEYS = REPO / "KEYS_LOCAL.md"


def conn_str() -> str:
    """Usa la conexion directa (no el pooler), que requiere dedicated IPv4
    add-on (Pixora lo tiene activo desde 2026-05-05)."""
    text = KEYS.read_text(encoding="utf-8")
    pw = re.search(r"Database password:\s*(\S+)", text).group(1)
    host = re.search(r"Direct host:\s*(\S+):\d+", text).group(1)
    return f"postgresql://postgres:{pw}@{host}:5432/postgres"


def main():
    conn = psycopg2.connect(conn_str())
    cur = conn.cursor()

    print("=" * 70)
    print("  1. Definicion de RPC increment_likes / decrement_likes")
    print("=" * 70)
    cur.execute("""
        SELECT proname, pg_get_functiondef(oid) AS def
        FROM pg_proc
        WHERE pronamespace = 'public'::regnamespace
          AND proname IN ('increment_likes', 'decrement_likes',
                          'wp_log_event')
        ORDER BY proname;
    """)
    for name, definition in cur.fetchall():
        print(f"\n--- {name} ---")
        print(definition)

    print("\n" + "=" * 70)
    print("  2. wallpaper_stats: VIEW o TABLE?")
    print("=" * 70)
    cur.execute("""
        SELECT table_type, view_definition
        FROM information_schema.tables t
        LEFT JOIN information_schema.views v
          ON t.table_name = v.table_name
         AND t.table_schema = v.table_schema
        WHERE t.table_name = 'wallpaper_stats' AND t.table_schema = 'public';
    """)
    rows = cur.fetchall()
    if rows:
        for typ, vdef in rows:
            print(f"Tipo: {typ}")
            if vdef:
                print(f"\nDefinicion de la vista:")
                print(vdef)
    else:
        print("(no encontrado)")

    print("\n" + "=" * 70)
    print("  3. Columnas de wallpaper_stats")
    print("=" * 70)
    cur.execute("""
        SELECT column_name, data_type, is_nullable, column_default
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'wallpaper_stats'
        ORDER BY ordinal_position;
    """)
    for col, typ, nullable, default in cur.fetchall():
        print(f"  {col:<20} {typ:<20} null={nullable}  default={default}")

    print("\n" + "=" * 70)
    print("  4. Realtime publication (supabase_realtime)")
    print("=" * 70)
    cur.execute("""
        SELECT schemaname, tablename
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND tablename IN ('wallpaper_stats', 'wallpaper_likes', 'wallpapers');
    """)
    rows = cur.fetchall()
    if rows:
        print("Tablas con realtime habilitado:")
        for s, t in rows:
            print(f"  + {s}.{t}")
    else:
        print("  XX NINGUNA tabla de likes esta en realtime publication")

    print("\n" + "=" * 70)
    print("  5. Triggers de wallpapers y wallpaper_likes")
    print("=" * 70)
    cur.execute("""
        SELECT event_object_table, trigger_name, action_timing,
               event_manipulation, action_statement
        FROM information_schema.triggers
        WHERE event_object_schema = 'public'
          AND event_object_table IN ('wallpapers', 'wallpaper_likes',
                                     'wallpaper_stats', 'wallpaper_events')
        ORDER BY event_object_table, trigger_name;
    """)
    rows = cur.fetchall()
    if rows:
        for tbl, name, timing, event, action in rows:
            print(f"  [{tbl}] {name}: {timing} {event}")
            print(f"    -> {action[:150]}")
    else:
        print("  (sin triggers)")

    print("\n" + "=" * 70)
    print("  6. RLS policies en wallpaper_likes y wallpapers")
    print("=" * 70)
    cur.execute("""
        SELECT tablename, policyname, cmd, qual, with_check
        FROM pg_policies
        WHERE tablename IN ('wallpaper_likes', 'wallpaper_stats',
                            'wallpapers')
        ORDER BY tablename, policyname;
    """)
    rows = cur.fetchall()
    if rows:
        for tbl, pol, cmd, qual, wc in rows:
            print(f"  [{tbl}] {pol} ({cmd})")
            if qual: print(f"    USING: {qual[:200]}")
            if wc:   print(f"    CHECK: {wc[:200]}")
    else:
        print("  (sin policies — probablemente RLS desactivado)")

    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
