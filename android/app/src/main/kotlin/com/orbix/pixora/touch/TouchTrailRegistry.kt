package com.orbix.pixora.touch

/**
 * Registry of all available touch-trail effects. Adding a new effect:
 *   1. Implement [TouchTrailRenderer]
 *   2. Add it to [allIds] + [create]
 *   3. Add a Spanish + English entry in lib/features/settings (Dart side)
 *
 * The user's selection is stored in SharedPreferences "pixora_live" /
 * "touch_trail_style" and read by PixoraWallpaperService.
 */
object TouchTrailRegistry {
    const val PREF_KEY = "touch_trail_style"
    const val DEFAULT_ID = "aurora"

    val allIds: List<String> = listOf(
        "aurora",
        "sparks",
        "comet",
        "lightning",
        "petals",
        "stardust",
        "pixora_gold",
    )

    fun create(id: String): TouchTrailRenderer = when (id) {
        "aurora" -> AuroraTrail()
        "sparks" -> SparksTrail()
        "comet" -> CometTrail()
        "lightning" -> LightningTrail()
        "petals" -> PetalsTrail()
        "stardust" -> StardustTrail()
        "pixora_gold" -> PixoraGoldTrail()
        else -> AuroraTrail() // safe fallback
    }
}
