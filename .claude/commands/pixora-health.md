---
description: "Lightweight Supabase health check for Pixora catalogs — row counts + 3 random URL pings"
---

Run a lightweight health check against Supabase and report findings. Don't fix anything — just observe and report.

### Steps

1. Use the Supabase MCP `execute_sql` tool against project `vzuwvsmlyigjtsearxym`:
   - `select category, count(*) from public.aura_tracks group by category`
     Expected: `frequency=9`, `nature=15`.

2. Pick 3 semi-random rows from `aura_tracks` covering both categories — query:
   `select id, audio_url from public.aura_tracks order by random() limit 3`

3. For each returned URL, ping it:
   ```bash
   curl -sI -o /dev/null -w "%{http_code}\n" <url>
   ```
   Expected: `200` for each.

4. Optionally: pick one wallpaper catalog JSON and curl its URL as a basic sanity check:
   ```
   https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public/wallpaper-videos/live_wallpaper_catalog.json
   ```

### Report format

```
🔍 Pixora Supabase Health
  aura_tracks:   24/24 ✅  (frequency=9, nature=15)
  AURA URLs:     3/3 → 200 ✅
  Live catalog:  200 ✅
  Verdict:       ALL GREEN  (or ⚠️  with specific failures)
```

If any check is red, report the specific row / URL / status and stop — don't try to fix. The user decides next steps.
