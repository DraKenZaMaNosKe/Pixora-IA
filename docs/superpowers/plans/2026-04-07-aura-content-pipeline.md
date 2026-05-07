# AURA Content Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a fully-curated wellness audio catalog (9 Solfeggio frequencies + 15 nature sounds) hosted in Supabase Storage with bilingual metadata, ready for the Flutter app to consume.

**Architecture:** Local audio generation/curation pipeline → Supabase Storage bucket `aura-audio` → Postgres table `aura_tracks` with bilingual descriptions and chakra/category metadata. No Flutter code in this plan; output is HTTPS URLs + DB rows that Plan 2 (App Integration) consumes.

**Tech Stack:** ffmpeg 8 (sine generation, fade, loudness normalization), Python 3 (Freesound API client, Supabase upload via REST), Freesound API v2 (CC0/CC-BY nature sounds), Supabase Storage + Postgres.

---

## File Structure

- `tools/aura/` — pipeline scripts (new dir, gitignored except scripts)
  - `gen_frequencies.sh` — ffmpeg one-shot to generate all 9 Solfeggio MP3s
  - `freesound_fetch.py` — search + download nature sounds via API
  - `process_nature.py` — normalize loudness, trim silence, crossfade-loop
  - `upload_supabase.py` — upload all assets + insert DB rows
  - `tracks_manifest.json` — single source of truth for all 24 tracks (id, hz, category, file, titles, descriptions ES/EN)
- `tools/aura/out/` — generated audio (gitignored)
- `tools/aura/.gitignore` — ignore `out/` and any downloaded raw audio
- Supabase: bucket `aura-audio` (public read), table `aura_tracks`

---

## Task 1: Workspace & manifest scaffold

**Files:**
- Create: `tools/aura/.gitignore`
- Create: `tools/aura/tracks_manifest.json`
- Create: `tools/aura/README.md`

- [ ] **Step 1: Create directory and gitignore**

```bash
mkdir -p tools/aura/out/frequencies tools/aura/out/nature tools/aura/raw
```

Create `tools/aura/.gitignore`:
```
out/
raw/
*.mp3
*.wav
__pycache__/
.venv/
```

- [ ] **Step 2: Create the manifest as the single source of truth**

Create `tools/aura/tracks_manifest.json` with all 24 tracks. Use this exact structure (the upload script depends on these field names):

