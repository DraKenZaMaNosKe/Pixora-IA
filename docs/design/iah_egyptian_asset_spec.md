# Iah Egyptian · Parallax Asset Spec

LiveCalendar deck #1 — first parallax-ready set with chroma-keyed layers + PNG sequence sprites.

## 🎨 Estandarización

- **Chroma key color**: `#00B140` (Hollywood pure chroma green)
- **Static images**: 1080×1080 (moons + halo + frame) o 1080×2340 (landscapes)
- **Animated sprites**: video → PNG sequence (24-60 frames, 24fps, transparent after chroma)
- **Naming**: lowercase, snake_case, descriptive
- **Carpeta destino**: `D:/Orbix/Pixora-IA/docs/design/concepts/livecalendar/egyptian/`

## 📋 Asset list

### Capa 0 — Fondo (sin chroma, es el fondo real)

**`bg_sky_lapis.webp`** · 1080×2340 portrait
```
Generate a single Unreal Engine HD render, portrait 1080x2340, ideal for phone live wallpaper background. Subject: a deep lapis lazuli night sky with subtle scattered stars. The sky goes from medium-dark lapis blue (#0A1A38) at the bottom to almost black at the top. Stars rendered as small bright pinpricks of gold and white, scattered naturally — denser at the top, sparser near the bottom. Add very subtle constellation lines drawn in fine gold connecting some stars (decorative, no specific zodiac). Style: cinematic, museum-quality, photorealistic. Mood: ancient sacred night. NO MOON, NO LANDSCAPE, NO TEXT, NO LETTERS, NO WATERMARKS. Pure starry night sky only.
```

### Capa 1 — Paisaje (chroma green, silueta)

**`landscape_giza.png`** · 1080×2340 portrait, chroma green
```
Generate a single Unreal Engine HD render, portrait 1080x2340. Subject: silhouette of the three Pyramids of Giza with desert dunes in the foreground. Background fill: PURE CHROMA GREEN #00B140 (everywhere except the silhouettes). The pyramids are solid black silhouettes with very subtle gold edge highlights catching the moonlight. Sand dunes in the bottom 1/3 are dark gold/sand color (#C9A06A) with subtle rippled texture. Composition: pyramids centered, dunes filling the bottom third, the upper 2/3 is PURE CHROMA GREEN #00B140 — completely flat, no gradient, no stars, no clouds. This is for chroma key extraction. Style: cinematic museum-quality. NO TEXT, NO LETTERS, NO WATERMARKS, NO MOON, NO STARS, NO SKY GRADIENT — just pure flat green where the sky would be.
```

### Capa 2 — Lunas (8 fases, chroma green)

> **Convención global**: 1080×1080 square. Fondo: `#00B140` chroma green flat. La luna ocupa ~70% del frame, centrada. NO halo, NO frame ornamental — esos son capas separadas.

**`moon_d00_new.png`**
```
Generate Unreal Engine HD render, square 1080x1080, with PURE CHROMA GREEN #00B140 background. Subject: ancient Egyptian new moon — perfectly black moon disc, matte obsidian-black, subtle texture suggesting carved stone. Composition: moon centered, occupies 70% of frame. Background is PURE FLAT CHROMA GREEN #00B140 only — for chroma key extraction. Cinematic museum-quality. NO STARS, NO HALO, NO FRAME, NO TEXT, NO WATERMARKS. Just the dark moon disc on flat chroma green.
```

**`moon_d04_waxing_crescent.png`**
```
Generate Unreal Engine HD render, square 1080x1080, with PURE CHROMA GREEN #00B140 background. Subject: ancient Egyptian waxing crescent moon, 13 percent illuminated — thin sliver of luminous gold-cream light on the right edge, the rest deep matte black. Style: cinematic museum-quality, gold tones #FFD200. Composition: moon centered, occupies 70% of frame. Background is PURE FLAT CHROMA GREEN #00B140 only — for chroma key extraction. NO HALO, NO FRAME, NO STARS, NO TEXT.
```

**`moon_d07_first_quarter.png`**
```
Generate Unreal Engine HD render, square 1080x1080, PURE CHROMA GREEN #00B140 background. Subject: ancient Egyptian first quarter moon, exactly half illuminated — right side bright gold-cream papyrus texture, left side deep matte black. Subtle Eye of Horus barely visible at the terminator (light/dark boundary). Composition: moon centered. Background is PURE FLAT CHROMA GREEN #00B140 only. NO HALO, NO FRAME, NO STARS, NO TEXT.
```

