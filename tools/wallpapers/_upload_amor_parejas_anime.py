"""Upload 4 anime-couple parallax canvas_scenes for the AMOR section.

Parejas:
  - Goku y Chichi   (Dragon Ball)   — hogar en la Montaña Paozu
  - Naruto y Hinata (Naruto)        — beso de otoño en Konoha
  - Haruka y Michiru (Sailor Moon)  — Sailor Uranus + Neptune
  - Vegeta y Bulma  (Dragon Ball Z) — atardecer saiyajin

FULL-FRAME LAYER approach (NOT bake-and-center like Marina):
  each `solopersonages` PNG is a full-frame 1080x1920 layer decomposed from
  the same composition as its `solofondo`. So we cover-fit BOTH the fondo
  and the subject IDENTICALLY to 1080x2340 (fondo → RGB opaque, subject →
  RGBA alpha-preserved) and give both the SAME scale (1.22). The subject
  stays pixel-aligned with the fondo automatically; parallax_factor=0.85 on
  the subject gives the 3D depth pop. Eduardo can nudge offset_x/y_px per
  couple in the sprite editor afterward.

Assets under C:/Users/lalo/Desktop/wallPapers_repo/nuevos/amor/parejas_anime/
"""
import json
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
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"
TARGET = (1080, 2340)

SRC_ROOT = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/amor/parejas_anime")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_amor_parejas")
if WORK.exists():
    shutil.rmtree(WORK)
WORK.mkdir(parents=True)

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)