```json
{
  "frequencies": [
    {
      "id": "freq_174",
      "hz": 174,
      "name_en": "Foundation",
      "name_es": "Fundación",
      "chakra": null,
      "color_hex": "#6B4F8F",
      "duration_min": 15,
      "file": "out/frequencies/174hz_foundation.mp3",
      "desc_en": "The lowest Solfeggio tone, traditionally associated with a sense of safety, security, and pain relief. Often used as a grounding base before deeper meditation.",
      "desc_es": "El tono Solfeggio más bajo, tradicionalmente asociado con una sensación de seguridad, protección y alivio del dolor. Se usa como base para enraizarse antes de meditaciones profundas."
    },
    {
      "id": "freq_285",
      "hz": 285,
      "name_en": "Quantum Cognition",
      "name_es": "Cognición Cuántica",
      "chakra": null,
      "color_hex": "#7C5BA6",
      "duration_min": 15,
      "file": "out/frequencies/285hz_quantum.mp3",
      "desc_en": "Said to support the body's natural healing field — popular in practices focused on tissue regeneration and recovery.",
      "desc_es": "Asociada al campo natural de sanación del cuerpo — popular en prácticas enfocadas en regeneración de tejidos y recuperación."
    },
    {
      "id": "freq_396",
      "hz": 396,
      "name_en": "Liberation",
      "name_es": "Liberación",
      "chakra": "root",
      "color_hex": "#C0392B",
      "duration_min": 15,
      "file": "out/frequencies/396hz_liberation.mp3",
      "desc_en": "Linked to the root chakra (Muladhara). Traditionally used to release fear and guilt, helping you feel grounded and present.",
      "desc_es": "Vinculada al chacra raíz (Muladhara). Tradicionalmente usada para liberar miedo y culpa, ayudándote a sentirte enraizado y presente."
    },
    {
      "id": "freq_417",
      "hz": 417,
      "name_en": "Transmutation",
      "name_es": "Transmutación",
      "chakra": "sacral",
      "color_hex": "#E67E22",
      "duration_min": 15,
      "file": "out/frequencies/417hz_transmutation.mp3",
      "desc_en": "Associated with the sacral chakra (Svadhisthana). Used to facilitate change, break old patterns, and welcome new beginnings.",
      "desc_es": "Asociada al chacra sacro (Svadhisthana). Se usa para facilitar el cambio, romper patrones antiguos y dar bienvenida a nuevos comienzos."
    },
    {
      "id": "freq_528",
      "hz": 528,
      "name_en": "Miracle",
      "name_es": "Milagro",
      "chakra": "solar_plexus",
      "color_hex": "#F1C40F",
      "duration_min": 15,
      "file": "out/frequencies/528hz_miracle.mp3",
      "desc_en": "The most popular Solfeggio frequency, known as the 'Love Frequency'. Linked to the solar plexus chakra (Manipura) and widely used in meditation for inner peace and self-confidence.",
      "desc_es": "La frecuencia Solfeggio más popular, conocida como la 'Frecuencia del Amor'. Vinculada al chacra del plexo solar (Manipura) y muy usada en meditación para la paz interior y la confianza personal."
    },
    {
      "id": "freq_639",
      "hz": 639,
      "name_en": "Connection",
      "name_es": "Conexión",
      "chakra": "heart",
      "color_hex": "#27AE60",
      "duration_min": 15,
      "file": "out/frequencies/639hz_connection.mp3",
      "desc_en": "Tied to the heart chakra (Anahata). Used to nurture harmony in relationships, communication, and self-love.",
      "desc_es": "Ligada al chacra del corazón (Anahata). Se usa para nutrir la armonía en las relaciones, la comunicación y el amor propio."
    },
    {
      "id": "freq_741",
      "hz": 741,
      "name_en": "Expression",
      "name_es": "Expresión",
      "chakra": "throat",
      "color_hex": "#3498DB",
      "duration_min": 15,
      "file": "out/frequencies/741hz_expression.mp3",
      "desc_en": "Associated with the throat chakra (Vishuddha). Traditionally used to support clear self-expression, intuition, and creative problem-solving.",
      "desc_es": "Asociada al chacra de la garganta (Vishuddha). Tradicionalmente usada para apoyar la auto-expresión clara, la intuición y la resolución creativa de problemas."
    },
    {
      "id": "freq_852",
      "hz": 852,
      "name_en": "Intuition",
      "name_es": "Intuición",
      "chakra": "third_eye",
      "color_hex": "#5B2C6F",
      "duration_min": 15,
      "file": "out/frequencies/852hz_intuition.mp3",
      "desc_en": "Linked to the third-eye chakra (Ajna). Used in practices that aim to awaken intuition and inner vision.",
      "desc_es": "Vinculada al chacra del tercer ojo (Ajna). Se usa en prácticas que buscan despertar la intuición y la visión interior."
    },
    {
      "id": "freq_963",
      "hz": 963,
      "name_en": "Divine Consciousness",
      "name_es": "Consciencia Divina",
      "chakra": "crown",
      "color_hex": "#9B59B6",
      "duration_min": 15,
      "file": "out/frequencies/963hz_divine.mp3",
      "desc_en": "The highest Solfeggio tone, tied to the crown chakra (Sahasrara). Used in meditations focused on spiritual awakening and a sense of unity.",
      "desc_es": "El tono Solfeggio más alto, ligado al chacra corona (Sahasrara). Se usa en meditaciones enfocadas en el despertar espiritual y la sensación de unidad."
    }
  ],
  "nature": [
    { "id": "nat_rain_soft",     "name_en": "Soft Rain",        "name_es": "Lluvia Suave",         "icon": "rain",        "freesound_query": "soft rain ambient",            "license": "CC0", "duration_min": 10, "file": "out/nature/rain_soft.mp3",     "desc_en": "Gentle, steady rainfall — the classic sleep companion.", "desc_es": "Lluvia suave y constante — la compañera clásica para dormir." },
    { "id": "nat_rain_thunder",  "name_en": "Rain & Thunder",   "name_es": "Lluvia y Truenos",     "icon": "storm",       "freesound_query": "rain thunder distant",         "license": "CC0", "duration_min": 10, "file": "out/nature/rain_thunder.mp3",  "desc_en": "Rain with distant rolling thunder — cozy and grounding.", "desc_es": "Lluvia con truenos lejanos — acogedor y enraizante." },
    { "id": "nat_ocean",         "name_en": "Ocean Waves",      "name_es": "Olas del Mar",         "icon": "wave",        "freesound_query": "ocean waves beach calm",       "license": "CC0", "duration_min": 10, "file": "out/nature/ocean.mp3",         "desc_en": "Slow ocean waves washing over a beach.",                 "desc_es": "Olas lentas del océano lavando una playa." },
    { "id": "nat_river",         "name_en": "River Stream",     "name_es": "Río",                  "icon": "river",       "freesound_query": "river stream flowing",         "license": "CC0", "duration_min": 10, "file": "out/nature/river.mp3",         "desc_en": "A clear stream flowing over stones.",                    "desc_es": "Un arroyo claro fluyendo sobre piedras." },
    { "id": "nat_waterfall",     "name_en": "Waterfall",        "name_es": "Cascada",              "icon": "waterfall",   "freesound_query": "waterfall ambient",            "license": "CC0", "duration_min": 10, "file": "out/nature/waterfall.mp3",     "desc_en": "The roar of a forest waterfall.",                        "desc_es": "El rugido de una cascada en el bosque." },
    { "id": "nat_fireplace",     "name_en": "Fireplace",        "name_es": "Chimenea",             "icon": "fire",        "freesound_query": "fireplace crackling",          "license": "CC0", "duration_min": 10, "file": "out/nature/fireplace.mp3",     "desc_en": "Crackling fire on a winter night.",                      "desc_es": "Fuego crepitando en una noche de invierno." },
    { "id": "nat_forest_birds",  "name_en": "Forest Birds",     "name_es": "Bosque y Pájaros",     "icon": "forest",      "freesound_query": "forest birds ambient morning",  "license": "CC0", "duration_min": 10, "file": "out/nature/forest_birds.mp3",  "desc_en": "Birdsong in a peaceful forest at dawn.",                 "desc_es": "Canto de pájaros en un bosque tranquilo al amanecer." },
    { "id": "nat_wind_trees",    "name_en": "Wind in Trees",    "name_es": "Viento en Árboles",    "icon": "wind",        "freesound_query": "wind in trees leaves",         "license": "CC0", "duration_min": 10, "file": "out/nature/wind_trees.mp3",    "desc_en": "Wind moving through leaves and branches.",               "desc_es": "Viento moviéndose entre hojas y ramas." },
    { "id": "nat_storm",         "name_en": "Distant Storm",    "name_es": "Tormenta Lejana",      "icon": "lightning",   "freesound_query": "distant thunderstorm rumble",  "license": "CC0", "duration_min": 10, "file": "out/nature/storm.mp3",         "desc_en": "A storm rolling across the horizon.",                    "desc_es": "Una tormenta rodando por el horizonte." },
    { "id": "nat_crickets",      "name_en": "Night Crickets",   "name_es": "Grillos Nocturnos",    "icon": "moon",        "freesound_query": "crickets night ambient",       "license": "CC0", "duration_min": 10, "file": "out/nature/crickets.mp3",      "desc_en": "A summer night chorus of crickets.",                     "desc_es": "Coro de grillos en una noche de verano." },
    { "id": "nat_cafe",          "name_en": "Coffee Shop",      "name_es": "Cafetería",            "icon": "coffee",      "freesound_query": "coffee shop ambience",         "license": "CC0", "duration_min": 10, "file": "out/nature/cafe.mp3",          "desc_en": "Soft chatter and clinking cups for focus.",              "desc_es": "Murmullo suave y tazas chocando para concentrarse." },
    { "id": "nat_white_noise",   "name_en": "White Noise",      "name_es": "Ruido Blanco",         "icon": "static",      "freesound_query": null,                           "license": "GENERATED", "duration_min": 15, "file": "out/nature/white_noise.mp3", "desc_en": "Pure white noise — masks distractions and supports deep sleep.", "desc_es": "Ruido blanco puro — enmascara distracciones y apoya el sueño profundo." },
    { "id": "nat_brown_noise",   "name_en": "Brown Noise",      "name_es": "Ruido Marrón",         "icon": "static",      "freesound_query": null,                           "license": "GENERATED", "duration_min": 15, "file": "out/nature/brown_noise.mp3", "desc_en": "Deeper than white noise — softer on the ears, popular for focus.", "desc_es": "Más profundo que el ruido blanco — más suave al oído, popular para concentrarse." },
    { "id": "nat_singing_bowl",  "name_en": "Tibetan Bowl",     "name_es": "Cuenco Tibetano",      "icon": "bowl",        "freesound_query": "tibetan singing bowl",         "license": "CC0", "duration_min": 10, "file": "out/nature/singing_bowl.mp3",  "desc_en": "Tibetan singing bowl — a traditional meditation aid.",   "desc_es": "Cuenco tibetano — auxiliar tradicional de meditación." },
    { "id": "nat_wind_chimes",   "name_en": "Wind Chimes",      "name_es": "Campanas de Viento",   "icon": "bell",        "freesound_query": "wind chimes gentle",           "license": "CC0", "duration_min": 10, "file": "out/nature/wind_chimes.mp3",   "desc_en": "Soft wind chimes drifting on a breeze.",                 "desc_es": "Campanas de viento suaves meciéndose con la brisa." }
  ]
}
```

