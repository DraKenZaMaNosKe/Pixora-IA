package com.orbix.pixora.data.db

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Favorited item — wallpapers, live wallpapers, AURA tracks, ringtones,
 * stories, day cycles all share this table. `kind` discriminates the
 * type so the Favoritos screen can render mixed grids with the right
 * tap-to-open behavior per kind.
 *
 * `id` is the same id used by the catalog/Postgres for that kind, so
 * we don't need a join — we just keep a denormalized snapshot of the
 * fields needed to render the favorite card (name, previewUrl, accent).
 */
@Entity(tableName = "favorites")
data class FavoriteEntity(
    @PrimaryKey val id: String,
    val kind: String,        // "wallpaper" / "live" / "aura" / "tone" / "story" / "daycycle"
    val name: String,
    val previewUrl: String,
    val accentHex: String,   // e.g. "#FFD66B" — for badge/border tint
    val addedAt: Long,
) {
    companion object {
        const val KIND_WALLPAPER = "wallpaper"
        const val KIND_LIVE = "live"
        const val KIND_AURA = "aura"
        const val KIND_TONE = "tone"
        const val KIND_STORY = "story"
        const val KIND_DAYCYCLE = "daycycle"
    }
}
