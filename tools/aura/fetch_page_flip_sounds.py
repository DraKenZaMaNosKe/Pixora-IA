"""
Sonidos de cambio de pagina para la libreta 3D de Eduardo (Outlier).

Mismo enfoque que fetch_writing_sounds.py pero busca page-flip / page-turn.
Guarda en C:\\Users\\lalo\\Desktop\\sonidos_tmp.
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

QUERIES = [
    "page turn book",
    "page flip paper",
    "book page turning",
    "turning page",
    "paper flip",
    "old book page",
    "magazine page flip",
    "notebook page turn",
]

TOP_PER_QUERY = 3
MIN_DURATION = 0.3   # 300 ms
MAX_DURATION = 3.0   # 3 s


def load_token() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"API Key \(client secret\):\s*(\S+)", text)
    if not m:
        sys.exit("No se encontro Freesound API key en KEYS_LOCAL.md")
    return m.group(1)


def search(token: str, query: str) -> list[dict]:
    params = {
        "query": query,
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

    total = 0
    seen = set()
    summary = []

    for q in QUERIES:
        print(f"\n[buscando] {q!r}")
        results = search(token, q)
        if not results:
            print("  (sin resultados)")
            continue

        slug = "page_" + safe_name(q)
        count = 0
        for sound in results:
            sid = sound["id"]
            if sid in seen:
                continue
            seen.add(sid)

            name = safe_name(sound["name"])
            duration = round(sound["duration"], 2)
            rating = round(sound.get("avg_rating", 0), 2)
            license_short = (
                "CC0" if "Creative Commons 0" in sound["license"] else "CC-BY"
            )
            filename = (
                f"{slug}__id{sid}__{license_short}__{duration}s__{name}.mp3"
            )
            target = DEST / filename
            print(
                f"  -> id={sid} dur={duration}s rating={rating} "
                f"lic={license_short} -> {filename[:80]}"
            )
            if download(token, sound, target):
                total += 1
                count += 1
                summary.append({
                    "id": sid,
                    "dur": duration,
                    "rating": rating,
                    "lic": license_short,
                    "user": sound.get("username", "?"),
                    "file": filename,
                })
            if count >= TOP_PER_QUERY:
                break

    print(f"\nListo. {total} sonidos guardados en {DEST}")
    print("\n--- Resumen ---")
    for s in summary:
        print(
            f"{s['file'][:75]:<75} {s['dur']:>5.2f}s "
            f"{s['lic']:<6} {s['rating']:>4.2f}  {s['user']}"
        )


if __name__ == "__main__":
    main()