# ============================================================
# Couples config
# ============================================================
COUPLES = [
    {
        "id": "goku_chichi_amor",
        "src": "gokuychichi",
        "fondo": "solofondo.png",
        "subject": "solopersonages.png",
        "flat": "gokuychichi_wallaperestatico.png",
        "title_es": "Goku y Chichi · Hogar en Paozu",
        "title_en": "Goku & Chichi · Home in Paozu",
        "glow": "#E8862E",
        "tags": ["amor", "goku", "chichi", "dragon_ball", "anime",
                 "pareja", "couple", "romance", "3d", "parallax"],
        "desc": (
            "Goku y Chichi se casaron cumpliendo una promesa que él hizo "
            "de niño sin entender qué era el matrimonio. Aquí, "
            "lejos de los torneos y las batallas, el guerrero más fuerte "
            "del universo abraza a la mujer que convirtió una montaña "
            "solitaria en un hogar. Al fondo, la casa de Paozu donde criaron a "
            "Gohan y Goten. Los corazones flotan sobre el valle: hasta el "
            "Saiyajin más poderoso descubrió que su mayor fuerza era "
            "su familia."
        ),
    },
    {
        "id": "naruto_hinata_amor",
        "src": "naruto",
        "fondo": "naruto_amor_solofondo.png",
        "subject": "naruto_solo_personages_sinfondo_amor.png",
        "flat": "naruto_amor_wallpaper_estatico.png",
        "title_es": "Naruto y Hinata · Beso de Otoño",
        "title_en": "Naruto & Hinata · Autumn Kiss",
        "glow": "#E0A82E",
        "tags": ["amor", "naruto", "hinata", "naruto_shippuden", "anime",
                 "pareja", "couple", "romance", "3d", "parallax"],
        "desc": (
            "Hinata amó a Naruto en silencio desde la academia, cuando "
            "nadie más creía en el niño del Zorro de Nueve Colas. "
            "Él tardó años en verla, hasta que ella "
            "arriesgó su vida para protegerlo. Bajo un árbol de hojas "
            "doradas, en el bosque de Konoha, por fin se besan mientras el "
            "otoño cae a su alrededor. De este amor nacieron Boruto y "
            "Himawari. El ninja más ruidoso de la aldea, por una vez, se "
            "queda sin palabras."
        ),
    },
    {
        "id": "haruka_michiru_amor",
        "src": "sailormoon",
        "fondo": "sailormoon_solofondo.png",
        "subject": "sailormoon_solopersonages.png",
        "flat": "salilor_moon_amor_pareja_wallpaperestatico.png",
        "title_es": "Haruka y Michiru · Viento y Marea",
        "title_en": "Uranus & Neptune · Wind and Tide",
        "glow": "#35C4B5",
        "tags": ["amor", "sailor_moon", "sailor_uranus", "sailor_neptune",
                 "haruka", "michiru", "anime", "magical_girl", "pareja",
                 "couple", "romance", "3d", "parallax"],
        "desc": (
            "Haruka Tenō (Sailor Uranus) y Michiru Kaiō (Sailor "
            "Neptune) son una de las parejas más queridas del anime: "
            "guardianas del viento y del mar que pelean espalda con espalda y "
            "se aman sin pedir permiso. Michiru toca el violín; Haruka "
            "corre carreras y pilota como el viento. Elegantes e inseparables, "
            "representaron un amor abierto en la televisión desde los "
            "años 90. Entre destellos violeta y aguamarina, dos fuerzas de "
            "la naturaleza que se pertenecen."
        ),
    },
    {
        "id": "vegeta_bulma_amor",
        "src": "vegetaybulma",
        "fondo": "solofondo.png",
        "subject": "solopersonages.png",
        "flat": "vegetaybulma_wallpaperestatico.png",
        "title_es": "Vegeta y Bulma · Atardecer Saiyajin",
        "title_en": "Vegeta & Bulma · Saiyan Sunset",
        "glow": "#E85A8A",
        "tags": ["amor", "vegeta", "bulma", "dragon_ball", "anime",
                 "pareja", "couple", "romance", "3d", "parallax"],
        "desc": (
            "El orgulloso Príncipe de los Saiyajin carga en brazos a "
            "Bulma, la científica más brillante de la Tierra, bajo un "
            "cielo de fuego y pétalos de cerezo. Vegeta jamás lo "
            "diría en voz alta —su orgullo no lo permite—, pero "
            "fue ella quien domó al guerrero que alguna vez quiso destruir "
            "el planeta. De ese choque de mundos nacieron Trunks y Bra. A veces "
            "el amor más fuerte empieza como el choque de dos rivales."
        ),
    },
    # ── Escenas adicionales (carpetas otra / otramas) ──────────────
    {
        "id": "goku_chichi_kinton_amor",
        "src": "gokuychichi/otra",
        "fondo": "solofondo.png",
        "subject": "solopersonages.png",
        "flat": "gokuychichi_wallpaperestatico.png",
        "title_es": "Goku y Chichi · Vuelo en la Nube",
        "title_en": "Goku & Chichi · Flight on the Nimbus",
        "glow": "#F2C230",
        "tags": ["amor", "goku", "chichi", "dragon_ball", "anime",
                 "pareja", "couple", "romance", "nube_voladora", "3d", "parallax"],
        "desc": (
            "La Nube Voladora (Kinton) solo carga a quien tiene el corazón "
            "puro — por eso Goku pudo montarla toda su vida. Aquí surca el "
            "cielo con Chichi a su lado, entre nubes de algodón, rumbo a "
            "casa. De niños se conocieron en una promesa inocente; de adultos "
            "comparten la misma nube dorada. Volar juntos, sin prisa, también "
            "es una forma de amar."
        ),
    },
    {
        "id": "haruka_michiru_rosas_amor",
        "src": "sailormoon/otra",
        "fondo": "solofondo.png",
        "subject": "solopersonages.png",
        "flat": "sailor_moon_pareja_wallpaperestatico.png",
        "title_es": "Haruka y Michiru · Jardín de Rosas",
        "title_en": "Haruka & Michiru · Rose Garden",
        "glow": "#E8637F",
        "tags": ["amor", "sailor_moon", "sailor_uranus", "sailor_neptune",
                 "haruka", "michiru", "anime", "magical_girl", "pareja",
                 "couple", "romance", "3d", "parallax"],
        "desc": (
            "Lejos de las batallas como Sailor Uranus y Neptune, Haruka y "
            "Michiru se roban un momento de calma entre rosas. Sin "
            "transformaciones ni enemigos: solo dos personas que eligieron "
            "cuidarse la una a la otra. Michiru, serena como el mar; Haruka, "
            "libre como el viento. Un jardín florecido para la pareja que "
            "enseñó a toda una generación que el amor no necesita permiso."
        ),
    },
    {
        "id": "serenity_endymion_amor",
        "src": "sailormoon/otramas",
        "fondo": "solofondo.png",
        "subject": "solopersonages.png",
        "flat": "salirmonn_wallpaperestatico_amor.png",
        "title_es": "Serenity y Endymion · Amor de la Luna",
        "title_en": "Serenity & Endymion · Moonlight Love",
        "glow": "#C9A227",
        "tags": ["amor", "sailor_moon", "usagi", "mamoru", "serenity",
                 "endymion", "tuxedo_mask", "anime", "magical_girl",
                 "pareja", "couple", "romance", "luna", "3d", "parallax"],
        "desc": (
            "La Princesa Serenity y el Príncipe Endymion —Usagi y Mamoru en "
            "esta vida— se aman a través de los siglos, la muerte y la "
            "reencarnación. Su amor nació en el antiguo Milenio de Plata, en "
            "el Reino de la Luna, y renace en el Tokio de hoy cada vez que se "
            "encuentran. Él se arrodilla ante ella bajo la luna creciente, "
            "como en un cuento que nunca termina. El romance más eterno del "
            "anime: dos almas destinadas a hallarse una y otra vez."
        ),
    },
]

