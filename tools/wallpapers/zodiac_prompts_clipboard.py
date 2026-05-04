"""
Zodiac sprite prompts — sequential clipboard helper.

Usage:
    python tools/wallpapers/zodiac_prompts_clipboard.py

Cada vez que hagas Enter, el siguiente prompt se copia al portapapeles.
Pegas en Gemini con Ctrl+V, esperas a que genere, descargas la imagen
con el nombre que te indica, y vuelves a Enter para el siguiente.

Sin instalar dependencias raras — solo usa subprocess + clip.exe (Windows).
"""
import subprocess
import sys

PROMPTS = [
    ("01_aries.png", "♈ ARIES (Fuego · coral)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: A majestic golden ram with massive curling horns, head turned in profile, intricate Egyptian gold-leaf etchings on its horns, eyes glowing warm amber. Magnificent fur with bronze and copper highlights. Subtle ember particles rising near the horns suggesting fire. Pose: noble standing, 3/4 view. NO TEXT, NO LETTERS. Photorealistic 3D render with dramatic rim lighting."""),

    ("02_taurus.png", "♉ TAURUS (Tierra · jade)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: A massive bronze bull head facing forward with thick horns curving up, emerald green eyes glowing softly, Egyptian-style gold ornament on forehead with jade gemstone, deep brown coat with subtle moss-green highlights, vines and small leaves curling around the horns. Strong, grounded presence. Pose: head straight, looking at camera. NO TEXT. Unreal Engine 5 photoreal."""),

    ("03_gemini.png", "♊ GEMINI (Aire · lila)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: Two ethereal twin silhouettes embracing in profile, one slightly forward of the other, made of swirling lilac and silver mist, with constellation stars (Castor and Pollux) visible inside their forms, light pouring out from their hearts in pale violet. Hands clasped between them. Floating in mid-air, weightless. NO TEXT. Unreal Engine 5 ethereal cinematic."""),

    ("04_cancer.png", "♋ CANCER (Agua · teal)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: A regal crab with iridescent teal and pearl-white shell, intricate Egyptian hieroglyph patterns engraved into the carapace, bright cyan eyes glowing, holding a single drop of luminous water in one claw. Detailed legs and mandibles. Subtle ripples of water beneath. Pose: front view, claws raised. NO TEXT. Unreal Engine 5 photoreal."""),

    ("05_leo.png", "♌ LEO (Fuego · coral)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: A majestic male lion head with a flowing mane of intertwined fire and gold, piercing amber eyes, royal Egyptian crown nestled in the mane with rubies, flames flickering at the tips of the mane. Powerful and regal. Pose: facing forward slightly turned, mouth closed. NO TEXT. Unreal Engine 5, Lion King meets Disney concept art."""),

    ("06_virgo.png", "♍ VIRGO (Tierra · jade)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: An ethereal female figure in flowing jade-green robes, hair the color of wheat, holding a single sheaf of golden wheat, eyes closed in serenity, soft halo of green light around her, Egyptian-style gold collar and arm bands. Standing pose, three-quarter view. NO TEXT, NO FACE FEATURES needing realism — stylized classical sculpture quality. Unreal Engine 5 photoreal."""),

    ("07_libra.png", "♎ LIBRA (Aire · lila)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: An ornate floating set of golden balance scales with intricate Egyptian filigree, two perfectly balanced trays each containing a single glowing sphere — one lilac, one silver. Floating in air, no chains visible (held by invisible force), surrounded by drifting silvery mist particles. Pose: straight on, perfectly symmetric. NO TEXT. Unreal Engine 5, ornate antique aesthetic."""),

    ("08_scorpio.png", "♏ SCORPIO (Agua · teal)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: An obsidian-black scorpion with iridescent teal-cyan glow under the chitin plates, stinger raised high glowing bright cyan with a drop of luminous venom forming at the tip, intricate Egyptian patterns on the carapace, glowing turquoise eyes. Pose: classic scorpion combat stance, side view with stinger curled overhead. NO TEXT. Unreal Engine 5 photoreal."""),

    ("09_sagit.png", "♐ SAGITTARIUS (Fuego · coral)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: A noble centaur archer drawing back a flaming bow, arrow tip on fire with coral-red flames, lower horse body in deep brown with bronze patterns, upper human body in golden Egyptian armor, wild dark hair, eyes glowing amber, intense focused expression. Pose: 3/4 view, bow drawn taut, ready to release. NO TEXT. Unreal Engine 5 cinematic, fantasy concept art."""),

    ("10_capri.png", "♑ CAPRICORN (Tierra · jade)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: A mystical mountain goat with crystal-formation horns growing in spirals, horns the color of deep emerald jade, deep dark fur with green moss patches, eyes like glowing green gemstones, standing on a small rocky outcrop with crystals jutting from beneath its hooves. Pose: head proudly raised, 3/4 view. NO TEXT. Unreal Engine 5 photoreal mystical fantasy."""),

    ("11_aquar.png", "♒ AQUARIUS (Aire · lila)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: An ornate Egyptian gold and lapis lazuli urn tilted slightly, pouring out not water but a stream of pale lilac and silver light, mist particles, and tiny stars. The urn is decorated with hieroglyphics. Floating in air, no visible support. Pose: 3/4 view, urn pouring downward and to the side. NO TEXT. Unreal Engine 5 photoreal mystical glow."""),

    ("12_pisces.png", "♓ PISCES (Agua · teal)",
     """Generate a cinematic Unreal Engine 5 quality sprite for a mobile live wallpaper. SQUARE 1024×1024. Pure chroma-key GREEN background (#00FF00) covering 100% of non-subject area. Subject: Two koi fish swimming in opposite directions forming a perfect circular yin-yang composition. One fish iridescent teal-cyan with silver fins, the other deep cobalt blue with white fins. Detailed scales catching light, water ripples and a few bubbles around them. Pose: top-down view, perfect circle. NO TEXT. Unreal Engine 5 photoreal intricate detail."""),
]


