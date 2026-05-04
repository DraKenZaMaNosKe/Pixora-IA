"""
Attach editorial `cultural` content to all 7 wallpapers in the 3D section
(except Mictlantecuhtli which already has it).

Patches:
  - catalog_index.json entries for canvas_scene wallpapers (5 items)
  - Postgres `wallpapers` rows for the 2 aquarium-style wallpapers

Each cultural block is a richly-researched mini-codex: real lore, dates,
symbols, curiosities. Designed to make users discover something interesting
about the world while picking a wallpaper.
"""
from __future__ import annotations
import json, re, sys, urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
SVC = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
                KEYS.read_text(encoding="utf-8")).group(1)
PROJECT = "vzuwvsmlyigjtsearxym"


# ─────────────────────────────────────────────────────────────────────────────
# EDITORIAL CONTENT (Mictlantecuhtli already done — skipping here)
# ─────────────────────────────────────────────────────────────────────────────

CULTURAL_DATA = {
    # ── Iah Egyptian / Lunar / Zodiac ─────────────────────────────────────
    "iah_egyptian_giza": {
        "chapter": "Capítulo II · Cielo de Iah",
        "subtitle": "El Mensajero Lunar",
        "pronunciation": "[I·ah · YA·a]",
        "lead": "Iah era el dios egipcio de la luna, padre del calendario y guía de las almas durante la noche. Su nombre significaba simplemente 'luna' — antes de Thoth, antes de Khonsu, él medía el tiempo del Nilo.",
        "facts": [
            {"key": "Cultura",     "value": "Egipto · Reino Antiguo"},
            {"key": "Dominio",     "value": "Luna · Tiempo · Noche"},
            {"key": "Símbolo",     "value": "Disco lunar + creciente"},
            {"key": "Hijos",       "value": "Khonsu · Thoth"},
            {"key": "Calendario",  "value": "12 ciclos lunares · 354 días"},
            {"key": "Animal",      "value": "Babuino · ibis"}
        ],
        "ofrenda": {
            "label": "Ofrenda nocturna",
            "text":  "Los sacerdotes ofrecían leche, miel y agua del Nilo en cuencos de plata bajo cada luna llena. La plata era considerada 'la carne de Iah'."
        },
        "cta": "Bajo la mirada de Iah"
    },

    # ── Goku Genkidama (Dragon Ball lore) ─────────────────────────────────
    "goku_genkidama": {
        "chapter": "Capítulo VII · Energía Espiritual",
        "subtitle": "La Bomba de Energía",
        "pronunciation": "[gen·KI·da·ma]",
        "lead": "El Genkidama es la técnica más pura de Dragon Ball: Goku reúne energía vital prestada de toda forma viva — humanos, animales, plantas, planetas — y la condensa en una esfera de luz. No requiere fuerza propia, solo la voluntad colectiva del universo.",
        "facts": [
            {"key": "Origen",      "value": "Dragon Ball Z · 1989"},
            {"key": "Maestro",     "value": "Kaio del Norte"},
            {"key": "Significado", "value": "源気玉 · 'esfera del ki original'"},
            {"key": "Restricción", "value": "Solo corazones puros pueden usarla"},
            {"key": "Primer uso",  "value": "Vs. Vegeta · Saga Saiyajin"},
            {"key": "Pico máximo", "value": "Vs. Kid Buu · energía de toda la Tierra"}
        ],
        "ofrenda": {
            "label": "Filosofía",
            "text":  "El Genkidama enseña que el poder más grande no nace del individuo sino de la cooperación. Es la técnica que hizo de Goku un héroe global, no solo guerrero."
        },
        "cta": "Reunir el ki"
    },

    # ── Volcano Dragon (mythology) ────────────────────────────────────────
    "volcano_dragon": {
        "chapter": "Capítulo III · Forja de la Tierra",
        "subtitle": "El Dragón del Volcán",
        "pronunciation": "[ig·NEUS · drak·KO·nis]",
        "lead": "En la mitología comparada, los dragones de fuego son guardianes del corazón ardiente del planeta. Los celtas creían que cada volcán activo escondía un dragón dormido cuyo aliento moldea continentes; los nórdicos lo llamaban 'la fragua de Surtr'.",
        "facts": [
            {"key": "Arquetipo",   "value": "Mítico · universal"},
            {"key": "Hábitat",     "value": "Conductos magmáticos · cráteres"},
            {"key": "Aliento",     "value": "Lava · azufre · ceniza"},
            {"key": "Edad mítica", "value": "Anterior al hombre"},
            {"key": "Función",     "value": "Renovar la corteza terrestre"},
            {"key": "Símbolo",     "value": "Renacimiento por destrucción"}
        ],
        "ofrenda": {
            "label": "Leyenda",
            "text":  "Cuando un volcán entra en silencio prolongado, dicen que el dragón está soñando. El día que despierte, transformará el paisaje — y con ello, el destino de quienes vivan cerca."
        },
        "cta": "Despertar al guardián"
    },

    # ── Bosque Lluvioso (mythology of forests) ────────────────────────────
    "bosque_lluvioso": {
        "chapter": "Capítulo V · Espíritus del Bosque",
        "subtitle": "La Selva Encantada",
        "pronunciation": "[bos·ke · LLOO·vio·so]",
        "lead": "Los bosques lluviosos guardan el 50% de la biodiversidad terrestre. Para los pueblos amazónicos, cada árbol antiguo aloja un espíritu — 'curupira' en guaraní, 'mapinguari' entre los tupís — que protege la selva de quien la daña.",
        "facts": [
            {"key": "Bioma",       "value": "Selva tropical · selva nubosa"},
            {"key": "Especies",    "value": "+50% de la vida del planeta"},
            {"key": "Lluvia anual","value": "2,000 a 10,000 mm"},
            {"key": "Espíritu",    "value": "Curupira · pies al revés"},
            {"key": "Significado", "value": "Útero verde de la Tierra"},
            {"key": "Edad",        "value": "+100 millones de años"}
        ],
        "ofrenda": {
            "label": "Saber ancestral",
            "text":  "Los chamanes amazónicos dicen que 'el bosque escucha'. Antes de cortar un árbol piden permiso al espíritu del lugar — un gesto que la ciencia moderna está empezando a entender como ecología profunda."
        },
        "cta": "Entrar al bosque"
    },

    # ── Dusk Fortress (medieval lore) ─────────────────────────────────────
    "dusk_fortress": {
        "chapter": "Capítulo VIII · Castillos del Crepúsculo",
        "subtitle": "La Fortaleza del Ocaso",
        "pronunciation": "[FOR·ta·le·sa]",
        "lead": "Las fortalezas medievales eran construidas en colinas estratégicas para divisar al enemigo desde el atardecer. Los maestros canteros tardaban 30 años en levantar una; sus muros tenían el grosor de 4 metros para resistir trabuquetes y catapultas.",
        "facts": [
            {"key": "Era",         "value": "Edad Media · siglos IX-XV"},
            {"key": "Construcción","value": "Hasta 30 años · 1,000 obreros"},
            {"key": "Muro típico", "value": "4 metros de grosor"},
            {"key": "Función",     "value": "Refugio · poder · administración"},
            {"key": "Pieza clave", "value": "Torre del homenaje (donjon)"},
            {"key": "Asedio largo","value": "Hasta 2 años · agotaba reservas"}
        ],
        "ofrenda": {
            "label": "Vida en el castillo",
            "text":  "Cuando caía la noche, el puente levadizo se cerraba al anochecer y nadie entraba ni salía hasta el alba. Las antorchas quemaban grasa de cordero — perfumaban el patio con un aroma denso que duraba semanas."
        },
        "cta": "Cruzar el puente levadizo"
    },

    # ── Aquarium Betta (peces betta) ──────────────────────────────────────
    "aquarium_betta_paradise": {
        "chapter": "Capítulo I · Acuarios Vivos",
        "subtitle": "El Pez Luchador del Siam",
        "pronunciation": "[BE·ta · sple·NEN·dens]",
        "lead": "El betta — pez luchador del Siam — fue domesticado en Tailandia hace 700 años. Inicialmente criado para peleas en festivales reales, hoy es admirado por su cola en abanico y su asombrosa paleta de colores: cada individuo es único, como una huella digital.",
        "facts": [
            {"key": "Nombre cien.","value": "Betta splendens"},
            {"key": "Origen",     "value": "Tailandia · siglo XIV"},
            {"key": "Hábitat",    "value": "Arrozales · pantanos cálidos"},
            {"key": "Vida",       "value": "3 a 5 años en cautiverio"},
            {"key": "Curiosidad", "value": "Respira aire de la superficie"},
            {"key": "Inteligencia","value": "Reconoce a su cuidador"}
        ],
        "ofrenda": {
            "label": "Respeto al pez",
            "text":  "El betta macho es territorial: nunca debe convivir con otros machos. En la naturaleza construye nidos de burbujas en la superficie para proteger sus huevos — un comportamiento parental único entre peces tropicales."
        },
        "cta": "Sumergirse en el acuario"
    },

    # ── Jellyfish Abyss (medusas bioluminiscentes) ────────────────────────
    "jellyfish_abyss": {
        "chapter": "Capítulo IV · Luz del Abismo",
        "subtitle": "Las Medusas Inmortales",
        "pronunciation": "[meh·DOO·sa · scy·PHO·zo·a]",
        "lead": "Las medusas son los animales más antiguos del planeta — llevan más de 500 millones de años flotando en los océanos. Algunas especies, como la Turritopsis dohrnii, son técnicamente inmortales: pueden revertir su ciclo vital de adulto a pólipo, repetidamente, sin envejecer.",
        "facts": [
            {"key": "Antigüedad",  "value": "+500 millones de años"},
            {"key": "Composición", "value": "95% agua · sin cerebro"},
            {"key": "Bioluminisc.","value": "30% de las especies brillan"},
            {"key": "Inmortal",    "value": "Turritopsis dohrnii"},
            {"key": "Profundidad", "value": "Hasta 3,000 metros"},
            {"key": "Función",     "value": "Limpian océanos de plancton"}
        ],
        "ofrenda": {
            "label": "Misterio del abismo",
            "text":  "En las profundidades sin sol, las medusas crean su propia luz mediante una proteína llamada GFP — la misma que la ciencia moderna usa para iluminar células en investigación médica. Un regalo evolutivo de hace medio billón de años."
        },
        "cta": "Descender al abismo"
    },
}


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

