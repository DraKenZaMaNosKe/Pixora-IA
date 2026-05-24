package com.orbix.pixora.data.models

import com.orbix.pixora.data.SupabaseConfig
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DayCycleTheme(
    val id: String,
    val name: String,
    val description: String = "",
    @SerialName("previewImage") val previewImage: String,
    @SerialName("morningImage") val morningImage: String,
    @SerialName("afternoonImage") val afternoonImage: String,
    @SerialName("eveningImage") val eveningImage: String,
    @SerialName("nightImage") val nightImage: String,
    @SerialName("glowColor") val glowColor: String = "#FFFFFF",
) {
    val previewUrl: String get() = SupabaseConfig.imageUrl(previewImage)
    val morningUrl: String get() = SupabaseConfig.imageUrl(morningImage)
    val afternoonUrl: String get() = SupabaseConfig.imageUrl(afternoonImage)
    val eveningUrl: String get() = SupabaseConfig.imageUrl(eveningImage)
    val nightUrl: String get() = SupabaseConfig.imageUrl(nightImage)
}

@Serializable
data class DayCycleCatalog(
    val themes: List<DayCycleTheme> = emptyList(),
)
