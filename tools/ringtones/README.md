# Pixora Ringtones Pipeline

Adds new ringtone packs (or extends existing ones) by sourcing CC0 audio from
[Freesound](https://freesound.org), processing it to spec, uploading to
Supabase Storage, and merging into `ringtones_catalog.json` — then firing an
FCM push so live users see new content without an app update.

## Layout

```
tools/ringtones/
├── manifest.json   ← What to fetch (packs + tones + queries + target lengths)
├── fetch.py        ← Freesound search + download → raw/<pack>/<id>.mp3
├── process.py      ← Trim + fade + normalize → out/<pack>/<id>.mp3
├── upload.py       ← Upload to Supabase + merge catalog + FCM push
├── raw/            ← Untouched preview MP3s from Freesound (gitignored)
└── out/            ← Final processed MP3s ready to ship (gitignored)
```

## Run order

```bash
# 1. Download from Freesound (idempotent — skips cached raw files)
python tools/ringtones/fetch.py

# 2. Process to final length + normalize (rerun safe — overwrites out/)
python tools/ringtones/process.py

# 3. Upload to Supabase + merge catalog + fire FCM push
python tools/ringtones/upload.py
```

## Manifest schema

```jsonc
{
  "packs": [
    {
      "id": "pack_id",              // Stable slug for the pack
      "name": "Display name",        // What users see
      "category": "ANIMALS",         // Filter category
      "description": "...",          // Pack description (1-2 sentences)
      "glowColor": "#FFB6D9",        // Accent color for pack card
      "previewImage": "x.webp",      // Existing image in wallpaper-images
      "new_pack": true,              // false = APPEND to existing pack
      "tones": [
        {
          "id": "tone_id",            // Stable slug for the tone
          "name": "Display name",     // What users see
          "freesound_query": "...",   // Search query for Freesound API
          "target_sec": 2,            // Final length after processing (1-30)
          "suggestedType": "notification" // or "ringtone"
        }
      ]
    }
  ]
}
```

## Merge behavior

- **new_pack: true** + pack_id not in catalog → creates a fresh pack at the end
- **new_pack: false** OR pack_id already exists → APPENDS tones to the existing
  pack (never replaces — existing tones are preserved, only new IDs are added)

## Audio specs

- **Source**: 44.1 kHz preview MP3 from Freesound (CC0 only)
- **Output**: 192 kbit/s MP3, loudnorm to -16 LUFS (slightly louder than AURA's
  -18 LUFS so notifications cut through background noise)
- **Length**: per `target_sec` in manifest (1-30s typical)
- **Fades**: 10 ms fade-in + 50 ms fade-out to prevent clicks

## Notes & pitfalls

- All sources MUST be CC0. The fetch script filters by license at API level.
- `target_sec=1` is fine for very short SFX (typewriter ding, etc.) but the
  loudnorm filter needs ≥200 ms or it will pad silence.
- Existing packs in `ringtones_catalog.json` are NEVER touched except to
  append new tones. The catalog version timestamp is bumped on every upload.
- FCM push fires automatically at end of upload — clients refresh on next
  open or pull-to-refresh.
