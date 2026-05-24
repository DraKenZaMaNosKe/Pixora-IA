package com.orbix.pixora.data.models

import com.orbix.pixora.data.SupabaseConfig
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Ringtone(
    val id: String,
    val name: String,
    val file: String,
    val duration: Int = 0,
    @SerialName("suggestedType") val suggestedType: String = "notification",
) {
    val audioUrl: String get() = SupabaseConfig.imageUrl(file)
}

@Serializable
data class RingtonePack(
    val id: String,
    val name: String,
    val description: String = "",
    @SerialName("previewImage") val previewImage: String,
    @SerialName("glowColor") val glowColor: String = "#FFFFFF",
    val category: String = "MISC",
    val tones: List<Ringtone> = emptyList(),
) {
    val previewUrl: String get() = SupabaseConfig.imageUrl(previewImage)
}

@Serializable
data class RingtoneCatalog(
    val version: Int = 1,
    val packs: List<RingtonePack> = emptyList(),
)
