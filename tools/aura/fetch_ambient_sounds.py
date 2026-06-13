"""
Sonidos ambientales para la libreta 3D de Eduardo.
Largos (30-300s) para hacer loop suave mientras toma apuntes.

Categorias: lluvia, cafe, biblioteca, lofi, chimenea, room tone.
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

# Cada query baja UNO solo (los ambient ocupan mucho espacio).
QUERIES = [
    "rain ambience window soft",
    "coffee shop ambience cafe",
    "library quiet ambience",
    "fireplace crackling cozy",
    "rain heavy thunder ambience",
    "study room ambience quiet",
    "lofi rain background",
    "forest ambience birds",
    "writing room ambience",
    "soft wind autumn ambience",
]

TOP_PER_QUERY = 1
MIN_DURATION = 30   # 30 s minimo
MAX_DURATION = 300  # 5 min maximo


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
        "page_size": 8,
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
        r = requests.get(url, params={"token": token}, stream=True, timeout=180)
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
        slug = "ambient_" + safe_name(q)
        count = 0
        for sound in results:
            sid = sound["id"]
            if sid in seen:
                continue
            seen.add(sid)
            name = safe_name(sound["name"])
            duration = round(sound["duration"], 2)
            rating = round(sound.get("avg_rating", 0), 2)
            lic = "CC0" if "Creative Commons 0" in sound["license"] else "CC-BY"
            filename = f"{slug}__id{sid}__{lic}__{duration}s__{name}.mp3"
            target = DEST / filename
            print(
                f"  -> id={sid} dur={duration}s rating={rating} "
                f"lic={lic} -> {filename[:80]}"
            )
            if download(token, sound, target):
                total += 1
                count += 1
                summary.append({
                    "file": filename, "dur": duration, "rating": rating,
                    "lic": lic, "user": sound.get("username", "?"),
                })
            if count >= TOP_PER_QUERY:
                break

    print(f"\nListo. {total} ambientes guardados en {DEST}")
    print("\n--- Resumen ---")
    for s in summary:
        print(
            f"{s['file'][:75]:<75} {s['dur']:>6.1f}s "
            f"{s['lic']:<6} {s['rating']:>4.2f}  {s['user']}"
        )


if __name__ == "__main__":
    main()
