"""Publish the verified Tiempo consumido canvas scene."""
from pathlib import Path

from _upload_scene_generic import upload_scene


ROOT = Path(
    r"G:\Mi unidad\pixoraIA_admin\ia_contenido_pipeline\wallpapers"
    r"\3_publicados\mano_cyber_tiempo_consumido_parallax\production"
)

CYCLE = {
    "name": "ash_fall",
    "duration_s": 8.0,
    "frames": [
        {"layer_key": "ash_00", "from_s": 0.0, "to_s": 5.5},
        {"layer_key": "ash_01", "from_s": 5.5, "to_s": 5.95},
        {"layer_key": "ash_02", "from_s": 5.95, "to_s": 6.4},
        {"layer_key": "ash_03", "from_s": 6.4, "to_s": 6.85},
        {"layer_key": "ash_04", "from_s": 6.85, "to_s": 7.3},
        {"layer_key": "ash_00", "from_s": 7.3, "to_s": 8.0},
    ],
}

DESC_RICH = (
    "Una [[name:mano cibernética]] sostiene un cigarro encendido en la oscuridad. "
    "La máquina no necesita nicotina y, aun así, repite el gesto: una metáfora de "
    "la dependencia, la ansiedad y los hábitos que continúan incluso cuando dejaron "
    "de ayudarnos. [[emotion:La brasa es el alivio inmediato; el humo, el tiempo que "
    "desaparece; la ceniza, el costo que queda.]]\n\n"
    "Nadie inventó el tabaco. Diversos pueblos indígenas de América cultivaron y "
    "usaron especies de Nicotiana durante siglos o milenios antes del contacto europeo, "
    "con usos ceremoniales, espirituales, medicinales y sociales. Después de 1492 se "
    "extendió por Europa y se convirtió en mercancía internacional. James Bonsack no "
    "inventó el tabaco: patentó en 1880 una máquina que aceleró la producción masiva de "
    "cigarrillos.\n\n"
    "La nicotina puede provocar durante unos minutos calma, atención o placer, pero en "
    "una persona dependiente parte de esa aparente calma es el alivio temporal de la "
    "propia abstinencia: deseo → fumar → alivio breve → baja la nicotina → irritabilidad "
    "o ansiedad → nuevo deseo. La dependencia no es falta de carácter.\n\n"
    "Para dejarlo ayuda identificar detonantes, retirar cigarros y ceniceros, pedir apoyo "
    "y preparar sustitutos para el impulso. La orientación conductual combinada con "
    "medicamentos apropiados —como reemplazo de nicotina y, bajo valoración profesional, "
    "vareniclina o bupropión— ofrece mejores probabilidades que intentarlo sin apoyo. "
    "En México, [[place:Línea de la Vida: 800 911 2000]] brinda orientación gratuita "
    "sobre salud mental y adicciones. Esta ficha es educativa y no sustituye atención médica."
)

CONFIG = {
    "scene_id": "mano_cyber_tiempo_consumido_parallax",
    "src_dir": str(ROOT),
    "background_file": "background.webp",
    "bg": {"z": 0, "parallax": 0.04, "scale": 1.23},
    "layers": [
        {"key": "smoke", "file": "smoke.webp", "z": 10,
         "parallax": 0.38, "scale": 1.0, "bob": [6.0, 6.2],
         "bob_phase_source": "hand_cigarette"},
        {"key": "hand_cigarette", "file": "hand_cigarette.webp", "z": 20,
         "parallax": 0.38, "scale": 1.0, "bob": [6.0, 6.2]},
        {"key": "ember_glow", "file": "ember_glow.webp", "z": 30,
         "parallax": 0.38, "scale": 1.0, "bob": [6.0, 6.2],
         "bob_phase_source": "hand_cigarette"},
        *[
            {"key": f"ash_{i:02d}", "file": f"ash_{i:02d}.webp", "z": 40,
             "parallax": 0.42, "scale": 1.0, "initial_alpha": 1.0 if i == 0 else 0.0}
            for i in range(5)
        ],
    ],
    "static_file": "mano_cyber_tiempo_consumido_parallax.webp",
    "particles": [],
    "cycles": [CYCLE],
    "sprites": [],
    "title": {"es": "Tiempo consumido", "en": "Consumed Time"},
    "tags": ["ansiedad", "tabaquismo", "concientización", "cyberpunk", "mano",
             "humo", "ceniza", "parallax", "contenido adulto", "salud"],
    "category_semantic": "abstract",
    "glow": "#FF5A2A",
    "name": "Tiempo consumido",
    "desc_plain": (
        "Una mano cibernética convierte el humo y la ceniza en una reflexión sobre "
        "ansiedad, dependencia y el tiempo que consume el tabaco."
    ),
    "desc_rich": DESC_RICH,
    "featured": False,
    "published": True,
}


if __name__ == "__main__":
    upload_scene(CONFIG)
