# -*- coding: utf-8 -*-
"""Pixora IA — captura diaria de métricas para el histórico estadístico.

Jala de Supabase las métricas que SÍ están en nuestra base y las agrega como
UNA fila (append-only) al backbone en Drive:
  G:/Mi unidad/pixoraIA_admin/claude_compartido/tiktok/stadistics/data/daily/pixora_metrics_daily.csv

Las métricas externas (AdMob, TikTok) NO están en nuestra base — se pasan por
argumento (o se dejan en blanco y se completan a mano en el CSV).

Idempotente: si ya existe la fila de la fecha objetivo, la REEMPLAZA (no duplica).
También escribe un snapshot crudo en data/snapshots/AAAA-MM-DD.json.

Uso:
  python capture_daily.py                        # captura HOY (hora MX)
  python capture_daily.py --date 2026-08-05      # una fecha específica
  python capture_daily.py --admob-revenue 0.99 --admob-impressions 20 \
        --tiktok-spend 60 --tiktok-clicks 500 --tiktok-impressions 8000 \
        --notes "TikTok dia 3"

Excluye los devices de Eduardo (alert_device_exclusions) para que el histórico
sea de usuarios reales.
"""
import argparse
import csv
import json
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # tools/
from apply_migration import connect  # noqa: E402

# México ya no usa horario de verano (CST fijo UTC-6 desde 2022). Offset fijo
# para evitar depender de la base IANA (que Windows no trae). Postgres sí tiene
# su propia tzdb, así que 'AT TIME ZONE America/Mexico_City' en el SQL va bien.
MX = timezone(timedelta(hours=-6))
DRIVE = Path(r"G:/Mi unidad/pixoraIA_admin/claude_compartido/tiktok/stadistics")
CSV_PATH = DRIVE / "data" / "daily" / "pixora_metrics_daily.csv"
SNAP_DIR = DRIVE / "data" / "snapshots"

COLUMNS = [
    "date", "users_total", "users_new", "users_new_authed", "users_new_anon",
    "wallpapers_applied_total", "ads_shown_ours", "ads_attempts_ours",
    "admob_revenue_mxn", "admob_impressions", "admob_ecpm_mxn",
    "subs_active", "subs_mrr_mxn",
    "tiktok_spend_mxn", "tiktok_clicks", "tiktok_impressions", "tiktok_ctr_pct",
    "cac_mxn", "source", "notes",
]


def _one(cur, sql, params=None):
    cur.execute(sql, params or ())
    row = cur.fetchone()
    return row[0] if row else None


def collect_supabase(target_date):
    """Devuelve las métricas derivadas de nuestra base para [target_date] (date local MX)."""
    conn = connect()
    cur = conn.cursor()
    d = target_date.isoformat()

    # Devices de Eduardo a excluir (para que el histórico sea real).
    cur.execute("SELECT device_id FROM alert_device_exclusions")
    excl = tuple(r[0] for r in cur.fetchall()) or ("__none__",)

    # Total de usuarios reales ACUMULADO HASTA esa fecha (sin devices de
    # Eduardo). Usar <= fecha hace que la serie crezca correctamente en el
    # histórico, en vez de estampar el total de hoy en cada fila.
    users_total = _one(cur,
        """SELECT count(*) FROM device_presence
           WHERE device_id <> ALL(%s)
             AND (first_seen_at AT TIME ZONE 'America/Mexico_City')::date <= %s""",
        (list(excl), d))

    # Nuevos ese día (first_seen en fecha local MX).
    users_new = _one(cur,
        """SELECT count(*) FROM device_presence
           WHERE device_id <> ALL(%s)
             AND (first_seen_at AT TIME ZONE 'America/Mexico_City')::date = %s""",
        (list(excl), d))

    # Split login / anónimo entre los nuevos del día.
    users_new_authed = _one(cur,
        """SELECT count(*) FROM device_presence dp
           WHERE dp.device_id <> ALL(%s)
             AND (dp.first_seen_at AT TIME ZONE 'America/Mexico_City')::date = %s
             AND dp.device_id IN (
                 SELECT device_id FROM app_events WHERE user_id IS NOT NULL
                 UNION SELECT device_id FROM wallpaper_events WHERE user_id IS NOT NULL)""",
        (list(excl), d))
    users_new_anon = (users_new or 0) - (users_new_authed or 0)

    # Wallpaper aplicado (acumulado, real).
    wallpapers_applied_total = _one(cur,
        """SELECT count(*) FROM device_presence
           WHERE device_id <> ALL(%s) AND active_wallpaper_id IS NOT NULL""", (list(excl),))

    # Ads propios ese día (mostrados / intentos).
    ads_shown_ours = _one(cur,
        """SELECT count(*) FROM ad_events
           WHERE (ts AT TIME ZONE 'America/Mexico_City')::date = %s AND shown""", (d,))
    ads_attempts_ours = _one(cur,
        """SELECT count(*) FROM ad_events
           WHERE (ts AT TIME ZONE 'America/Mexico_City')::date = %s""", (d,))

    # Suscriptores activos.
    subs_active = _one(cur,
        """SELECT count(*) FROM user_subscriptions
           WHERE status='active' AND (expires_at IS NULL OR expires_at > now())""")

    # MRR (si existe la vista del audit BD; si no, queda None).
    subs_mrr_mxn = None
    try:
        subs_mrr_mxn = _one(cur, "SELECT mrr_mxn_con_derecho FROM v_subs_mrr LIMIT 1")
    except Exception:
        conn.rollback()

    cur.close()
    conn.close()
    return {
        "users_total": users_total or 0,
        "users_new": users_new or 0,
        "users_new_authed": users_new_authed or 0,
        "users_new_anon": users_new_anon,
        "wallpapers_applied_total": wallpapers_applied_total or 0,
        "ads_shown_ours": ads_shown_ours or 0,
        "ads_attempts_ours": ads_attempts_ours or 0,
        "subs_active": subs_active or 0,
        "subs_mrr_mxn": subs_mrr_mxn if subs_mrr_mxn is not None else "",
    }


