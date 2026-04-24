# Gemini Image Prompts — 10 Pixora Wallpaper Concepts

**Uso**: pegar cada prompt en Gemini (Create Image mode, no style selected) para generar el fondo hero de cada concepto. Dimensiones esperadas: vertical 9:19.5 portrait (1408×3040 o similar — Gemini escoge, luego downscaleamos a 1080×2340).

**Regla global**:
- Siempre pedir "Tall vertical phone wallpaper, 9:19.5 portrait aspect"
- Siempre incluir "No characters, no people, no text, no letters, no logos, no UI elements"
- Siempre indicar dónde dejar espacio limpio para compositar los sprites animados

---

## 01 · Cherry Blossom 🌸

```
Tall vertical phone wallpaper, 9:19.5 portrait aspect. Serene Japanese landscape at sunset. Large red-orange torii gate silhouette centered on a still reflecting pond. Distant misty mountains in soft purple. Sky gradient from warm pink at horizon through coral to deep twilight at top, with a hazy golden sun low behind the torii casting light on the water. Cherry blossom petals drifting in the air, some blurred in foreground. Cinematic painterly quality, Studio Ghibli poster aesthetic, strong atmospheric perspective. No characters, no people, no text, no letters. Central area above the pond kept visually clean for a small animated character later.
```

## 02 · Neon Alley (Cyberpunk) 🌃

```
Tall vertical phone wallpaper, 9:19.5 portrait aspect. Cyberpunk Tokyo back-alley at night after heavy rain. Narrow alley framed by tall buildings covered in vertical neon signs glowing in magenta, cyan and yellow, reflecting on wet asphalt puddles. Atmospheric steam rising from manholes. Tangled power cables overhead. Slight fisheye distortion. Blade Runner 2049 aesthetic, dense, grungy, moody. Signs as abstract glowing shapes (not readable text). No characters, no people, no text, no letters. The alley floor in the lower third kept clean for walking sprites.
```

## 03 · Haunted Cemetery 🌕

```
Tall vertical phone wallpaper, 9:19.5 portrait aspect. Gothic Victorian cemetery at midnight under a huge full moon high in the sky. Crooked moss-covered tombstones in foreground leaning at dramatic angles. Bare twisted dead tree on the left silhouetted. Low cold mist rolling across the ground catching moonlight. Thin cloud wisps crossing the moon. Cold blue and silver palette with faint green ghostly undertones. Tim Burton cinematic, Edgar Allan Poe energy, painterly rendering. No characters, no people, no text. Lower third with open space between tombstones for ghost sprites to drift.
```

## 04 · Ice Aurora 🧊

```
Tall vertical phone wallpaper, 9:19.5 portrait aspect. Arctic night landscape. Jagged snow-covered mountain peaks in mid-ground against a deep navy sky. Magnificent aurora borealis dominating the upper two-thirds in vivid ribbons of teal green, electric cyan, violet and soft pink — highly detailed curling bands, not flat. Stars visible between aurora veils. Soft snow on ground in foreground with subtle sparkle. Snow surface reflects aurora glow. Epic National Geographic photography quality, hyperreal with slight painterly touch. No characters, no people, no text. Lower third with open snow area for sprite placement.
```

## 05 · Volcanic Dragon 🌋

```
Tall vertical phone wallpaper, 9:19.5 portrait aspect. Dramatic volcanic landscape at night. Tall active volcano in background center erupting glowing orange lava from summit, lava streams running down flanks. Sky thick with dark ash clouds illuminated red-orange by eruption. Foreground: jagged black volcanic rock with visible lava fissures glowing amber. Distant silhouettes of smaller peaks. Ember sparks floating upward through frame. Mordor meets Japanese woodblock print. Deep blacks, ember oranges, hints of crimson. Cinematic, intense. No characters, no people, no text. Sky mid-upper area clean for dragon sprite to circle later.
```

## 06 · Zen Koi Pond 🎍

