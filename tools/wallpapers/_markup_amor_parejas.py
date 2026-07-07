"""Add semantic color markup to the 7 anime-couple descriptions.

Markup roles (rendered by TypewriterText in the app):
  [[name:...]]    -> personajes / sagas (gold)
  [[place:...]]   -> lugares / mundos (mint)
  [[power:...]]   -> poderes / energia (celeste)
  [[emotion:...]] -> la leccion / el valor de la escena (coral)

This is the pilot batch to validate the look on device before we roll the
same treatment across the whole catalog. Idempotent-ish: it overwrites the
description of these 7 ids with the marked-up version verbatim.
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

DESCS = {
    "goku_chichi_amor": (
        "[[name:Goku]] y [[name:Chichi]] se casaron cumpliendo una promesa que él "
        "hizo de niño sin entender qué era el matrimonio. Aquí, lejos de los torneos "
        "y las batallas, el guerrero más fuerte del universo abraza a la mujer que "
        "convirtió una montaña solitaria en un hogar. Al fondo, la casa de "
        "[[place:Paozu]] donde criaron a [[name:Gohan]] y [[name:Goten]]. Los "
        "corazones flotan sobre el valle: hasta el [[name:Saiyajin]] más poderoso "
        "descubrió que [[emotion:su mayor fuerza era su familia]]."
    ),
    "goku_chichi_kinton_amor": (
        "La [[power:Nube Voladora (Kinton)]] solo carga a quien tiene el corazón puro "
        "— por eso [[name:Goku]] pudo montarla toda su vida. Aquí surca el cielo con "
        "[[name:Chichi]] a su lado, entre nubes de algodón, rumbo a casa. De niños se "
        "conocieron en una promesa inocente; de adultos comparten la misma nube "
        "dorada. [[emotion:Volar juntos, sin prisa, también es una forma de amar]]."
    ),
    "haruka_michiru_amor": (
        "[[name:Haruka Tenō]] ([[name:Sailor Uranus]]) y [[name:Michiru Kaiō]] "
        "([[name:Sailor Neptune]]) son una de las parejas más queridas del anime: "
        "guardianas del viento y del mar que pelean espalda con espalda y se aman sin "
        "pedir permiso. [[name:Michiru]] toca el violín; [[name:Haruka]] corre "
        "carreras y pilota como el viento. Elegantes e inseparables, representaron "
        "[[emotion:un amor abierto]] en la televisión desde los años 90. Entre "
        "destellos violeta y aguamarina, dos fuerzas de la naturaleza que se "
        "pertenecen."
    ),
    "haruka_michiru_rosas_amor": (
        "Lejos de las batallas como [[name:Sailor Uranus]] y [[name:Neptune]], "
        "[[name:Haruka]] y [[name:Michiru]] se roban un momento de calma entre rosas. "
        "Sin transformaciones ni enemigos: solo dos personas que eligieron cuidarse "
        "la una a la otra. [[name:Michiru]], serena como el mar; [[name:Haruka]], "
        "libre como el viento. Un jardín florecido para la pareja que enseñó a toda "
        "una generación que [[emotion:el amor no necesita permiso]]."
    ),
    "naruto_hinata_amor": (
        "[[name:Hinata]] amó a [[name:Naruto]] en silencio desde la academia, cuando "
        "nadie más creía en el niño del [[power:Zorro de Nueve Colas]]. Él tardó años "
        "en verla, hasta que ella arriesgó su vida para protegerlo. Bajo un árbol de "
        "hojas doradas, en el bosque de [[place:Konoha]], por fin se besan mientras "
        "el otoño cae a su alrededor. De este amor nacieron [[name:Boruto]] y "
        "[[name:Himawari]]. El ninja más ruidoso de la aldea, por una vez, se queda "
        "sin palabras."
    ),
    "serenity_endymion_amor": (
        "La [[name:Princesa Serenity]] y el [[name:Príncipe Endymion]] —[[name:Usagi]] "
        "y [[name:Mamoru]] en esta vida— se aman a través de los siglos, la muerte y "
        "la reencarnación. Su amor nació en el antiguo [[place:Milenio de Plata]], en "
        "el [[place:Reino de la Luna]], y renace en el [[place:Tokio]] de hoy cada vez "
        "que se encuentran. Él se arrodilla ante ella bajo la luna creciente, como en "
        "un cuento que nunca termina. [[emotion:El romance más eterno del anime]]: dos "
        "almas destinadas a hallarse una y otra vez."
    ),
    "vegeta_bulma_amor": (
        "El orgulloso [[name:Príncipe de los Saiyajin]] carga en brazos a "
        "[[name:Bulma]], la científica más brillante de la Tierra, bajo un cielo de "
        "fuego y pétalos de cerezo. [[name:Vegeta]] jamás lo diría en voz alta —su "
        "orgullo no lo permite—, pero fue ella quien domó al guerrero que alguna vez "
        "quiso destruir el planeta. De ese choque de mundos nacieron [[name:Trunks]] "
        "y [[name:Bra]]. A veces [[emotion:el amor más fuerte empieza como el choque "
        "de dos rivales]]."
    ),
}

conn = connect()
cur = conn.cursor()
n = 0
for wid, desc in DESCS.items():
    cur.execute(
        "UPDATE wallpapers SET description = %s WHERE id = %s;",
        (desc, wid),
    )
    n += cur.rowcount
    print(f"  {wid}: {cur.rowcount} row(s)")
conn.commit()
cur.close()
conn.close()
print(f"\nDONE — {n} parejas con markup de color.")
