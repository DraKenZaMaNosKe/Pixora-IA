"""Batch upload the 7 remaining ia_contenido_pipeline scenes (HIDDEN).
Params extracted from each scene's README + METADATA (Codex handoff).
Uses cleaned assets: *_personaje_v2_final.png + *_wallpaper_estatico_v2_final.png.
"""
from pathlib import Path
from _upload_scene_generic import upload_scene

BASE = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar")

EMBERS = [{"kind": "embers", "params": {
    "count": 20, "speed": 0.3, "color": "#FF8A24", "min_size": 1.0, "max_size": 3.5}}]

SCENES = [
    dict(scene_id="girasoles_jarron_parallax", folder="girasoles_jarron", pfx="gj",
         bg_pf=0.08, near_pf=0.48, name="Girasoles",
         title={"es": "Girasoles", "en": "Sunflowers"}, glow="#FFD100", cat="art",
         desc="El sol, cortado y en un jarron - girasoles al estilo Van Gogh.",
         tags=["girasoles", "sunflowers", "vangogh", "oleo", "bodegon", "azul", "amarillo", "arte", "parallax", "classic"],
         particles=[]),
    dict(scene_id="golfo_reina_bella_notte_parallax", folder="golfo_reina_bella_notte", pfx="gr",
         bg_pf=0.08, near_pf=0.62, name="Bella Notte",
         title={"es": "Bella noche", "en": "Bella Notte"}, glow="#FFC15A", cat="cartoon",
         desc="Dos mundos se encuentran sobre un plato de espagueti y una noche iluminada por la luna.",
         tags=["golfo", "tramp", "reina", "lady", "bella notte", "espagueti", "romance", "perritos", "clasico", "luna", "parallax"],
         particles=[]),
    dict(scene_id="jack_starry_parallax", folder="jack_skellington_starry", pfx="js",
         bg_pf=0.12, near_pf=0.62, name="Jack Skellington",
         title={"es": "Jack Skellington", "en": "Jack Skellington"}, glow="#C77DFF", cat="cartoon",
         desc="Jack bajo un cielo estrellado al estilo Noche Estrellada.",
         tags=["jack", "skellington", "nightmare", "halloween", "vangogh", "starrynight", "burton", "parallax", "spooky"],
         particles=[]),
    dict(scene_id="johnny_goro_parallax", folder="johnny_cage_goro", pfx="jg",
         bg_pf=0.10, near_pf=0.68, name="Johnny Cage vs Goro",
         title={"es": "Johnny Cage vs Goro", "en": "Johnny Cage vs Goro"}, glow="#FF4500", cat="gaming",
         desc="Duelo en la arena: Johnny Cage frente al principe Goro.",
         tags=["johnnycage", "goro", "mortalkombat", "mk", "fight", "boss", "arena", "parallax", "accion", "gaming"],
         particles=EMBERS),
    dict(scene_id="looney_tunes_clasicos_parallax", folder="looney_tunes_clasicos", pfx="lt",
         bg_pf=0.10, near_pf=0.68, name="Caos clasico animado",
         title={"es": "Caos clasico animado", "en": "Classic Cartoon Chaos"}, glow="#16C7FF", cat="cartoon",
         desc="Cinco personalidades, una sola regla: cuando empieza el caos, nadie se queda quieto.",
         tags=["looney", "tunes", "clasico", "caricatura", "warner", "retro", "parallax", "grupo"],
         particles=[]),
    dict(scene_id="mowgli_baloo_parallax_v2", folder="mowgli_baloo", pfx="mb",
         bg_pf=0.10, near_pf=0.58, name="Mowgli y Baloo",
         title={"es": "Mowgli y Baloo", "en": "Mowgli & Baloo"}, glow="#FFB703", cat="movies",
         desc="Un abrazo entre dos amigos que encontraron familia en el lugar mas inesperado.",
         tags=["mowgli", "baloo", "junglebook", "selva", "amistad", "aventura", "kipling", "parallax", "familia", "cine"],
         particles=[]),
    dict(scene_id="smeagol_anillo_parallax", folder="smeagol_gollum", pfx="sg",
         bg_pf=0.08, near_pf=0.38, name="Smeagol",
         title={"es": "Smeagol", "en": "Gollum"}, glow="#FFD700", cat="movies",
         desc="El anillo lo es todo... mi tesoro.",
         tags=["smeagol", "gollum", "anillo", "lotr", "tolkien", "cueva", "fantasy", "precious", "parallax", "oscuro"],
         particles=[]),
]

results = []
for s in SCENES:
    pfx = s["pfx"]
    cfg = {
        "scene_id": s["scene_id"],
        "src_dir": str(BASE / s["folder"]),
        "background_file": f"{pfx}_solofondo_v2.png",
        "bg": {"z": 0, "parallax": s["bg_pf"], "scale": 1.05},
        "layers": [{"key": "subject", "file": f"{pfx}_personaje_v2_final.png",
                    "z": 10, "parallax": s["near_pf"], "scale": 1.0, "bob": [2.5, 6.0]}],
        "static_file": f"{pfx}_wallpaper_estatico_v2_final.png",
        "particles": s["particles"], "cycles": [], "sprites": [],
        "title": s["title"], "tags": s["tags"], "category_semantic": s["cat"],
        "glow": s["glow"], "name": s["name"], "desc_plain": s["desc"], "desc_rich": None,
        "featured": False, "published": False,   # OCULTO
    }
    try:
        r = upload_scene(cfg)
        results.append((s["scene_id"], "OK"))
    except Exception as e:
        results.append((s["scene_id"], f"ERROR: {e}"))
        print(f"!!! {s['scene_id']} FALLO: {e}")

print("\n" + "=" * 60)
print("RESUMEN DEL BATCH:")
for sid, st in results:
    print(f"  {sid:38} {st}")