- [ ] **Step 3: Commit scaffold**

```bash
git add tools/aura/.gitignore tools/aura/tracks_manifest.json tools/aura/README.md 2>/dev/null || true
git add tools/aura/.gitignore tools/aura/tracks_manifest.json
git commit -m "feat(aura): add content pipeline scaffold and manifest"
```

---

## Task 2: Generate the 9 Solfeggio frequencies (15 min each)

**Files:**
- Create: `tools/aura/gen_frequencies.sh`

- [ ] **Step 1: Write the generator script**

Create `tools/aura/gen_frequencies.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out/frequencies
DUR=900       # 15 minutes
FADE=5        # 5 second fade
SR=48000
BR=192k

declare -a TRACKS=(
  "174:foundation"
  "285:quantum"
  "396:liberation"
  "417:transmutation"
  "528:miracle"
  "639:connection"
  "741:expression"
  "852:intuition"
  "963:divine"
)

for pair in "${TRACKS[@]}"; do
  hz="${pair%%:*}"
  name="${pair##*:}"
  out="out/frequencies/${hz}hz_${name}.mp3"
  echo ">> ${hz}Hz -> ${out}"
  ffmpeg -y \
    -f lavfi -i "sine=frequency=${hz}:sample_rate=${SR}:duration=${DUR}" \
    -af "afade=t=in:st=0:d=${FADE},afade=t=out:st=$((DUR-FADE)):d=${FADE},volume=0.5,loudnorm=I=-18:TP=-2:LRA=7" \
    -c:a libmp3lame -b:a ${BR} \
    "${out}" -loglevel error
done
echo "Done. 9 frequencies generated."
```

