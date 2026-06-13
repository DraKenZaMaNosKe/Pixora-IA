"""
One-shot helper para la libreta 3D de Eduardo (Outlier).

Busca en Freesound varios sonidos cortos de pluma/pluma fuente/lapiz escribiendo
sobre papel, filtra por licencia libre (CC0 + CC-BY) y duración corta, y baja
los top resultados a C:\\Users\\lalo\\Desktop\\sonidos_tmp para que Eduardo
escoja el que mejor le acomode al efecto de tecleo.

Reusa el cargador de token de freesound_fetch.py.
"""
import re
import sys
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
KEYS = REPO / "KEYS_LOCAL.md"

DEST = Path(r"C:\Users\lalo\Desktop\sonidos_tmp")
API = "https://freesound.org/apiv2"

# Queries pensadas para una libreta donde tecleas y la pluma escribe.
# Mezcla: pluma fuente (sonido elegante), lápiz (más áspero), trazos cortos.
QUERIES = [
    "fountain pen writing paper",
    "pen writing paper close",
    "ink pen scribble",
    "pencil writing paper",
    "quill writing parchment",
    "marker writing paper",
    "ballpoint pen writing",
    "pen scratch paper",
]

TOP_PER_QUERY = 3   # bajar los 3 mejores por query
MIN_DURATION = 0.2  # 200 ms — útil para 1 letra
MAX_DURATION = 4.0  # 4 s — útil como loop continuo


def load_token() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"API Key \(client secret\):\s*(\S+)", text)
    if not m:
        sys.exit("No se encontró Freesound API key en KEYS_LOCAL.md")
    return m.group(1)


def search(token: str, query: str) -> list[dict]:
    """Top resultados CC0/CC-BY, cortos, mejor rateados."""
    params = {
        "query": query,
        # Licencias libres — CC0 (sin atribución) Y CC Attribution (con
        # atribución; aceptable para uso personal en libreta privada).
        "filter": (
            f'(license:"Creative Commons 0" OR license:"Attribution") '
            f'duration:[{MIN_DURATION} TO {MAX_DURATION}]'
        ),
        "sort": "rating_desc",
        "fields": (
            "id,name,duration,license,download,previews,"
            "username,avg_rating,num_ratings"
        ),
        "page_size": 10,
        "token": token,
    }
    r = requests.get(f"{API}/search/text/", params=params, timeout=30)
    if r.status_code != 200:
        print(f"  ! HTTP {r.status_code}: {r.text[:200]}")
        return []
    return r.json().get("results", [])


def safe_name(s: str) -> str:
    """Sanitiza para usar como filename Windows."""
    s = re.sub(r"[^\w\s-]", "", s).strip()
    s = re.sub(r"\s+", "_", s)
    return s[:60]


def download(token: str, sound: dict, dest: Path) -> bool:
    previews = sound.get("previews") or {}
    url = previews.get("preview-hq-mp3") or previews.get("preview-lq-mp3")
    if not url:
        return False
    try:
        r = requests.get(url, params={"token": token}, stream=True, timeout=60)
        r.raise_for_status()
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "wb") as f:
            for chunk in r.iter_content(8192):
                f.write(chunk)
        return True
    except Exception as e:
        print(f"  ! download failed: {e}")
        return False


def main() -> None:
    token = load_token()
    DEST.mkdir(parents=True, exist_ok=True)

    total_downloaded = 0
    seen_ids = set()
    summary = []

    for q in QUERIES:
        print(f"\n[buscando] {q!r}")
        results = search(token, q)
        if not results:
            print("  (sin resultados)")
            continue

        slug = safe_name(q)
        count_for_query = 0

        for sound in results:
            sid = sound["id"]
            if sid in seen_ids:
                continue  # duplicado entre queries
            seen_ids.add(sid)

            name = safe_name(sound["name"])
            duration = round(sound["duration"], 2)
            rating = round(sound.get("avg_rating", 0), 2)
            license_short = "CC0" if "Creative Commons 0" in sound["license"] else "CC-BY"

            filename = (
                f"{slug}__id{sid}__{license_short}__{duration}s__{name}.mp3"
            )
            target = DEST / filename

            print(
                f"  -> id={sid} dur={duration}s rating={rating} "
                f"lic={license_short} -> {filename[:80]}"
            )

            if download(token, sound, target):
                total_downloaded += 1
                count_for_query += 1
                summary.append({
                    "query": q,
                    "id": sid,
                    "duration": duration,
                    "rating": rating,
                    "license": license_short,
                    "name": sound["name"],
                    "user": sound.get("username", "?"),
                    "file": filename,
                })

            if count_for_query >= TOP_PER_QUERY:
                break

    print(f"\nListo. {total_downloaded} sonidos guardados en {DEST}")
    print("\n--- Resumen ---")
    print(f"{'archivo':<70} {'dur':>6}  {'lic':<6} rating  user")
    for s in summary:
        print(
            f"{s['file'][:70]:<70} {s['duration']:>5.2f}s "
            f"{s['license']:<6} {s['rating']:>5.2f}  {s['user']}"
        )


if __name__ == "__main__":
    main()
