---
name: pixora-batch-content
description: "Use to run the full content generation pipeline for Pixora: scrape a reference source (URL or folder), analyze each reference image, craft prompts optimized for the target AI (Grok / Gemini / ChatGPT / Claude in Chrome), drive the AI site via browser automation to generate each image, download results, post-process (resize, convert, name), and optionally upload to a Supabase bucket with catalog update. Trigger on 'bajar referencias', 'generar wallpapers en lote', 'batch de imágenes', 'crear wallpapers desde referencias', 'scrape and generate', or any multi-step content generation request."
---

# Pixora Batch Content Generation

Turns the "I want 30 wallpapers inspired by famous paintings" idea into an actual batch pipeline. Combines **chrome-devtools-mcp** (browser automation) + **ffmpeg/Pillow** (post-processing) + **Supabase MCP** (catalog upload).

## What the user provides upfront

Ask **before** starting — don't guess:

1. **Reference source** — one of:
   - A URL (e.g. `https://en.wikipedia.org/wiki/List_of_most_expensive_paintings`)
   - A local folder (e.g. `D:/Orbix/refs/starry_night/`)
   - A list of individual image URLs
2. **Target AI generator**:
   - Grok (`grok.com/chat`)
   - Gemini (`gemini.google.com`)
   - ChatGPT (`chatgpt.com`)
   - Claude in Chrome (`claude.ai`)
   - Or generic (save prompts to a .txt for manual batch)