SUBJECT_KEY = "pareja"


# ============================================================
# Storage helpers
# ============================================================
def put(bucket, remote, body, ct="image/webp"):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body, method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=180) as r:
        print(f"    PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


def put_json(bucket, remote, data):
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    put(bucket, remote, body, "application/json")


def get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=20) as r:
        return json.loads(r.read().decode("utf-8"))


# ============================================================
# Image helpers
# ============================================================
def _cover_geom(src, target=TARGET):
    tw, th = target
    sw, sh = src.size
    scale = max(tw / sw, th / sh)
    nw, nh = int(round(sw * scale)), int(round(sh * scale))
    resized = src.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    return resized.crop((left, top, left + tw, top + th))


def cover_fit_rgb(img, target=TARGET):
    """Cover-fit → flat RGB on black. For the opaque fondo + flat."""
    cropped = _cover_geom(img.convert("RGBA"), target)
    out = Image.new("RGB", target, (0, 0, 0))
    out.paste(cropped, mask=cropped.split()[3])
    return out


def cover_fit_rgba(img, target=TARGET):
    """Cover-fit preserving alpha. For the full-frame subject overlay —
    SAME geometry as cover_fit_rgb so subject stays aligned with fondo."""
    return _cover_geom(img.convert("RGBA"), target)


def encode_webp(img, out_path, quality=90):
    img.save(out_path, "WEBP", quality=quality, method=6)
    return out_path.read_bytes()


# ============================================================
# Main
# ============================================================
print("=" * 64)
print("Upload AMOR · 4 parejas anime parallax (canvas_scene)")
print("=" * 64)

# Load catalog_index once, mutate, write once at the end.
try:
    cat = get_json(IMG_BUCKET, "catalog_index.json")
except Exception:
    cat = {"version": 0, "items": []}

conn = connect()
cur = conn.cursor()