**`moon_d11_waxing_gibbous.png`**
```
Generate Unreal Engine HD render, square 1080x1080, PURE CHROMA GREEN #00B140 background. Subject: ancient Egyptian waxing gibbous moon, 84 percent illuminated. Bright gold-leaf surface with subtle natural-looking crater patterns. Thin sliver of shadow on the LEFT edge. Composition: moon centered. Background is PURE FLAT CHROMA GREEN #00B140. NO HALO, NO FRAME, NO STARS, NO TEXT.
```

**`moon_d14_full.png`**
```
Generate Unreal Engine HD render, square 1080x1080, PURE CHROMA GREEN #00B140 background. Subject: ancient Egyptian FULL MOON, 100 percent illuminated, divine. Rich golden papyrus texture across the surface with subtle hieroglyph-suggested crater shadows. Composition: moon centered, occupies 75% of frame. Background is PURE FLAT CHROMA GREEN #00B140 only — for chroma key extraction. NO HALO (separate layer), NO FRAME (separate layer), NO STARS, NO TEXT.
```

**`moon_d18_waning_gibbous.png`** · mirror of d11 (shadow on RIGHT edge)
**`moon_d22_last_quarter.png`** · mirror of d07 (LEFT side bright)
**`moon_d26_waning_crescent.png`** · mirror of d04 (sliver on LEFT)

### Capa 3 — Halo dorado (chroma green)

**`halo_gold.png`** · 1080×1080 square, chroma green
```
Generate Unreal Engine HD render, square 1080x1080, PURE CHROMA GREEN #00B140 background. Subject: a glowing gold halo / aura ring — translucent radial glow with golden rays extending outward. CENTER of the halo is COMPLETELY TRANSPARENT GREEN #00B140 (this is where the moon will sit behind). Outer edge: warm gold #FFD200 fading to soft amber. The halo itself is a ring/glow, NOT a solid disc. Composition: halo centered, occupies 95% of frame. Background everywhere (including center) is PURE FLAT CHROMA GREEN #00B140. The halo is gold ONLY — green stays green for chroma extraction. NO MOON, NO TEXT, NO STARS.
```

### Capa 4 — Anillo de jeroglíficos (chroma green)

**`frame_hieroglyph.png`** · 1080×1080 square, chroma green
```
Generate Unreal Engine HD render, square 1080x1080, PURE CHROMA GREEN #00B140 background. Subject: an ornate decorative ring/border made of pure gold (#FFD200), inscribed with ancient Egyptian hieroglyphs — Eye of Horus, ankh, ibis, scarab, pyramid glyphs. The ring is approximately 80% of frame diameter, hollow center (transparent green). The ring is detailed gold with hieroglyphic carvings around its full circumference. CENTER and OUTSIDE of the ring are PURE FLAT CHROMA GREEN #00B140. Style: museum-quality engraving, ornate, ceremonial. NO MOON inside, NO BACKGROUND TEXTURE, NO TEXT (other than hieroglyphic carvings).
```

### Capa 5 — Partículas / polvo dorado (sprite anim)

**`iah_dust_particles/`** · 24 frames PNG sequence, chroma green
```
[GROK VIDEO PROMPT]
Create a 4-second looping video: golden dust particles and tiny luminous fireflies slowly drifting upward and slightly sideways across the frame. ~10-15 individual particles of varying sizes (small to medium), pure gold color #FFD200, soft glow. Background: PURE FLAT CHROMA GREEN #00B140 — completely flat, no other elements. Particles must drift smoothly at 24fps, ambient and gentle, sacred atmosphere. Resolution 1080x1080. NO TEXT, NO OTHER SUBJECTS — just gold particles drifting on chroma green.
```

After Grok generates: open in CapCut Pro → chroma key the green → File > Export > PNG sequence at 24fps → save folder as `iah_dust_particles/` with frames `frame_0001.png` ... `frame_0024.png`.

### Capa 6 — Ojo de Horus animado (sprite anim, hero)

**`iah_eye_of_horus/`** · 30 frames PNG sequence, chroma green
```
[GROK VIDEO PROMPT]
Create a 3-second looping video at 24fps, 1080x1080 resolution: the Egyptian Eye of Horus rendered in pure gold #FFD200 with hieroglyphic precision. Animation: the eye slowly opens fully, glows with a divine golden light pulse, then slowly closes. Loop seamlessly. Background: PURE FLAT CHROMA GREEN #00B140 — completely flat, only the eye visible. The eye should pulse with sacred energy — the gold gets brighter/dimmer subtly as it opens. NO TEXT, NO OTHER ELEMENTS, NO BACKGROUND TEXTURE. Just the gold Eye of Horus opening, glowing, closing on flat chroma green.
```

