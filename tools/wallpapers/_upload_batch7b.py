"""Batch upload the 2nd wave (7 scenes) from ia_contenido_pipeline (HIDDEN).
New Codex naming: <pfx>_solofondo.png / <pfx>_personaje_final.png (cleaned) /
<pfx>_wallpaper_estatico_final.png (cleaned). Params from README/METADATA.
"""
from pathlib import Path
from _upload_scene_generic import upload_scene

BASE = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar")

SCENES = [
    dict(sid="jack_colina_calabazas_parallax", folder="jack_colina_calabazas", pfx="jk",
         bg_pf=0.06, near_pf=0.42, glow="#C77DFF", cat="cartoon",
         title={"es": "El lamento del Rey Calabaza", "en": "The Pumpkin King's Lament"},
         name="El lamento del Rey Calabaza",
         desc="Sobre la colina espiral, Jack escucha una pregunta que solo la luna parece entender.",
         tags=["jack", "skellington", "nightmare", "halloween", "burton", "luna", "colina", "parallax", "spooky"]),
    dict(sid="jack_sally_halloween_town_parallax", folder="jack_sally_halloween_town", pfx="js",
         bg_pf=0.06, near_pf=0.36, glow="#C77DFF", cat="cartoon",
         title={"es": "Todos en Halloween Town", "en": "All of Halloween Town"},
         name="Todos en Halloween Town",
         desc="Una ciudad entera despierta cuando las calabazas comienzan a sonreir.",
         tags=["jack", "sally", "halloween", "town", "nightmare", "burton", "parallax", "spooky"]),
    dict(sid="johnny_bravo_guitarra_parallax", folder="johnny_bravo_guitarra", pfx="jb",
         bg_pf=0.10, near_pf=0.72, glow="#FF2C9C", cat="cartoon",
         title={"es": "Johnny Bravo: Rock total", "en": "Johnny Bravo: Total Rock"},
         name="Johnny Bravo: Rock total",
         desc="Copete perfecto, guitarra rosa y suficiente actitud para iluminar todo el escenario.",
         tags=["johnnybravo", "johnny", "bravo", "cartoon", "rock", "guitarra", "retro", "parallax"]),
    dict(sid="motoratones_villanos_invasion_parallax", folder="motoratones_villanos_invasion", pfx="mv",
         bg_pf=0.08, near_pf=0.55, glow="#38D89F", cat="cartoon",
         title={"es": "Motoratones: los villanos", "en": "Biker Mice: the Villains"},
         name="Motoratones: los villanos",
         desc="Limburger y sus secuaces Plutarkianos planean apoderarse de la Tierra.",
         tags=["motoratones", "bikermice", "marte", "villanos", "limburger", "plutarkianos", "retro", "parallax", "90s"]),
    dict(sid="pez_conserje_fondo_bikini_parallax", folder="pez_conserje_fondo_bikini", pfx="pc",
         bg_pf=0.08, near_pf=0.68, glow="#22CDE4", cat="cartoon",
         title={"es": "Turno submarino", "en": "Underwater Shift"},
         name="Turno submarino",
         desc="La ciudad todavia duerme, pero alguien ya esta limpiando el desastre.",
         tags=["pez", "conserje", "submarino", "fondo", "caricatura", "parallax", "oceano", "nocturno"]),
    dict(sid="sedusa_noir_townsville_parallax", folder="sedusa_noir_townsville", pfx="sd",
         bg_pf=0.08, near_pf=0.66, glow="#A90F38", cat="cartoon",
         title={"es": "Sedusa: Noche de engano", "en": "Sedusa: Night of Deceit"},
         name="Sedusa: Noche de engano",
         desc="Cabello vivo, lluvia de neon y una joya demasiado perfecta para ignorarla.",
         tags=["sedusa", "powerpuff", "chicas", "superpoderosas", "townsville", "villana", "noir", "parallax"]),
    dict(sid="vaca_pollo_granja_parallax", folder="vaca_pollo_granja", pfx="vp",
         bg_pf=0.08, near_pf=0.65, glow="#F5B43A", cat="cartoon",
         title={"es": "Vaca y Pollo: Caos en la granja", "en": "Cow and Chicken: Farm Chaos"},
         name="Vaca y Pollo: Caos en la granja",
         desc="Una cubeta, dos hermanos y ninguna posibilidad de llegar limpios.",
         tags=["vaca", "pollo", "cowandchicken", "cartoon", "granja", "comedia", "hermanos", "parallax", "90s"]),
]

results = []
for s in SCENES:
    pfx = s["pfx"]
    cfg = {
        "scene_id": s["sid"], "src_dir": str(BASE / s["folder"]),
        "background_file": f"{pfx}_solofondo.png",
        "bg": {"z": 0, "parallax": s["bg_pf"], "scale": 1.05},
        "layers": [{"key": "subject", "file": f"{pfx}_personaje_final.png",
                    "z": 10, "parallax": s["near_pf"], "scale": 1.0, "bob": [2.5, 6.0]}],
        "static_file": f"{pfx}_wallpaper_estatico_final.png",
        "particles": [], "cycles": [], "sprites": [],
        "title": s["title"], "tags": s["tags"], "category_semantic": s["cat"],
        "glow": s["glow"], "name": s["name"], "desc_plain": s["desc"], "desc_rich": None,
        "featured": False, "published": False,
    }
    try:
        upload_scene(cfg); results.append((s["sid"], "OK"))
    except Exception as e:
        results.append((s["sid"], f"ERROR: {e}")); print(f"!!! {s['sid']} FALLO: {e}")

print("\n" + "=" * 60 + "\nRESUMEN:")
for sid, st in results:
    print(f"  {sid:42} {st}")