for c in COUPLES:
    sid = c["id"]
    src = SRC_ROOT / c["src"]
    print(f"\n{'-' * 64}\n[{sid}]  {c['title_es']}\n{'-' * 64}")

    fondo_p = src / c["fondo"]
    subj_p = src / c["subject"]
    flat_p = src / c["flat"]
    for p in (fondo_p, subj_p, flat_p):
        if not p.is_file():
            raise SystemExit(f"MISSING asset: {p}")

    # --- Bake ---
    print("  baking...")
    fondo_img = cover_fit_rgb(Image.open(fondo_p))
    fondo_body = encode_webp(fondo_img, WORK / f"{sid}_fondo.webp", quality=90)

    subj_img = cover_fit_rgba(Image.open(subj_p))
    subj_body = encode_webp(subj_img, WORK / f"{sid}_{SUBJECT_KEY}.webp", quality=92)

    flat_img = cover_fit_rgb(Image.open(flat_p))
    flat_body = encode_webp(flat_img, WORK / f"{sid}.webp", quality=88)
    prev = flat_img.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev_body = encode_webp(prev, WORK / f"{sid}_preview.webp", quality=85)

    # --- Upload ---
    print("  uploading to storage...")
    put(IMG_BUCKET, f"{sid}_fondo.webp", fondo_body)
    put(IMG_BUCKET, f"{sid}_{SUBJECT_KEY}.webp", subj_body)
    put(IMG_BUCKET, f"{sid}.webp", flat_body)
    put(IMG_BUCKET, f"{sid}_preview.webp", prev_body)

    url_bg = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{sid}_fondo.webp"
    url_subject = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{sid}_{SUBJECT_KEY}.webp"
    url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{sid}.webp"
    url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{sid}_preview.webp"

    title = {"es": c["title_es"], "en": c["title_en"]}

    # --- Spec JSON ---
    spec = {
        "schema_version": 1,
        "id": sid,
        "type": "canvas_scene",
        "title": title,
        "tags": c["tags"],
        "category": "anime",
        "featured": False,
        "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
        "image_layers": [
            {
                "key": "fondo", "url": url_bg, "z": 0,
                "parallax_factor": 0.0, "scroll_factor": 0.0,
                "scale": 1.22, "offset_x_px": 0, "offset_y_px": 0,
                "revision": 1,
            },
            {
                "key": SUBJECT_KEY, "url": url_subject, "z": 1,
                "parallax_factor": 0.85, "scroll_factor": 0.0,
                "scale": 1.22, "offset_x_px": 0, "offset_y_px": 0,
                "revision": 1,
            },
        ],
        "sprites": [],
        "particles": [],
        "events": [],
    }
    put_json(SCENES_BUCKET, f"{sid}.json", spec)

    # --- catalog_index entry ---
    entry = {
        "id": sid,
        "type": "canvas_scene",
        "schema": 1,
        "title": title,
        "preview_url": url_prev,
        "image_url": url_flat,
        "tags": c["tags"],
        "category": "anime",
        "featured": False,
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{sid}.json",
    }
    cat["items"] = [it for it in cat.get("items", []) if it.get("id") != sid]
    cat["items"].insert(0, entry)

    # --- Postgres ---
    print("  registering in Postgres...")
    cur.execute("DELETE FROM wallpapers WHERE id = %s;", (sid,))
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    sort = cur.fetchone()[0]
    cur.execute(
        """
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'static'::wallpaper_type, 'SCENES'::wallpaper_category, %s,
            %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, false, 0,
            true, false, %s, %s, %s
        )
        RETURNING id;
        """,
        (
            sid, c["title_es"], c["desc"], c["tags"],
            f"{sid}.webp", f"{sid}_preview.webp",
            len(flat_body), len(prev_body), c["glow"], sort, "Pixora Studio",
            TARGET[0], TARGET[1],
        ),
    )
    print(f"    inserted: {cur.fetchone()[0]}")

# Write catalog_index once (version bump), commit Postgres.
cat["version"] = (cat.get("version", 0) or 0) + 1
put_json(IMG_BUCKET, "catalog_index.json", cat)
conn.commit()
cur.close()
conn.close()

print()
print("=" * 64)
print("DONE — 4 parejas anime publicadas en AMOR (tag `amor`)")
for c in COUPLES:
    print(f"  • {c['id']:24s} {c['title_es']}")
print("  Ajusta offset_x/y_px por pareja en el sprite editor si hace falta.")
print("=" * 64)
