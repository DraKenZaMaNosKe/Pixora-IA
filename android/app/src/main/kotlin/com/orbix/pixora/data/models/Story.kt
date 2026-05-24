package com.orbix.pixora.data.models

import com.orbix.pixora.data.SupabaseConfig
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class StoryFrame(
    @SerialName("imageFile") val imageFile: String,
    @SerialName("captionEs") val captionEs: String = "",
    @SerialName("captionEn") val captionEn: String = "",
    @SerialName("captionJa") val captionJa: String = "",
) {
    val imageUrl: String get() = SupabaseConfig.imageUrl(imageFile)
}

@Serializable
data class Story(
    val id: String,
    val title: String,
    val description: String = "",
    @SerialName("coverImage") val coverImage: String,
    @SerialName("glowColor") val glowColor: String = "#FFFFFF",
    val category: String = "STORIES",
    @SerialName("intervalMinutes") val intervalMinutes: Int = 30,
    val frames: List<StoryFrame> = emptyList(),
) {
    val coverUrl: String get() = SupabaseConfig.imageUrl(coverImage)
}

@Serializable
data class StoryCatalog(
    val version: Int = 1,
    val stories: List<Story> = emptyList(),
)
