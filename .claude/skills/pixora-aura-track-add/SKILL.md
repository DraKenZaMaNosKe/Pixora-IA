---
name: pixora-aura-track-add
description: "Use to add a new audio track to the Pixora AURA module (Solfeggio frequency or nature sound). Handles the full pipeline: edit tracks_manifest.json → run the correct generator/fetcher → normalize → upload to Supabase bucket → insert row in aura_tracks table → verify URL returns 200 → append entry to master doc §14.3 or §14.4. Trigger on 'agregar una frecuencia a AURA', 'nuevo sonido en AURA', 'add a track to aura'."
---

# Pixora AURA Track Add

Adds a new track to the AURA catalog. Guards against the pitfalls we hit during the initial AURA build (duplicate Freesound results, silent URL misses, forgetting to update the doc).

## What the user provides

Ask upfront, don't guess:

1. **Category**: `frequency` or `nature`
2. **If frequency**: Hz value (integer), chakra (root/sacral/solar_plexus/heart/throat/third_eye/crown or none), color hex
3. **If nature**: short id slug (e.g. `nat_thunder_soft`), icon name (see existing cards), Freesound query string
4. **Bilingual metadata**: `name_en`, `name_es`, `desc_en`, `desc_es`
5. **Duration**: minutes (default 15 for frequencies, 10 for nature)

If any of these is missing, stop and ask — never invent descriptions.

## The flow

### Step 1 — Edit manifest

Open `tools/aura/tracks_manifest.json` and append the new entry to the correct array (`frequencies` or `nature`), following the existing schema exactly. Validate JSON is still parseable:
```bash
python -m json.tool tools/aura/tracks_manifest.json > /dev/null
```

### Step 2 — Generate or fetch the audio

**For frequency**: extend `tools/aura/gen_frequencies.sh` (add the new `"Hz:name"` pair), then:
```bash
bash tools/aura/gen_frequencies.sh
```
This regenerates all frequencies — cheap, takes ~5 min. The new one appears at `tools/aura/out/frequencies/<Hz>hz_<name>.mp3`.

**For nature**: run the fetcher for just the new track:
```bash
cd tools/aura && .venv/Scripts/python freesound_fetch.py
```
Then verify: listen to the raw file (`raw/<id>.mp3`) briefly. If it sounds wrong (talking, music, low quality), update the `freesound_query` in the manifest and rerun. Then process:
```bash
.venv/Scripts/python process_nature.py
```

### Step 3 — Upload to Supabase

```bash
cd tools/aura && .venv/Scripts/python upload_supabase.py
```

The script reads `KEYS_LOCAL.md` for the service role key and idempotently upserts all rows. New track should appear in the output with its public URL.

### Step 4 — Verify

1. Database row count:
   ```
   [Supabase MCP] execute_sql: "select count(*) from public.aura_tracks"
   ```
   Should be the previous count + 1.

2. URL reachable:
   ```bash
   curl -sI -o /dev/null -w "%{http_code}\n" <audio_url>
   ```
   Must return `200`.

3. MIME is audio:
   ```bash
   curl -sI <audio_url> | grep -i "content-type"
   ```
   Expect `audio/mpeg`.

### Step 5 — Append to master doc

Use the `pixora-master-doc-append` skill (or its pattern):
- For frequency: append to §14.3 (Frecuencias Solfeggio — tabla)
- For nature: append to §14.4 (Catálogo de Naturaleza)

Include the Hz (or icon), name ES/EN, and the Freesound attribution if applicable (`freesound_user` from fetch_log.json).

### Step 6 — Commit

```bash
git add tools/aura/tracks_manifest.json tools/aura/gen_frequencies.sh
git commit -m "feat(aura): add <category> track <id> (<name_en>)"
```

Audio files themselves are gitignored — don't try to commit them.

### Step 7 — App verification (optional but recommended)

Invoke the `pixora-device-test` skill to rebuild + install + launch, then have the user manually verify the new track appears in the AURA tab.

## Reporting

```
🎵 AURA Track Added
  Category:    frequency | nature
  ID:          <id>
  Name:        <name_en> / <name_es>
  Manifest:    ✅ updated
  Audio:       ✅ generated / fetched (processed to N MB, 10:00 duration)
  Supabase:    ✅ row upserted, URL 200 OK, audio/mpeg
  Master doc:  ✅ §14.X updated
  Commit:      <SHA>
  Next:        run pixora-device-test to verify in-app
```

## What NOT to do

- Don't skip the audio quality listen on nature sounds — CC0 results on Freesound can be hit-or-miss.
- Don't hardcode the service role key anywhere — always read from `KEYS_LOCAL.md`.
- Don't commit files from `tools/aura/out/` or `tools/aura/raw/` — gitignored.
- Don't invent descriptions when the user only gave you a name. Ask.
- Don't skip the URL verification — a 404 audio link is invisible until a user taps it.
