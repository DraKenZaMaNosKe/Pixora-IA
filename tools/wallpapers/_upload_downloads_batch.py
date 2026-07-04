"""Upload all Downloads/*.jpg + *.png as panoramic wallpapers.

33 imagenes: 12 PNG Gemini (4128x1024, watermark ya limpiado) +
21 JPG Grok (1792x1008, sin watermark).

Todos suben como type='panoramic' + category='PANORAMIC' con badge NUEVO.
Pixora los detecta como panoramicos y panea horizontalmente en el home.
"""
import re
import shutil
import sys
import urllib.request
from pathlib import Path
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
SRC_DIR = Path(r"C:/Users/lalo/Downloads")
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/downloads_uploaded_2026_07_04")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_downloads_batch")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)

# Mapping filename -> ID + metadata (based on prompts que le pase a Eduardo)
WALLPAPERS = [
    # === 12 GEMINI (4128x1024) ===
    {"src": "bowser_castle.png", "id": "pano_bowser_castle", "name": "Castillo de Bowser", "description": "Castillo oscuro de Bowser con ventanas en forma de calavera brillando rojas, foso de lava, plataformas colgantes con fire bars y Thwomps guardando la entrada. Cielo tormentoso con relampagos.", "glow": "#DC2626", "tags": ["videojuegos", "mario", "bowser", "castillo", "panoramica", "lava"]},
    {"src": "chipchipbeach.png", "id": "pano_cheep_cheep_beach", "name": "Cheep Cheep Beach", "description": "Escena submarina de Cheep Cheep Beach de Super Mario World con Mario nadando entre bancos de Cheep Cheeps rojos, tuberias sumergidas, corales en paleta Nintendo brillante y rayos de sol atravesando el agua.", "glow": "#0EA5E9", "tags": ["videojuegos", "mario", "cheep_cheep", "playa", "panoramica", "submarino"]},
    {"src": "dark_world_zelda.png", "id": "pano_dark_world_zelda", "name": "Dark World Zelda", "description": "Dark World de A Link to the Past — paisaje morado retorcido con arboles nudosos, islas de roca flotante, cielo rojo sangre con nubes ominosas y la Piramide del Poder de Ganon en la distancia.", "glow": "#7C3AED", "tags": ["videojuegos", "zelda", "dark_world", "snes", "panoramica", "fantasia_oscura"]},
    {"src": "goros_lair.png", "id": "pano_goros_lair_mk", "name": "Guarida de Goro", "description": "Goro's Lair de Mortal Kombat 11 fotorrealista — sala del trono subterranea tallada en obsidiana con Goro Shokan sobre trono de calaveras, cadenas con cadaveres colgando y antorchas iluminando el rojo brutal.", "glow": "#EF4444", "tags": ["videojuegos", "mortalkombat", "goro", "arena", "panoramica", "oscuro"]},
    {"src": "hyrule_castle.png", "id": "pano_hyrule_castle_snes", "name": "Castillo de Hyrule SNES", "description": "Castillo de Hyrule de A Link to the Past — fortaleza medieval oscura con simbolo de la Trifuerza sobre la puerta, pedestal de la Master Sword en bosque sagrado y silueta de Ganon en el Dark World reflejado.", "glow": "#F59E0B", "tags": ["videojuegos", "zelda", "hyrule", "snes", "panoramica", "medieval"]},
    {"src": "hyrule_field.png", "id": "pano_hyrule_field_oot", "name": "Campo de Hyrule OoT", "description": "Vasto Campo de Hyrule de Ocarina of Time al atardecer con Link sobre Epona galopando, Castillo de Hyrule iluminado por luz dorada al fondo, Death Mountain humeando y Rancho Lon Lon visible.", "glow": "#FBBF24", "tags": ["videojuegos", "zelda", "hyrule", "ocarina", "panoramica", "campo"]},
    {"src": "mario_kard_rainbow_road.png", "id": "pano_rainbow_road_mk", "name": "Rainbow Road Mario Kart", "description": "Rainbow Road iconico de Mario Kart flotando en el espacio, pista arcoiris translucida curvando entre estrellas, Mario en kart rojo derrapando con chispas y Bowser persiguiendo. Planetas y galaxias al fondo.", "glow": "#EC4899", "tags": ["videojuegos", "mario_kart", "rainbow_road", "espacio", "panoramica", "colorido"]},
    {"src": "nethereal_mk10.png", "id": "pano_netherrealm_mk10", "name": "Netherrealm MK X", "description": "Netherrealm de Mortal Kombat X — pais apocaliptico rojo sangre con almas condenadas crucificadas, rios de lava, fortaleza de Shinnok sobre pico volcanico, ceniza cayendo desde cielo carmesi.", "glow": "#B91C1C", "tags": ["videojuegos", "mortalkombat", "netherrealm", "infierno", "panoramica", "epico"]},
    {"src": "peach_castle.png", "id": "pano_peach_castle_64", "name": "Castillo de Peach", "description": "Castillo de Peach de Super Mario 64 en luz dorada de la tarde — castillo rosa con vitral de rosa, foso reflejando el castillo, colinas verdes con flores y Lakitu con camara flotando en el cielo.", "glow": "#F472B6", "tags": ["videojuegos", "mario", "peach", "castillo", "panoramica", "n64"]},
    {"src": "thepit.png", "id": "pano_the_pit_mk", "name": "The Pit MK", "description": "The Pit stage de Mortal Kombat — puente de piedra antigua sobre abismo con estacas de madera, luna llena tras nubes, siluetas de espectadores en los acantilados, Scorpion y Sub-Zero en pose de pelea.", "glow": "#9CA3AF", "tags": ["videojuegos", "mortalkombat", "the_pit", "arena", "panoramica", "luna"]},
    {"src": "yoshi_island.png", "id": "pano_yoshi_island", "name": "Yoshi's Island", "description": "Paraiso tropical de Yoshi's Island — Yoshi verde sobre colina bajo cielo azul con nubes Nintendo, plantas Piranha asomandose, bloques flotantes, cascadas entre palmeras y montania volcanica al fondo.", "glow": "#22C55E", "tags": ["videojuegos", "yoshi", "isla", "tropical", "panoramica", "cheerful"]},
    {"src": "zelda_dungeon.png", "id": "pano_zelda_nes_dungeon", "name": "Zelda NES Dungeon", "description": "Recreacion pixel art 8-bit del primer dungeon de Zelda NES — corredores de piedra oscura con Keese bats rojos volando, Stalfos azules en las puertas, cofre dorado brillando y Link en tunica verde.", "glow": "#84CC16", "tags": ["videojuegos", "zelda", "nes", "pixel_art", "panoramica", "retro"]},

    # === 21 GROK (1792x1008) ===
    {"src": "aldea_meviebal.jpg", "id": "pano_aldea_medieval_pixel", "name": "Aldea Medieval Pixel Art", "description": "Aldea medieval pixel art 32-bit al atardecer dorado — casas techo de paja con luz calida interior, camino empedrado serpenteando, castillo en silueta contra cielo naranja-rosa, granjero con linterna.", "glow": "#F59E0B", "tags": ["pixel_art", "medieval", "aldea", "panoramica", "atardecer", "retro"]},
    {"src": "bosque_encantado.jpg", "id": "pano_bosque_pixel_encantado", "name": "Bosque Encantado Pixel", "description": "Bosque encantado pixel art 32-bit al anochecer — hongos brillantes en cyan y magenta esparcidos, luciernagas en calidos racimos, ciervo con astas luminosas en claro, luna entre robles antiguos.", "glow": "#A78BFA", "tags": ["pixel_art", "bosque", "encantado", "panoramica", "magia", "noche"]},
    {"src": "calle_con_niebla.jpg", "id": "pano_silent_hill_calle", "name": "Calle de Silent Hill", "description": "Calle principal desierta de Silent Hill al crepusculo — coches oxidados abandonados, columpios oxidados en parque infantil crujiendo, niebla blanca espesa, cartel rojo brillante, Pyramid Head en la distancia.", "glow": "#DC2626", "tags": ["videojuegos", "silent_hill", "niebla", "horror", "panoramica", "abandonado"]},
    {"src": "castillo_dimitrescu.jpg", "id": "pano_castillo_dimitrescu_re8", "name": "Castillo Dimitrescu RE8", "description": "Castillo Dimitrescu de Resident Evil Village — castillo gotico rumano en montania nevada, luna llena, silueta alta de Lady Dimitrescu con sombrero y vestido en balcon, cuervos volando entre torres.", "glow": "#9333EA", "tags": ["videojuegos", "resident_evil", "castillo", "dimitrescu", "panoramica", "gotico"]},
    {"src": "coruscat_templojedy.jpg", "id": "pano_coruscant_jedi", "name": "Coruscant Templo Jedi", "description": "Coruscant al atardecer de las precuelas Star Wars — metropolis vertical infinita, Templo Jedi con cinco spires prominente al centro, trafico de speeders como rayos luminosos, Star Destroyer en el cielo.", "glow": "#F59E0B", "tags": ["peliculas", "star_wars", "coruscant", "jedi", "panoramica", "sci_fi"]},
    {"src": "endor_atAt.jpg", "id": "pano_endor_atat", "name": "Endor con AT-AT", "description": "Luna forestal de Endor con AT-AT walkers marchando entre secuoyas gigantes, aldea Ewok visible en las copas, niebla del suelo, stormtroopers en speeder bikes zigzagueando, luz dorada de la tarde.", "glow": "#84CC16", "tags": ["peliculas", "star_wars", "endor", "atat", "panoramica", "bosque"]},
    {"src": "fabrica_de_puertas.jpg", "id": "pano_fabrica_puertas_monsters", "name": "Fabrica de Puertas Monsters Inc", "description": "Fabrica Monsters Inc con cintas transportadoras interminables cargando miles de puertas coloridas de dormitorios, iluminacion industrial calida amarilla y azul, ventanas gigantes al horizonte de fantasia.", "glow": "#3B82F6", "tags": ["peliculas", "monsters_inc", "fabrica", "puertas", "panoramica", "pixar"]},
    {"src": "goroslair.jpg", "id": "pano_goros_lair_grok", "name": "Guarida de Goro (Grok)", "description": "Guarida de Goro alternativa — sala subterranea de fuego y sangre con obsidiana negra, cadenas colgando del techo con esqueletos, antorchas en llamas creando sombras dramaticas, tono brutal epico.", "glow": "#B91C1C", "tags": ["videojuegos", "mortalkombat", "goro", "arena", "panoramica", "brutal"]},
    {"src": "himalaya_yeti.jpg", "id": "pano_himalaya_yeti_monsters", "name": "Himalaya de Monsters Inc", "description": "Paisaje del Himalaya de Monsters Inc — aldea de Yetis con cabanias de hielo, conos de nieve coloridos esparcidos, personaje Yeti fuera de su cabana con cono, tormenta de nieve distante, luz de hogar calida.", "glow": "#67E8F9", "tags": ["peliculas", "monsters_inc", "yeti", "himalaya", "panoramica", "nieve"]},
    {"src": "jungla_.jpg", "id": "pano_predator_jungla", "name": "Jungla del Predator", "description": "Densa selva de Predator 1987 — jungla humeda al anochecer con niebla entre kapok gigantes, pequenio puesto de comandos en claro con sacos y armas, distorsion optica del camuflaje del Predator entre las copas.", "glow": "#84CC16", "tags": ["peliculas", "predator", "jungla", "panoramica", "suspenso", "cinema"]},
    {"src": "lago_toluca.jpg", "id": "pano_lago_toluca_sh2", "name": "Lago Toluca Silent Hill 2", "description": "Lago Toluca al anochecer de Silent Hill 2 — pequeno bote de remos flotando en agua negra imposiblemente quieta, niebla espesa en las orillas, arboles muertos en la orilla lejana, hotel historico en la niebla.", "glow": "#94A3B8", "tags": ["videojuegos", "silent_hill", "lago", "toluca", "panoramica", "melancolico"]},
    {"src": "mansion_epenser.jpg", "id": "pano_spencer_mansion_re1", "name": "Mansion Spencer RE1", "description": "Vista panoramica exterior de la Mansion Spencer de Resident Evil 1 a medianoche durante tormenta — arquitectura colonial gotica con jardines invadidos, ventana iluminada en segundo piso, Hummer STARS abandonado.", "glow": "#7C2D12", "tags": ["videojuegos", "resident_evil", "mansion", "spencer", "panoramica", "horror"]},
    {"src": "mustafar_riosdelava.jpg", "id": "pano_mustafar_lava", "name": "Mustafar Rios de Lava", "description": "Planeta volcanico Mustafar de Revenge of the Sith — rios de lava entre islas volcanicas negras, castillo de Darth Vader silueteado bajo cielo rojo, plataformas mineras suspendidas, ruinas de templo Sith.", "glow": "#DC2626", "tags": ["peliculas", "star_wars", "mustafar", "lava", "panoramica", "sith"]},
    {"src": "nave_planetaalienigena.jpg", "id": "pano_nave_alien_pixel", "name": "Nave sobre Planeta Alienigena", "description": "Nave espacial pequenia pixel art 16-bit silueteada contra planeta alienigena masivo con oceanos turquesa y continentes violeta, dos soles poniendose, cinturon de asteroides, nebulosa rosa y azul al fondo.", "glow": "#22D3EE", "tags": ["pixel_art", "sci_fi", "espacio", "nave", "panoramica", "planeta"]},
    {"src": "netherealm.jpg", "id": "pano_netherrealm_grok", "name": "Netherrealm (Grok)", "description": "Netherrealm alternativo — reino demoniaco con fortaleza volcanica al fondo, rios de lava, portal de fuego violeta, arquitectura hueso y obsidiana, atmosfera apocaliptica cinematica.", "glow": "#B91C1C", "tags": ["videojuegos", "mortalkombat", "netherrealm", "infierno", "panoramica", "demonic"]},
    {"src": "onsen_bajo_nevada.jpg", "id": "pano_onsen_nevado", "name": "Onsen Bajo Nevada", "description": "Onsen tradicional japones en bosque nevado en hora azul — vapor densa saliendo del agua turquesa, nieve cayendo suavemente, luz amarilla de linternas de ryokan de madera, zorro de dos colas observando.", "glow": "#67E8F9", "tags": ["anime", "japon", "onsen", "invierno", "panoramica", "ghibli"]},
    {"src": "other_world.jpg", "id": "pano_otherworld_sh", "name": "Otherworld Silent Hill", "description": "Version Otherworld de Silent Hill — paredes de cage metalico oxidadas con manchas de sangre, pisos de cadena sobre oscuridad infinita, maniquies mutilados colgando, luces rojas de emergencia parpadeando.", "glow": "#DC2626", "tags": ["videojuegos", "silent_hill", "otherworld", "horror", "panoramica", "industrial"]},
    {"src": "rpd_residentevil.jpg", "id": "pano_rpd_re2", "name": "RPD Raccoon City RE2", "description": "Estacion de Policia de Raccoon City RPD de Resident Evil 2 Remake — fachada art deco de piedra con columnas, llamas de coches policiacos en las calles, zombies arrastrandose, Leon Kennedy en la entrada.", "glow": "#EAB308", "tags": ["videojuegos", "resident_evil", "raccoon_city", "rpd", "panoramica", "zombie"]},
    {"src": "sala_de_trofeos.jpg", "id": "pano_predator_trofeos", "name": "Sala de Trofeos Predator", "description": "Interior nave del cazador Predator — paredes cubiertas de calaveras alienigenas y humanas como trofeos, calavera xenomorfo como pieza central, Predator sin mascara ante mapa holografico de Tierra, iluminacion roja.", "glow": "#DC2626", "tags": ["peliculas", "predator", "trofeos", "sci_fi_horror", "panoramica", "cinema"]},
    {"src": "tattoine.jpg", "id": "pano_tatooine_soles", "name": "Tatooine con Dos Soles", "description": "Tatooine al atardecer con los dos soles iconicos poniendose sobre dunas, Luke Skywalker en tunica Jedi silueteado, vaporadores en la distancia, huellas de X-wing en la arena, jawa sandcrawler diminuto.", "glow": "#F59E0B", "tags": ["peliculas", "star_wars", "tatooine", "desierto", "panoramica", "iconico"]},
    {"src": "thepit.jpg", "id": "pano_the_pit_mk_grok", "name": "The Pit MK (Grok)", "description": "The Pit stage alternativo de Mortal Kombat — puente de piedra sobre abismo con estacas, luna llena tras nubes tormenta, siluetas de espectadores en las cimas, atmosfera epica de torneo.", "glow": "#9CA3AF", "tags": ["videojuegos", "mortalkombat", "the_pit", "arena", "panoramica", "epico"]},
]