3. **Destination bucket / category** in Pixora:
   - `wallpaper-images` (static wallpapers catalog)
   - `wallpaper-videos` (if generating videos)
   - Other / dry run (don't upload, just save locally)
4. **Count** — how many images to generate
5. **Style guidance** — free-text the user gives ("cinematic, dramatic, 4K, no text, dark mood")
6. **Target dimensions** — default 1080×1920 (phone portrait). Can also be 1080×2340, 2160×3840, or custom.

## The phases

### Phase 1 — Collect references

**From a URL**: use the `chrome-devtools-mcp` tools to navigate to the page, take a snapshot (`take_snapshot`), and extract image sources. Strategy:

```
1. navigate_page → the URL
2. take_snapshot → get the DOM
3. evaluate_script → querySelectorAll('img') and return src + alt + naturalWidth/Height
4. Filter out icons, thumbnails < 400px wide, base64 inline garbage
5. Download each via curl to tools/batch/<job_id>/refs/
```

**From a folder**: just list the files and copy metadata.

Report count: "Collected N references (M filtered out as too small / non-image)."

### Phase 2 — Analyze each reference

For each image, gather:
- Dimensions (`ffprobe` or Pillow)
- Aspect ratio
- Dominant color palette (use Pillow quantize to top 5 colors)
- Visual description — **use your own vision capability** to look at the image and describe: subject, style, mood, era, technique, notable elements

Save a manifest to `tools/batch/<job_id>/refs.json`:
```json
[
  {
    "ref_file": "refs/001.jpg",
    "dims": [1024, 768],
    "aspect": 1.333,
    "palette": ["#1a1a2e", "#c49e44", ...],
    "analysis": "Oil painting, Renaissance era, warm golden tones, central figure...",
    "source_url": "https://..."
  },
  ...
]
```

### Phase 3 — Prompt generation

For each reference, craft a prompt tuned to the target AI's style. General template:

```
[Subject from analysis], in the style of [style from analysis],
[palette colors as adjectives], [user's style guidance],
portrait orientation, [target dimensions], no text, no watermark,
highly detailed, cinematic composition
```

AI-specific tweaks:
- **Grok**: tolerates long prompts, responds to negative prompts inline
- **Gemini**: prefers shorter, natural-language prompts
- **ChatGPT (DALL-E)**: very literal — be explicit about what you DON'T want
- **Claude in Chrome**: natural language, can handle multi-paragraph creative direction

Save to `tools/batch/<job_id>/prompts.json`:
```json
[
  {"ref_id": "001", "prompt": "...", "target_dims": [1080, 1920]},
  ...
]
```

### Phase 4 — Review checkpoint 🛑

**Stop and show the user**:
- The list of references (filenames + short analyses)
- The first 3 generated prompts in full
- The target AI, destination bucket, total count

Ask: *"Do these look right? Reply **go**, **edit**, or **stop**."*

Only proceed on explicit `go`. On `edit`, iterate on prompts with user feedback. On `stop`, save the manifest so they can resume later.

### Phase 5 — Generate (browser automation loop)

For each prompt in the approved list:

```
1. navigate_page → target AI chat URL (reuse existing tab if possible — respect tabs_context)
2. wait_for → the prompt input to be ready
3. fill → the prompt text
4. click → send
5. wait_for → the generated image element (timeout 90s per image)
6. evaluate_script → extract image URL / right-click download URL
7. curl → download to tools/batch/<job_id>/raw/<ref_id>.png
8. take_screenshot of the result for audit trail
9. new chat / clear before next (avoid context pollution in the AI's memory)
```

**Rate limiting**: wait 3-5 seconds between prompts. Free tiers on most AIs throttle aggressively.

**Failure handling**: if generation fails 2x for the same prompt, log it and move on. Don't block the batch.

Checkpoint every 5 images: save progress to `tools/batch/<job_id>/progress.json` so the batch is resumable on crash.

### Phase 6 — Post-process

For each downloaded raw image:

1. Verify dimensions. If wrong aspect ratio, note it (don't auto-crop without asking).
2. Convert to WebP at 90% quality for Supabase catalog (saves ~40% size vs PNG):
   ```bash
   ffmpeg -i raw/001.png -quality 90 processed/001.webp
   ```
3. Rename consistently: `<category>_<slug>_NNN.webp` (e.g. `art_starry_night_001.webp`)
4. Store metadata for the catalog entry: dimensions, byte size, prompt used, reference source URL.

### Phase 7 — Upload (optional)

If the user chose a Supabase bucket:

1. Read service role key from `KEYS_LOCAL.md` (same pattern as `tools/aura/upload_supabase.py`)
2. Upload each WebP to the chosen bucket
3. Update the relevant catalog JSON (e.g. `wallpaper-videos/catalog.json` for the wallpapers list) or table, depending on which pattern the target bucket uses (see CLAUDE.md §Catalog patterns)
4. Verify with `curl -sI` that at least 3 random URLs return 200

### Phase 8 — Report + cleanup

```
🎨 Batch Content Generation
  Job ID:       <job_id>
  Source:       <URL or folder>
  References:   N collected (M filtered)
  Target AI:    <name>
  Approved:     <user confirmation>
  Generated:    X/N successful (Y failed)
  Processed:    X WebP files in tools/batch/<job_id>/processed/
  Uploaded:     ✅ N to <bucket> + catalog updated  (or: skipped)
  Screenshots:  tools/batch/<job_id>/screenshots/
  Next steps:   <list of any manual actions needed>
```

Offer to move the job folder to an archive path and clean up temp files.

## Directory convention

```
tools/batch/<job_id>/
├── refs/          # downloaded reference images
├── refs.json      # analysis manifest
├── prompts.json   # generated prompts
├── raw/           # raw outputs from the AI
├── processed/     # final WebPs ready for upload
├── screenshots/   # audit trail from generation
└── progress.json  # resumable state
```

`job_id` is a short slug — timestamp + topic, e.g. `20260408_famous_paintings`.

Add `tools/batch/` to `.gitignore` — these folders get huge and shouldn't be committed.

## What NOT to do

- **Never skip Phase 4 (review checkpoint)**. Generating 30 images with a bad prompt burns API quota and time.
- **Never trigger confirm/alert dialogs** in the browser (per chrome-devtools-mcp guidance — they block all further events).
- **Never hardcode AI-specific selectors** — use `take_snapshot` to find elements dynamically. Websites change.
- **Never upload without verifying 3 random URLs return 200** after upload.
- **Never paste the Supabase service role key** anywhere visible — always read from `KEYS_LOCAL.md`.
- **Don't generate more than 50 in one batch** without a break — AIs rate-limit and you burn your free tier.
- **Don't assume image licenses** from scraped URLs are free to use commercially. Public-domain art (Wikipedia Commons with clear PD tag) is safe; other sources aren't. Ask the user to confirm source legality.

## Relation to other skills

- Uses `chrome-devtools-mcp` tools for all browser automation
- Can call `pixora-master-doc-append` to log the batch in the master doc
- Its output may feed directly into Pixora's wallpaper catalog, similar to how `pixora-aura-track-add` updates AURA
