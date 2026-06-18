"""
Auditoria one-shot: compara lo que el admin dashboard muestra vs los datos
REALES en Supabase para detectar fallas de queries / datos perdidos.

Reporta:
- Devices distintos en las ultimas 48h (wallpaper_events + app_events)
- Marca cual es Eduardo vs otros usuarios
- Eventos huerfanos (sin device_id)
- Diferencias entre lo que muestra el admin endpoint /api/users vs SQL directo
"""
import re
import sys
from pathlib import Path
from collections import Counter, defaultdict
import requests

REPO = Path(__file__).resolve().parent.parent.parent
KEYS = REPO / "KEYS_LOCAL.md"
SUPA_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"
ADMIN_URL = "http://127.0.0.1:5757"

# Tu Samsung
EDUARDO_DEVICE = "RF8X903KZ3K"


def load_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key:\s*(\S+)", text)
    if not m:
        sys.exit("No se encontro Service Role Key en KEYS_LOCAL.md")
    return m.group(1)


def sb_get(key: str, path: str) -> list:
    """REST API directa a Supabase."""
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
    }
    r = requests.get(f"{SUPA_URL}/rest/v1/{path}", headers=headers, timeout=30)
    if r.status_code != 200:
        print(f"  ! HTTP {r.status_code} en {path}: {r.text[:200]}")
        return []
    return r.json()


def sb_rpc(key: str, sql: str) -> list:
    """Ejecuta SQL crudo via RPC execute_sql (si existe)."""
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    r = requests.post(
        f"{SUPA_URL}/rest/v1/rpc/execute_sql",
        headers=headers,
        json={"query": sql},
        timeout=30,
    )
    if r.status_code != 200:
        print(f"  ! RPC error: {r.status_code} {r.text[:200]}")
        return []
    return r.json()


def header(s: str) -> None:
    print(f"\n{'=' * 70}\n  {s}\n{'=' * 70}")


def main() -> None:
    key = load_service_key()

    # ── 1. wallpaper_events ─────────────────────────────────────
    header("1. WALLPAPER_EVENTS (ultimas 48h)")
    events = sb_get(
        key,
        "wallpaper_events?select=ts,device_id,user_id,event_type,app_version"
        "&order=ts.desc&limit=2000"
    )
    if not events:
        print("  (sin eventos o falta permiso)")
    else:
        from datetime import datetime, timezone, timedelta
        cutoff = datetime.now(timezone.utc) - timedelta(hours=48)
        recent = [e for e in events if datetime.fromisoformat(
            e["ts"].replace("Z", "+00:00")) > cutoff]

        device_count = Counter(e.get("device_id") or "NULL" for e in recent)
        event_types = Counter(e.get("event_type") for e in recent)
        versions = Counter(e.get("app_version") or "?" for e in recent)

        print(f"  Total eventos 48h: {len(recent)}")
        print(f"  Devices distintos: {len(device_count)}")
        print(f"  Tipos de evento:")
        for et, n in event_types.most_common():
            print(f"    {et:<30} {n:>5}")
        print(f"  Versiones de app que estan reportando:")
        for v, n in versions.most_common(10):
            print(f"    {v:<20} {n:>5}")

        print(f"\n  Top devices por eventos:")
        for did, n in device_count.most_common(15):
            is_me = "<<-- ¡TU SAMSUNG!" if did and EDUARDO_DEVICE in did else ""
            print(f"    {(did or 'NULL'):<50} {n:>5}  {is_me}")

        nulls = device_count.get("NULL", 0)
        if nulls:
            print(f"\n  ⚠ {nulls} eventos SIN device_id (huerfanos)")

    # ── 2. app_events ───────────────────────────────────────────
    header("2. APP_EVENTS (ultimas 48h)")
    aevents = sb_get(
        key,
        "app_events?select=ts,device_id,user_id,event_name,app_version"
        "&order=ts.desc&limit=2000"
    )
    if not aevents:
        print("  (sin eventos o tabla no existe)")
    else:
        from datetime import datetime, timezone, timedelta
        cutoff = datetime.now(timezone.utc) - timedelta(hours=48)
        recent = [e for e in aevents if datetime.fromisoformat(
            e["ts"].replace("Z", "+00:00")) > cutoff]

        device_count = Counter(e.get("device_id") or "NULL" for e in recent)
        event_names = Counter(e.get("event_name") for e in recent)

        print(f"  Total eventos 48h: {len(recent)}")
        print(f"  Devices distintos: {len(device_count)}")
        print(f"  Top event_names:")
        for en, n in event_names.most_common(10):
            print(f"    {en:<35} {n:>5}")

        print(f"\n  Top devices por app_events:")
        for did, n in device_count.most_common(15):
            is_me = "<<-- ¡TU SAMSUNG!" if did and EDUARDO_DEVICE in did else ""
            print(f"    {(did or 'NULL'):<50} {n:>5}  {is_me}")

    # ── 3. Compara con admin endpoint ──────────────────────────
    header("3. COMPARATIVA — Admin endpoint vs SQL directo")
    try:
        # El admin no expone /api/users — el endpoint real es /api/top-users.
        # Antes este script tiraba 404 silencioso aqui (audit 2026-06-16).
        r = requests.get(f"{ADMIN_URL}/api/top-users", timeout=10)
        if r.status_code == 200:
            admin_users = r.json()
            print(f"  Admin /api/top-users devolvio {len(admin_users)} usuarios")
            if admin_users and len(admin_users) > 0:
                print(f"  Primeros 5:")
                for u in admin_users[:5]:
                    print(f"    {u}")
        else:
            print(f"  ⚠ /api/users devolvio HTTP {r.status_code}")
    except Exception as e:
        print(f"  ⚠ Error al consultar admin: {e}")

    # ── 4. Resumen para Eduardo ────────────────────────────────
    header("4. RESUMEN PARA EDUARDO")
    if events and aevents:
        wp_devs = set(e.get("device_id") for e in events if e.get("device_id"))
        ap_devs = set(e.get("device_id") for e in aevents if e.get("device_id"))
        all_devs = wp_devs | ap_devs
        my_devs = {d for d in all_devs if d and EDUARDO_DEVICE in d}
        other_devs = all_devs - my_devs

        print(f"  Devices TOTAL detectados:    {len(all_devs)}")
        print(f"  Tu(s) device(s):             {len(my_devs)}")
        for d in my_devs:
            print(f"    + {d}")
        print(f"  Devices de OTROS usuarios:   {len(other_devs)}")
        for d in sorted(other_devs)[:10]:
            print(f"    + {d}")

        in_wp_only = wp_devs - ap_devs
        in_ap_only = ap_devs - wp_devs
        if in_wp_only:
            print(f"\n  ⚠ {len(in_wp_only)} devices SOLO en wallpaper_events "
                  f"(no aparecen en app_events — posiblemente app vieja):")
            for d in list(in_wp_only)[:5]:
                print(f"    {d}")
        if in_ap_only:
            print(f"\n  ⚠ {len(in_ap_only)} devices SOLO en app_events "
                  f"(no aparecen en wallpaper_events — quiza no aplicaron wp):")
            for d in list(in_ap_only)[:5]:
                print(f"    {d}")


if __name__ == "__main__":
    main()