def upsert_row(row):
    """Agrega o reemplaza la fila de row['date'] en el CSV, manteniendo orden por fecha."""
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    rows = {}
    if CSV_PATH.exists():
        with CSV_PATH.open("r", encoding="utf-8", newline="") as f:
            for r in csv.DictReader(f):
                rows[r["date"]] = r
    rows[row["date"]] = row
    ordered = [rows[k] for k in sorted(rows.keys())]
    with CSV_PATH.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS)
        w.writeheader()
        for r in ordered:
            w.writerow({c: r.get(c, "") for c in COLUMNS})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="AAAA-MM-DD (default: hoy hora MX)")
    ap.add_argument("--admob-revenue", type=float)
    ap.add_argument("--admob-impressions", type=int)
    ap.add_argument("--tiktok-spend", type=float)
    ap.add_argument("--tiktok-clicks", type=int)
    ap.add_argument("--tiktok-impressions", type=int)
    ap.add_argument("--notes", default="")
    ap.add_argument("--dry-run", action="store_true", help="solo imprime, no escribe")
    args = ap.parse_args()

    if args.date:
        target = datetime.strptime(args.date, "%Y-%m-%d").date()
    else:
        target = datetime.now(MX).date()

    sb = collect_supabase(target)

    # Derivados de externos (solo si se pasaron).
    admob_ecpm = ""
    if args.admob_revenue is not None and args.admob_impressions:
        admob_ecpm = round(args.admob_revenue / args.admob_impressions * 1000, 2)
    tiktok_ctr = ""
    if args.tiktok_clicks is not None and args.tiktok_impressions:
        tiktok_ctr = round(args.tiktok_clicks / args.tiktok_impressions * 100, 2)
    cac = ""
    if args.tiktok_spend is not None and sb["users_new"]:
        cac = round(args.tiktok_spend / sb["users_new"], 2)

    row = {
        "date": target.isoformat(),
        **sb,
        "admob_revenue_mxn": args.admob_revenue if args.admob_revenue is not None else "",
        "admob_impressions": args.admob_impressions if args.admob_impressions is not None else "",
        "admob_ecpm_mxn": admob_ecpm,
        "tiktok_spend_mxn": args.tiktok_spend if args.tiktok_spend is not None else "",
        "tiktok_clicks": args.tiktok_clicks if args.tiktok_clicks is not None else "",
        "tiktok_impressions": args.tiktok_impressions if args.tiktok_impressions is not None else "",
        "tiktok_ctr_pct": tiktok_ctr,
        "cac_mxn": cac,
        "source": "auto",
        "notes": args.notes,
    }

    print(f"=== Captura {row['date']} ===")
    for c in COLUMNS:
        print(f"  {c:26} {row.get(c, '')}")

    if args.dry_run:
        print("\n[dry-run] no se escribió nada.")
        return

    upsert_row(row)
    SNAP_DIR.mkdir(parents=True, exist_ok=True)
    snap = SNAP_DIR / f"{row['date']}.json"
    snap.write_text(json.dumps(row, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\n✓ Fila agregada/actualizada en {CSV_PATH.name}")
    print(f"✓ Snapshot en snapshots/{snap.name}")


if __name__ == "__main__":
    main()