def to_clipboard(text: str):
    # Windows clip.exe accepts stdin
    p = subprocess.Popen("clip", stdin=subprocess.PIPE, shell=True)
    p.communicate(text.encode("utf-16-le"))


def main():
    print("=" * 60)
    print("PIXORA · ZODIAC SPRITES — Gemini paste helper")
    print("=" * 60)
    print()
    print("Cómo usar:")
    print("  1. Abre Gemini en Chrome (gemini.google.com)")
    print("  2. Activa 'Crear imagen'")
    print("  3. Aquí presiona ENTER → el prompt se copia al clipboard")
    print("  4. Cambia a Gemini → Ctrl+V → Enter para generar")
    print("  5. Click derecho en imagen → Guardar como → usa el nombre indicado")
    print("  6. Vuelve aquí → ENTER para el siguiente")
    print()
    print(f"Total: {len(PROMPTS)} sprites a generar")
    print()
    out_dir = r"D:\\Orbix\\Pixora-IA\\docs\\design\\concepts\\livecalendar\\egyptian\\sprites"
    print(f"Guarda todas en: {out_dir}\\")
    print()

    for i, (filename, label, prompt) in enumerate(PROMPTS, 1):
        print(f"\n--- [{i}/{len(PROMPTS)}] {label} ---")
        print(f"   Guarda como: {filename}")
        input(f"   ENTER para copiar al clipboard...")
        to_clipboard(prompt)
        print(f"   ✅ Copiado. Pega en Gemini ahora.")
        print(f"   Prompt: {prompt[:100]}...")

    print()
    print("=" * 60)
    print("✅ Todos los 12 prompts entregados.")
    print(f"Cuando tengas las 12 imágenes en {out_dir}, regresa al chat.")
    print("=" * 60)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nCancelled.")
        sys.exit(0)