def put(remote, body, ct="image/webp"):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}",
        data=body, method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"    PUT {remote} -> {r.status} ({len(body):,} B)")


def encode_full(src, dst, quality=88):
    img = Image.open(src).convert("RGB")
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes(), img


def encode_preview(src, dst, max_side=720, quality=82):
    img = Image.open(src).convert("RGB")
    img.thumbnail((max_side, max_side), Image.LANCZOS)
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes()


print("=" * 60)
print(f"Downloads batch — {len(WALLPAPERS)} wallpapers panoramicos")
print("=" * 60)

conn = connect()
cur = conn.cursor()

for w in WALLPAPERS:
    src = SRC_DIR / w["src"]
    if not src.exists():
        print(f"\n[SKIP] {w['id']}: NO existe {src.name}")
        continue
    print(f"\n[PANO] {w['id']}  {w['name']}")
    shutil.copy2(src, BACKUP / w["src"])

    full_remote = f"{w['id']}.webp"
    prev_remote = f"{w['id']}_preview.webp"
    full_body, img = encode_full(src, WORK / full_remote)
    prev_body = encode_preview(src, WORK / prev_remote)
    put(full_remote, full_body)
    put(prev_remote, prev_body)

    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    sort = cur.fetchone()[0]

    cur.execute(
        """
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name,
            media_width, media_height
        ) VALUES (
            %s, %s, %s, 'panoramic'::wallpaper_type,
            'PANORAMIC'::wallpaper_category, %s,
            %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s,
            false, 0, true, true, 'Pixora Studio', %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description,
            tags=EXCLUDED.tags, image_path=EXCLUDED.image_path,
            preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color,
            media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
            daily_eligible=true,
            category='PANORAMIC'::wallpaper_category,
            updated_at=now()
        RETURNING id, sort_order;
        """,
        (
            w["id"], w["name"], w["description"], w["tags"],
            full_remote, prev_remote, len(full_body), len(prev_body),
            w["glow"], sort, img.width, img.height,
        ),
    )
    rid, rsort = cur.fetchone()
    print(f"    postgres: {rid}  sort={rsort}  {img.width}x{img.height}")

conn.commit()
cur.close()
conn.close()

print("\n" + "=" * 60)
print("FCM invalidate")
print("=" * 60)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _fcm_push import send_catalog_invalidate
print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")

print(f"\n[OK] Downloads batch ({len(WALLPAPERS)}) publicado")
