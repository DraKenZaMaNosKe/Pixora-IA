package com.orbix.pixora.data.models

import com.orbix.pixora.data.SupabaseConfig
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Live (video) wallpaper — maps to entries in live_wallpaper_catalog.json.
 *
 * Files live in the `wallpaper-videos` Storage bucket; videoFile + previewFile
 * are relative paths (e.g. "videos/foo.mp4" / "previews/foo_preview.webp").
 */
@Serializable
data class LiveWallpaper(
    val id: String,
    val name: String,
    val description: String = "",
    @SerialName("videoFile") val videoFile: String,
    @SerialName("previewFile") val previewFile: String,
    @SerialName("videoSize") val videoSize: Long? = null,
    @SerialName("previewSize") val previewSize: Long? = null,
    @SerialName("glowColor") val glowColor: String = "#FFFFFF",
    val category: String = "MISC",
    val type: String = "video",
    val badge: String? = null,
    @SerialName("sortOrder") val sortOrder: Int? = null,
    val tags: List<String> = emptyList(),
    @SerialName("downloadCount") val downloadCount: Long? = null,
    @SerialName("createdAt") val createdAt: String? = null,
) {
    val previewUrl: String get() = SupabaseConfig.videoUrl(previewFile)
    val videoUrl: String get() = SupabaseConfig.videoUrl(videoFile)
}

@Serializable
data class LiveWallpaperCatalog(
    val version: Int = 1,
    val wallpapers: List<LiveWallpaper> = emptyList(),
    val lastUpdated: String? = null,
)
