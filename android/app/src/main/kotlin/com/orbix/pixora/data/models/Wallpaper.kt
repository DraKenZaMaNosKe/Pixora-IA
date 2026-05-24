package com.orbix.pixora.data.models

import com.orbix.pixora.data.SupabaseConfig
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Static wallpaper — maps 1:1 to the `wallpapers_v` view in Supabase.
 *
 * Schema mirrors v1's `Wallpaper.dart.fromSupabase` factory exactly, so
 * existing content (283 items + Bulma + ...) just works without backfills.
 *
 * Dimension-agnostic fields (`mediaWidth` / `mediaHeight`) are present and
 * drive [isPanoramic]. Legacy items with NULL dims fall back to the
 * category check (same hybrid pattern as v1 Fase 2).
 */
@Serializable
data class Wallpaper(
    val id: String,
    val name: String,
    val description: String = "",
    @SerialName("image_path") val imagePath: String,
    @SerialName("preview_path") val previewPath: String,
    @SerialName("image_size") val imageSize: Long? = null,
    @SerialName("preview_size") val previewSize: Long? = null,
    @SerialName("glow_color") val glowColor: String = "#FFFFFF",
    val category: String = "MISC",
    val badge: String? = null,
    @SerialName("sort_order") val sortOrder: Int? = null,
    val featured: Boolean = false,
    @SerialName("daily_eligible") val dailyEligible: Boolean = false,
    val tags: List<String> = emptyList(),
    @SerialName("install_count") val installCount: Long? = null,
    @SerialName("view_count") val viewCount: Long? = null,
    @SerialName("media_width") val mediaWidth: Int? = null,
    @SerialName("media_height") val mediaHeight: Int? = null,
    @SerialName("author_name") val authorName: String = "Pixora Studio",
    @SerialName("created_at") val createdAt: String? = null,
) {
    /** Full image URL (in `wallpaper-images` public bucket). */
    val imageUrl: String get() = SupabaseConfig.imageUrl(imagePath)

    /** Preview thumbnail URL. */
    val previewUrl: String get() = SupabaseConfig.imageUrl(previewPath)

    /** Aspect ratio (width / height). Null when dimensions unknown. */
    val aspectRatio: Double?
        get() {
            val w = mediaWidth ?: return null
            val h = mediaHeight ?: return null
            if (h <= 0) return null
            return w.toDouble() / h.toDouble()
        }

    /**
     * Hybrid panoramic detection (matches v1 Fase 2 logic):
     *  1. Real ratio >= 3.0 → panoramic
     *  2. Else fallback to manual category == "PANORAMIC"
     */
    val isPanoramic: Boolean
        get() {
            val r = aspectRatio
            if (r != null && r >= 3.0) return true
            return category.equals("PANORAMIC", ignoreCase = true)
        }
}