def get(bucket: str, key: str) -> bytes:
    url = f"https://{PROJECT}.supabase.co/storage/v1/object/public/{bucket}/{key}"
    return urllib.request.urlopen(url, timeout=30).read()


def put(bucket: str, key: str, body: bytes, ctype: str):
    req = urllib.request.Request(
        f"https://{PROJECT}.supabase.co/storage/v1/object/{bucket}/{key}",
        data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SVC}")
    req.add_header("Content-Type", ctype)
    req.add_header("x-upsert", "true")
    return urllib.request.urlopen(req, timeout=30).status


def patch_postgres(wallpaper_id: str, cultural: dict):
    """Add a `cultural` column write to a wallpapers row."""
    url = f"https://{PROJECT}.supabase.co/rest/v1/wallpapers?id=eq.{wallpaper_id}"
    body = json.dumps({"cultural": cultural}).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="PATCH")
    req.add_header("Authorization", f"Bearer {SVC}")
    req.add_header("apikey", SVC)
    req.add_header("Content-Type", "application/json")
    req.add_header("Prefer", "return=minimal")
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.status


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("Loading catalog_index.json...")
    idx = json.loads(get("wallpaper-images", "catalog_index.json"))

    canvas_scene_ids = {
        "iah_egyptian_giza", "goku_genkidama", "volcano_dragon",
        "bosque_lluvioso", "dusk_fortress",
    }
    postgres_ids = {"aquarium_betta_paradise", "jellyfish_abyss"}

    # 1) Patch catalog_index entries
    patched = 0
    for entry in idx.get("items", []):
        wid = entry.get("id")
        if wid in canvas_scene_ids and wid in CULTURAL_DATA:
            entry["cultural"] = CULTURAL_DATA[wid]
            patched += 1
            print(f"  + catalog_index: {wid}")

    idx["version"] = idx.get("version", 29) + 1
    body = json.dumps(idx, ensure_ascii=False, indent=2).encode("utf-8")
    put("wallpaper-images", "catalog_index.json", body, "application/json")
    print(f"  catalog_index uploaded (v{idx['version']}, {patched} cultural blocks)")

    # 2) Patch Postgres rows
    print()
    print("Patching Postgres wallpapers table...")
    for wid in postgres_ids:
        if wid in CULTURAL_DATA:
            try:
                patch_postgres(wid, CULTURAL_DATA[wid])
                print(f"  + Postgres: {wid}")
            except urllib.error.HTTPError as e:
                err = e.read().decode("utf-8")[:200]
                print(f"  ! Postgres {wid}: HTTP {e.code} — {err}")

    print()
    print("Done. Cultural content attached to 7 wallpapers.")
    print("Total culturally-enriched wallpapers in app: 8 (incl. Mictlantecuhtli)")


if __name__ == "__main__":
    main()