```
Tall vertical phone wallpaper, 9:19.5 portrait aspect. Peaceful Japanese garden at dusk. Traditional stone lantern glowing warm amber on the left bank of a still pond. Bamboo grove background softly blurred. Water surface calm with gentle concentric ripples. A weeping cherry branch intrudes from the top corner with a few pink petals. Soft moonlight catches the water. Sumi-e ink painting style fused with modern photorealism, minimalist, tranquil. Muted teal-green water, warm golden lantern glow as focal point. No characters, no people, no text, no fish visible. Center-right pond area kept clean for koi sprites.
```

## 07 · Space Observatory 🌍

```
Tall vertical phone wallpaper, 9:19.5 portrait aspect. View from low Earth orbit at night. Earth's curved horizon fills the lower third, showing detailed blue oceans and green continents with wisps of cloud, edge glowing with thin atmospheric halo. Above: pitch black cosmic void scattered with thousands of stars and a diagonal glowing band of the Milky Way streaking across the upper half. Subtle nebula purples and pinks in far distance. NASA hyperrealistic photography aesthetic, cinematic awe. No characters, no people, no text, no spacecraft visible. Clean space above Earth's horizon for astronaut and ISS sprites.
```

## 08 · Medieval Castle 🏰

```
Tall vertical phone wallpaper, 9:19.5 portrait aspect. Towering medieval castle perched on a rocky cliff at dusk. Multiple tall turrets with conical roofs, stone walls weathered, narrow lit arrow-slit windows glowing warm amber from within. Cliff drops dramatically to a misty valley below. Sky gradient from deep violet top to burning orange-red at horizon, scattered dark clouds. Crescent moon peeking through. Flags on towers hanging still. Lord of the Rings cinematic mood, painterly fantasy epic. No characters, no people, no text. Sky around the towers uncluttered so dragons and crows can be composited flying.
```

## 09 · Coral Reef Kingdom 🪸

```
Tall vertical phone wallpaper, 9:19.5 portrait aspect. Underwater tropical coral reef, sunlight filtering down from above in god-ray shafts. Massive vibrant coral formations — pink elkhorn, orange brain coral, purple sea fans, yellow tube corals — rising like a fantasy skyline from sandy floor. Water crystal clear turquoise in foreground shifting to deep indigo far background. Caustic light patterns shimmering on seabed. A few tiny bubbles. Feels like Disney meets Avatar Pandora. Rich saturated color. No characters, no people, no text, no visible fish. Mid-water column empty so manta ray and fish sprites can swim through.
```

## 10 · Fairy Garden 🧚

```
Tall vertical phone wallpaper, 9:19.5 portrait aspect. Enchanted magical garden at twilight. Giant oversized glowing flowers in soft pastels — pink peonies, golden daffodils, purple bellflowers — emitting gentle bioluminescent light. Mushroom rings with tiny glowing caps. Tall grass blades catch the last light. Low mist drifts, catching fairy-dust sparkles. Warm lavender-pink-rose sky fading to deep twilight purple. Soft painterly rendering, Studio Ghibli meets Brian Froud. Magical and dreamlike. No characters, no people, no text. Center area between flowers kept open for fairy sprites to dance.
```

---

## Processing pipeline

Once images are generated in Gemini:

1. Download each image to `C:/Users/lalo/OneDrive/Escritorio/wallpapers/<concept_slug>/`
2. Patch watermark in bottom-right (same pattern as `process_aquarium_v2.py`)
3. Downscale to 1080×2340 WebP (full) + 540×1170 WebP (preview)
4. Upload to Supabase `wallpaper-images` bucket as `<slug>.webp` + `<slug>_preview.webp`
5. Add to `dynamic_catalog.json` with NEW badge, FANTASY category, `glowColor` matching palette
6. Commit to repo, rebuild AAB, release

**Estimated time per concept (end-to-end)**: 10-15 min once the image is approved.