- [ ] **Step 2: Run the script**

```bash
chmod +x tools/aura/gen_frequencies.sh
bash tools/aura/gen_frequencies.sh
ls -lh tools/aura/out/frequencies/
```

Expected: 9 MP3 files, each ~21 MB.

- [ ] **Step 3: Smoke-listen verification**

Open one file (e.g. `528hz_miracle.mp3`) in a media player. Verify:
- Length is 15:00
- Fade-in present (no click at start)
- Steady tone, no glitches

- [ ] **Step 4: Commit the script (not the audio)**

```bash
git add tools/aura/gen_frequencies.sh
git commit -m "feat(aura): add Solfeggio frequency generator (15min, loudness-normalized)"
```

---

## Task 3: Generate white & brown noise locally

**Files:**
- Modify: `tools/aura/gen_frequencies.sh` — extend or create separate script
- Create: `tools/aura/gen_noise.sh`

- [ ] **Step 1: Write the noise generator**

Create `tools/aura/gen_noise.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out/nature
DUR=900
SR=48000
BR=192k

# White noise
ffmpeg -y -f lavfi -i "anoisesrc=color=white:sample_rate=${SR}:duration=${DUR}:amplitude=0.3" \
  -af "afade=t=in:st=0:d=3,afade=t=out:st=$((DUR-3)):d=3,loudnorm=I=-18:TP=-2:LRA=7" \
  -c:a libmp3lame -b:a ${BR} out/nature/white_noise.mp3 -loglevel error
echo ">> white_noise.mp3"

# Brown noise
ffmpeg -y -f lavfi -i "anoisesrc=color=brown:sample_rate=${SR}:duration=${DUR}:amplitude=0.5" \
  -af "afade=t=in:st=0:d=3,afade=t=out:st=$((DUR-3)):d=3,loudnorm=I=-18:TP=-2:LRA=7" \
  -c:a libmp3lame -b:a ${BR} out/nature/brown_noise.mp3 -loglevel error
echo ">> brown_noise.mp3"
```

