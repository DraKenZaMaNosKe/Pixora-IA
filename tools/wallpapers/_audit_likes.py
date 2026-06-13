"""
Auditoria del sistema de likes: verifica que la infraestructura existe.

Chequea:
1. ¿Existe la tabla wallpaper_likes?
2. ¿Existe la funcion RPC increment_likes / decrement_likes?
3. ¿La tabla wallpapers tiene columna likes_count?
4. ¿Hay likes recientes registrados?
"""
import re
import sys
from pathlib import Path
import requests

REPO = Path(__file__).resolve().parent.parent.parent
KEYS = REPO / "KEYS_LOCAL.md"
SUPA_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"


def load_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key:\s*(\S+)", text)
    return m.group(1) if m else sys.exit("falta service key")


def sb(key: str, path: str):
    """Devuelve (status, parsed_json o text)."""
    h = {"apikey": key, "Authorization": f"Bearer {key}"}
    r = requests.get(f"{SUPA_URL}/rest/v1/{path}", headers=h, timeout=20)
    try:
        return r.status_code, r.json()
    except Exception:
        return r.status_code, r.text[:500]


def sb_post(key: str, path: str, body: dict) -> tuple[int, str]:
    h = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    r = requests.post(
        f"{SUPA_URL}/rest/v1/{path}", headers=h, json=body, timeout=20
    )
    return r.status_code, r.text[:500]


def h(s): print(f"\n{'=' * 60}\n  {s}\n{'=' * 60}")


def main():
    key = load_key()

    # 1. Tabla wallpaper_likes
    h("1. Tabla wallpaper_likes")
    code, body = sb(key, "wallpaper_likes?select=*&limit=5")
    if code == 200:
        rows = body
        print(f"  OK existe. Sample: {rows[:300]}")
    elif code == 404:
        print(f"  XX TABLA NO EXISTE (404). Body: {body[:200]}")
    else:
        print(f"  ? HTTP {code}: {body[:200]}")

    # 2. Conteo total de likes
    h("2. Total de likes registrados")
    code, body = sb(key, "wallpaper_likes?select=wallpaper_id")
    if code == 200:
        try:
            rows = body if isinstance(body, list) else []
            print(f"  Total likes: {len(rows)}")
            if rows:
                from collections import Counter
                top = Counter(r["wallpaper_id"] for r in rows).most_common(5)
                print(f"  Top 5 wallpapers mas likeados:")
                for wid, n in top:
                    print(f"    {wid:<40} {n}")
        except Exception as e:
            print(f"  Parse error: {e}")
    else:
        print(f"  ? HTTP {code}")

    # 3. Likes por device en ultimas 24h
    h("3. Likes recientes (ultimas 24h)")
    code, body = sb(
        key,
        "wallpaper_likes?select=device_id,wallpaper_id,created_at"
        "&order=created_at.desc&limit=20"
    )
    if code == 200:
        rows = body if isinstance(body, list) else []
        if rows:
            print(f"  ultimos {len(rows)} likes:")
            for r in rows[:10]:
                print(f"    {r.get('created_at','?')[:19]}  "
                      f"dev={r.get('device_id','?')[:20]:<20}  "
                      f"wp={r.get('wallpaper_id','?')[:30]}")
        else:
            print("  (sin likes registrados)")
    else:
        print(f"  ? HTTP {code}")

    # 4. Columna likes_count en tabla wallpapers
    h("4. Columna likes_count en tabla wallpapers")
    code, body = sb(
        key, "wallpapers?select=id,likes_count&order=likes_count.desc&limit=5"
    )
    if code == 200:
        rows = body if isinstance(body, list) else []
        print(f"  OK columna existe. Top 5 por likes_count:")
        for r in rows:
            print(f"    {r.get('id','?'):<40} likes={r.get('likes_count', 0)}")
    else:
        body_str = str(body).lower()
        if "column" in body_str and "does not exist" in body_str:
            print(f"  XX COLUMNA likes_count NO EXISTE EN tabla wallpapers")
        print(f"  HTTP {code} body: {body}")

    # 5. Probar el RPC increment_likes (con un wallpaper de prueba)
    h("5. RPC increment_likes existe?")
    # Usamos un ID dummy para ver si responde error de "function not found"
    # vs "row not found" (que indicaria que SI existe la function)
    code, body = sb_post(
        key, "rpc/increment_likes",
        {"p_wallpaper_id": "test_dummy_id_for_probe"}
    )
    if code == 404:
        print(f"  XX RPC NO EXISTE (404). Esto significa que toggleLike "
              f"falla silenciosamente porque el try/catch atrapa el error.")
        print(f"  Body: {body[:300]}")
    elif code in (200, 204):
        print(f"  OK RPC existe (responde {code})")
    elif code == 400:
        # 400 puede ser "no rows affected" — la funcion EXISTE pero el id no match
        print(f"  OK probablemente existe (HTTP 400 = el wp_id no match): "
              f"{body[:200]}")
    else:
        print(f"  ? HTTP {code}: {body[:300]}")

    # 6. Conclusion
    h("6. CONCLUSION")
    print("  Si '1' dice TABLA NO EXISTE -> hay que correr migracion.")
    print("  Si '4' dice COLUMNA NO EXISTE -> hay que correr migracion.")
    print("  Si '5' dice RPC NO EXISTE -> hay que crear las functions.")
    print("  Si todo OK arriba -> el bug es de UI (stream no propaga).")


if __name__ == "__main__":
    main()
