# AURA Content Pipeline

End-to-end pipeline that produces the wellness audio catalog consumed by Pixora's AURA tab.

## One-shot rebuild

```bash
cd tools/aura
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt

bash gen_frequencies.sh           # 9 Solfeggio MP3s, 15 min each
bash gen_noise.sh                 # white + brown noise, 15 min each
.venv/Scripts/python freesound_fetch.py     # download nature sounds (CC0)
.venv/Scripts/python process_nature.py      # trim/loop/normalize

# Apply schema once via Supabase MCP (see supabase_schema.sql)

export SUPABASE_SERVICE_ROLE_KEY="..."   # from KEYS_LOCAL.md
.venv/Scripts/python upload_supabase.py
```

## Source of truth

`tracks_manifest.json` lists every track. Adding/removing = edit there + re-run the relevant generator + uploader.

## Output

- Bucket: `aura-audio` (public)
- Table: `public.aura_tracks` (read by the Flutter app)