- [ ] **Step 2: Run and verify**

```bash
bash tools/aura/gen_noise.sh
ls -lh tools/aura/out/nature/
```

Expected: `white_noise.mp3` and `brown_noise.mp3`, each ~21 MB.

- [ ] **Step 3: Commit**

```bash
git add tools/aura/gen_noise.sh
git commit -m "feat(aura): add white/brown noise generator"
```

---

## Task 4: Freesound API client — search & download nature sounds

**Files:**
- Create: `tools/aura/freesound_fetch.py`
- Create: `tools/aura/requirements.txt`

- [ ] **Step 1: Add Python deps**

Create `tools/aura/requirements.txt`:
```
requests>=2.31
python-dotenv>=1.0
```

Install:
```bash
cd tools/aura && python -m venv .venv && .venv/Scripts/pip install -r requirements.txt
```

(On bash-for-Windows, the activation path is `.venv/Scripts/python.exe` — call the venv python directly to avoid shell-activation issues.)

- [ ] **Step 2: Write the fetcher**

Create `tools/aura/freesound_fetch.py`:
```python
"""
Search Freesound for each nature track in the manifest, pick the best CC0 result,
download the original file to tools/aura/raw/.

Reads the API token from KEYS_LOCAL.md (line starting with 'API Key (client secret):').
"""
import json
import re
import sys
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
MANIFEST = ROOT / "tracks_manifest.json"
RAW_DIR = ROOT / "raw"
KEYS = REPO / "KEYS_LOCAL.md"

API = "https://freesound.org/apiv2"

def load_token() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"API Key \(client secret\):\s*(\S+)", text)
    if not m:
        sys.exit("Could not find Freesound API key in KEYS_LOCAL.md")
    return m.group(1)

def search(token: str, query: str) -> dict | None:
    """Return the highest-rated CC0 result long enough to be useful."""
    params = {
        "query": query,
        "filter": 'license:"Creative Commons 0" duration:[60 TO 600]',
        "sort": "rating_desc",
        "fields": "id,name,duration,license,download,previews,username,avg_rating",
        "page_size": 5,
        "token": token,
    }
    r = requests.get(f"{API}/search/text/", params=params, timeout=30)
    r.raise_for_status()
    results = r.json().get("results", [])
    return results[0] if results else None

def download_preview(token: str, sound: dict, dest: Path) -> None:
    """Use the high-quality preview MP3 (no OAuth needed, unlike 'download')."""
    url = sound["previews"]["preview-hq-mp3"]
    r = requests.get(url, params={"token": token}, stream=True, timeout=120)
    r.raise_for_status()
    dest.parent.mkdir(parents=True, exist_ok=True)
    with open(dest, "wb") as f:
        for chunk in r.iter_content(8192):
            f.write(chunk)

def main() -> None:
    token = load_token()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    log = []
    for t in manifest["nature"]:
        if t["license"] == "GENERATED":
            print(f"-- skip {t['id']} (locally generated)")
            continue
        q = t["freesound_query"]
        print(f">> search '{q}' for {t['id']}")
        hit = search(token, q)
        if not hit:
            print(f"   NO RESULT — adjust query in manifest")
            log.append({"id": t["id"], "status": "no_result", "query": q})
            continue
        dest = RAW_DIR / f"{t['id']}.mp3"
        download_preview(token, hit, dest)
        print(f"   downloaded id={hit['id']} '{hit['name']}' by {hit['username']} -> {dest.name}")
        log.append({
            "id": t["id"],
            "status": "ok",
            "freesound_id": hit["id"],
            "freesound_name": hit["name"],
            "freesound_user": hit["username"],
            "freesound_rating": hit["avg_rating"],
            "duration": hit["duration"],
        })
    (ROOT / "fetch_log.json").write_text(json.dumps(log, indent=2))
    print(f"\nDone. Log: {ROOT/'fetch_log.json'}")

if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run the fetcher**

```bash
cd tools/aura && .venv/Scripts/python freesound_fetch.py
ls raw/
```

Expected: 13 MP3s in `raw/` (15 nature tracks − 2 generated locally). Any `no_result` entries get manual query tweaks in the manifest, then re-run.

- [ ] **Step 4: Manual smoke-listen**

Listen to each downloaded raw file. If any sounds bad (talking, music, low quality), edit `freesound_query` in the manifest and re-run for just that one (the script overwrites by `id`).

- [ ] **Step 5: Commit script (not audio)**

```bash
git add tools/aura/freesound_fetch.py tools/aura/requirements.txt
git commit -m "feat(aura): add Freesound API fetcher for CC0 nature sounds"
```

---

## Task 5: Process nature sounds — normalize, trim, loop-friendly

**Files:**
- Create: `tools/aura/process_nature.py`

- [ ] **Step 1: Write the processor**

Create `tools/aura/process_nature.py`:
```python
"""
For each downloaded raw nature sound:
  1. Trim leading/trailing silence
  2. Normalize loudness to -18 LUFS (matches frequencies)
  3. Loop/extend to 10 minutes with a short crossfade so it can play seamlessly
  4. Encode as 192k MP3 to out/nature/<id>.mp3
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "tracks_manifest.json"
RAW = ROOT / "raw"
OUT = ROOT / "out" / "nature"

TARGET_SECONDS = 600  # 10 min

def ffprobe_duration(p: Path) -> float:
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nokey=1:noprint_wrappers=1", str(p)],
        capture_output=True, text=True, check=True)
    return float(r.stdout.strip())

def process(track: dict) -> None:
    raw = RAW / f"{track['id']}.mp3"
    out = ROOT / track["file"]
    out.parent.mkdir(parents=True, exist_ok=True)
    if not raw.exists():
        print(f"!! missing raw for {track['id']}")
        return

    dur = ffprobe_duration(raw)
    # How many full loops do we need to reach TARGET_SECONDS?
    loops = max(1, int(TARGET_SECONDS // dur) + 1)

    # Filter graph:
    #   silenceremove (trim leading/trailing) -> aloop -> atrim to target -> fades -> loudnorm
    af = (
        "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1:"
        "stop_periods=-1:stop_threshold=-50dB:stop_silence=0.5,"
        f"aloop=loop={loops}:size=2e9,"
        f"atrim=duration={TARGET_SECONDS},"
        "afade=t=in:st=0:d=3,"
        f"afade=t=out:st={TARGET_SECONDS-5}:d=5,"
        "loudnorm=I=-18:TP=-2:LRA=7"
    )

    cmd = [
        "ffmpeg", "-y", "-i", str(raw),
        "-af", af,
        "-c:a", "libmp3lame", "-b:a", "192k",
        str(out), "-loglevel", "error",
    ]
    print(f">> {track['id']}  raw={dur:.1f}s loops={loops} -> {out.name}")
    subprocess.run(cmd, check=True)

def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for t in manifest["nature"]:
        if t["license"] == "GENERATED":
            continue
        process(t)
    print("Done.")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the processor**

```bash
cd tools/aura && .venv/Scripts/python process_nature.py
ls -lh out/nature/
```

Expected: 13 processed MP3s in `out/nature/`, each ~14 MB (10 min at 192k).

- [ ] **Step 3: Smoke-listen 3 random tracks**

Verify: clean fade-in, no abrupt loop click in the middle, consistent volume relative to a frequency track played back-to-back.

- [ ] **Step 4: Commit**

```bash
git add tools/aura/process_nature.py
git commit -m "feat(aura): add nature sound processor (trim, loop, loudnorm)"
```

---

## Task 6: Create the Supabase bucket and table

**Files:**
- Create: `tools/aura/supabase_schema.sql`

- [ ] **Step 1: Write the SQL**

Create `tools/aura/supabase_schema.sql`:
```sql
-- AURA wellness audio catalog
-- Run via Supabase SQL editor against project vzuwvsmlyigjtsearxym

-- 1. Bucket (public read)
insert into storage.buckets (id, name, public)
values ('aura-audio', 'aura-audio', true)
on conflict (id) do nothing;

-- Public read policy for the bucket
create policy if not exists "aura-audio public read"
  on storage.objects for select
  using ( bucket_id = 'aura-audio' );

-- 2. Catalog table
create table if not exists public.aura_tracks (
  id              text primary key,           -- e.g. 'freq_528', 'nat_rain_soft'
  category        text not null check (category in ('frequency','nature')),
  hz              integer,                    -- only for frequencies
  chakra          text,                       -- 'root','sacral','solar_plexus','heart','throat','third_eye','crown' or null
  color_hex       text,
  icon            text,                       -- only for nature
  name_en         text not null,
  name_es         text not null,
  desc_en         text not null,
  desc_es         text not null,
  duration_sec    integer not null,
  file_path       text not null,              -- path inside the bucket
  audio_url       text not null,              -- public URL
  license         text not null default 'CC0',
  freesound_id    bigint,
  freesound_user  text,
  sort_order      integer not null default 0,
  created_at      timestamptz not null default now()
);

create index if not exists aura_tracks_category_idx
  on public.aura_tracks (category, sort_order);

-- Public read
alter table public.aura_tracks enable row level security;
create policy if not exists "aura_tracks public read"
  on public.aura_tracks for select
  using ( true );
```

- [ ] **Step 2: Apply via Supabase MCP**

Use the Supabase MCP tool `apply_migration` with this SQL against project `vzuwvsmlyigjtsearxym`. Migration name: `2026_04_07_aura_tracks`.

Verify:
```sql
select id, name from storage.buckets where id = 'aura-audio';
select count(*) from public.aura_tracks;
```
Expected: bucket exists, count = 0.

- [ ] **Step 3: Commit**

```bash
git add tools/aura/supabase_schema.sql
git commit -m "feat(aura): add Supabase schema for aura_tracks + public bucket"
```

---

## Task 7: Upload all 24 tracks and seed `aura_tracks`

**Files:**
- Create: `tools/aura/upload_supabase.py`

This script needs the Supabase **service role key** (write access to storage). The user keeps it out of git — read it from an env var the user sets in their shell before running. Document this in the README.

- [ ] **Step 1: Write the uploader**

Create `tools/aura/upload_supabase.py`:
```python
"""
Upload all AURA audio files to bucket 'aura-audio' and insert/update rows
in public.aura_tracks. Requires SUPABASE_SERVICE_ROLE_KEY env var.
"""
import json
import os
import sys
import subprocess
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "tracks_manifest.json"

PROJECT = "vzuwvsmlyigjtsearxym"
BASE = f"https://{PROJECT}.supabase.co"
BUCKET = "aura-audio"

KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
if not KEY:
    sys.exit("Set SUPABASE_SERVICE_ROLE_KEY env var first")

HEADERS = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
}

def ffprobe_duration(p: Path) -> int:
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nokey=1:noprint_wrappers=1", str(p)],
        capture_output=True, text=True, check=True)
    return int(float(r.stdout.strip()))

def upload(file: Path, dest_path: str) -> str:
    """Upload (or overwrite) and return the public URL."""
    url = f"{BASE}/storage/v1/object/{BUCKET}/{dest_path}"
    with open(file, "rb") as f:
        r = requests.post(url, headers={**HEADERS, "Content-Type": "audio/mpeg",
                                        "x-upsert": "true"}, data=f, timeout=300)
    if r.status_code not in (200, 201):
        raise RuntimeError(f"upload failed {r.status_code}: {r.text}")
    return f"{BASE}/storage/v1/object/public/{BUCKET}/{dest_path}"

def upsert(row: dict) -> None:
    url = f"{BASE}/rest/v1/aura_tracks"
    r = requests.post(url, headers={**HEADERS,
                                    "Content-Type": "application/json",
                                    "Prefer": "resolution=merge-duplicates"},
                      json=[row], timeout=30)
    if r.status_code not in (200, 201, 204):
        raise RuntimeError(f"upsert failed {r.status_code}: {r.text}")

def main() -> None:
    m = json.loads(MANIFEST.read_text(encoding="utf-8"))

    sort = 0
    for t in m["frequencies"]:
        local = ROOT / t["file"]
        dest = f"frequencies/{Path(t['file']).name}"
        url = upload(local, dest)
        upsert({
            "id": t["id"],
            "category": "frequency",
            "hz": t["hz"],
            "chakra": t["chakra"],
            "color_hex": t["color_hex"],
            "icon": None,
            "name_en": t["name_en"],
            "name_es": t["name_es"],
            "desc_en": t["desc_en"],
            "desc_es": t["desc_es"],
            "duration_sec": ffprobe_duration(local),
            "file_path": dest,
            "audio_url": url,
            "license": "GENERATED",
            "freesound_id": None,
            "freesound_user": None,
            "sort_order": sort,
        })
        print(f"freq  {t['id']}  -> {url}")
        sort += 1

    # Read fetch_log to attribute Freesound creators where applicable
    log_path = ROOT / "fetch_log.json"
    log = {e["id"]: e for e in json.loads(log_path.read_text())} if log_path.exists() else {}

    sort = 0
    for t in m["nature"]:
        local = ROOT / t["file"]
        dest = f"nature/{Path(t['file']).name}"
        url = upload(local, dest)
        meta = log.get(t["id"], {})
        upsert({
            "id": t["id"],
            "category": "nature",
            "hz": None,
            "chakra": None,
            "color_hex": None,
            "icon": t["icon"],
            "name_en": t["name_en"],
            "name_es": t["name_es"],
            "desc_en": t["desc_en"],
            "desc_es": t["desc_es"],
            "duration_sec": ffprobe_duration(local),
            "file_path": dest,
            "audio_url": url,
            "license": t["license"],
            "freesound_id": meta.get("freesound_id"),
            "freesound_user": meta.get("freesound_user"),
            "sort_order": sort,
        })
        print(f"nat   {t['id']}  -> {url}")
        sort += 1

    print("\nDone.")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Set the env var and run**

```bash
export SUPABASE_SERVICE_ROLE_KEY="<paste from KEYS_LOCAL.md>"
cd tools/aura && .venv/Scripts/python upload_supabase.py
```

Expected: 24 lines of `freq …` and `nat …` with public URLs printed.

- [ ] **Step 3: Verify in Supabase**

Use the Supabase MCP `execute_sql` tool to run:
```sql
select category, count(*) from public.aura_tracks group by category;
```
Expected: `frequency 9`, `nature 15`.

Pick one URL from the output and `curl -I` it — should return `200 OK` with `Content-Type: audio/mpeg`.

- [ ] **Step 4: Commit**

```bash
git add tools/aura/upload_supabase.py
git commit -m "feat(aura): add Supabase uploader and seed for aura_tracks"
```

---

## Task 8: README & handoff to Plan 2

**Files:**
- Create: `tools/aura/README.md`

- [ ] **Step 1: Write the README**

Create `tools/aura/README.md`:
```markdown
# AURA Content Pipeline

End-to-end pipeline that produces the wellness audio catalog consumed by the Pixora app's AURA tab.

## One-shot rebuild

```bash
cd tools/aura
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt

bash gen_frequencies.sh           # 9 Solfeggio MP3s, 15 min each
bash gen_noise.sh                 # white + brown noise
.venv/Scripts/python freesound_fetch.py     # download nature sounds
.venv/Scripts/python process_nature.py      # trim/loop/normalize

# Apply schema once via Supabase MCP (see supabase_schema.sql)

export SUPABASE_SERVICE_ROLE_KEY="..."   # from KEYS_LOCAL.md
.venv/Scripts/python upload_supabase.py
```

## Editing the catalog

`tracks_manifest.json` is the single source of truth. Adding a track = adding an entry there + re-running the relevant generator/fetcher + the uploader.

## Output

- Bucket: `aura-audio` (public)
- Table: `public.aura_tracks` (read by the Flutter app)
```

- [ ] **Step 2: Commit and tag the milestone**

```bash
git add tools/aura/README.md
git commit -m "docs(aura): pipeline README"
git tag aura-content-v1
```

---

## Done criteria

- `select count(*) from public.aura_tracks` returns 24
- All 24 audio URLs return 200 with `Content-Type: audio/mpeg`
- Manual smoke-listen of 3 random tracks (1 frequency, 1 downloaded nature, 1 generated noise) sounds clean and consistent in loudness
- Plan 2 (App Integration) can start consuming `public.aura_tracks` immediately