CapCut: chroma → PNG sequence → folder `iah_eye_of_horus/` with `frame_0001.png` ... `frame_0030.png`.

### Capa 7 — Iah cruzando en barca lunar (sprite anim, opcional)

**`iah_lunar_boat/`** · 60 frames PNG sequence, chroma green
```
[GROK VIDEO PROMPT]
Create a 30-second looping video at 24fps, 1080x500 (wide format): a tiny silhouette of the Egyptian moon god Iah riding a curved papyrus reed boat across the night sky. The boat and figure are gold #FFD200 silhouettes, very small (occupy ~8% of frame width). Animation: drift smoothly from far left edge to far right edge over 30 seconds. Background: PURE FLAT CHROMA GREEN #00B140 — only the small gold boat silhouette is visible. Seamless loop. NO TEXT, NO OTHER ELEMENTS, NO BACKGROUND TEXTURE.
```

## 📐 Spec JSON (cómo se compone en el motor)

```json
{
  "schema_version": 1,
  "id": "iah_egyptian_giza",
  "type": "canvas_scene",
  "background": {
    "url": "<bg_sky_lapis.webp>",
    "scroll": false
  },
  "image_layers": [
    { "key": "landscape", "z": -5, "parallax_factor": 0.20, "url": "<landscape_giza.webp>" },
    { "key": "moon",      "z":  0, "parallax_factor": 0.50, "url": "<moon_d{phase}.webp>" },
    { "key": "halo",      "z":  1, "parallax_factor": 0.52, "url": "<halo_gold.webp>" },
    { "key": "frame",     "z":  3, "parallax_factor": 0.65, "url": "<frame_hieroglyph.webp>" }
  ],
  "sprites": [
    {
      "name": "eye_of_horus",
      "manifest_key": "iah_eye_of_horus",
      "behavior": "phase_triggered",
      "active_phases": ["full"],
      "frame_skip": 2,
      "params": { "x": 0.5, "y": 0.35, "scale": 0.4, "alpha": 220, "parallax_factor": 0.5 }
    },
    {
      "name": "dust",
      "manifest_key": "iah_dust_particles",
      "behavior": "static",
      "frame_skip": 2,
      "params": { "x": 0.5, "y": 0.5, "scale": 1.0, "alpha": 180, "parallax_factor": 0.85 }
    },
    {
      "name": "lunar_boat",
      "manifest_key": "iah_lunar_boat",
      "behavior": "time_triggered",
      "active_hours": ["dawn", "dusk"],
      "frame_skip": 1,
      "params": { "x": 0.0, "y": 0.65, "scale": 1.0, "alpha": 200 }
    }
  ],
  "events": [
    {
      "kind": "flash_overlay",
      "trigger": "moonrise",
      "interval_s": 60,
      "duration_s": 0.5,
      "params": { "color": "#FFD200", "peak_alpha": 60 }
    }
  ]
}
```

## 🚀 Orden de generación recomendado

**Sprint 1 — Validación visual (lo crítico)** · 5 prompts:
1. `bg_sky_lapis.webp` — el fondo
2. `landscape_giza.png` — silueta pirámides
3. `moon_d14_full.png` — luna llena (la más bonita, la que valida estilo)
4. `halo_gold.png` — resplandor
5. `frame_hieroglyph.png` — anillo

Con esos 5 yo monto el primer mockup parallax estático en HTML para validar la composición.

**Sprint 2 — Lunas restantes** · 7 prompts: las 7 fases que faltan.

**Sprint 3 — Animaciones** · 3 videos en Grok:
- `iah_dust_particles/` (más fácil, valida el flujo Grok→CapCut→PNG sequence)
- `iah_eye_of_horus/` (hero animation)
- `iah_lunar_boat/` (opcional, scope creep)

**Sprint 4 — Otras escenas** (si Giza convence): Nilo, Sphinx, Karnak — solo el `landscape_*` cambia, los moons + halo + frame + sprites se reusan.

## ✅ Checklist por sprint

- [ ] Sprint 1: 5 imágenes generadas, chromas hechos
- [ ] Sprint 2: 7 lunas restantes
- [ ] Sprint 3: 3 sprite sequences
- [ ] Mockup HTML parallax validado
- [ ] Spec JSON subido a Supabase
- [ ] Wallpaper testeado en device
