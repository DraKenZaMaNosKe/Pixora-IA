package com.orbix.pixora.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * AURA wellness track — maps to `aura_tracks` Postgres table.
 *
 * Two categories so far: "frequency" (Solfeggio Hz tones) and "nature"
 * (rain, ocean, etc.). Audio files live in the `aura-audio` Storage bucket;
 * `audio_url` is pre-built server-side and already includes the full URL.
 */
@Serializable
data class AuraTrack(
    val id: String,
    val category: String,
    val hz: Int? = null,
    val chakra: String? = null,
    @SerialName("color_hex") val colorHex: String? = null,
    val icon: String? = null,
    @SerialName("name_en") val nameEn: String? = null,
    @SerialName("name_es") val nameEs: String? = null,
    @SerialName("desc_en") val descEn: String? = null,
    @SerialName("desc_es") val descEs: String? = null,
    @SerialName("duration_sec") val durationSec: Int = 0,
    @SerialName("file_path") val filePath: String,
    @SerialName("audio_url") val audioUrl: String,
    val license: String = "",
    @SerialName("sort_order") val sortOrder: Int = 0,
    @SerialName("created_at") val createdAt: String? = null,
) {
    /** Effective accent color (falls back to a calm purple if null). */
    val accentHex: String get() = colorHex?.takeIf { it.isNotBlank() } ?: "#6B4F8F"

    /** Spanish-by-default for now (MX target). Wire LocaleHelper later. */
    val displayName: String get() =
        nameEs?.takeIf { it.isNotBlank() } ?: nameEn ?: id
    val displayDesc: String get() =
        descEs?.takeIf { it.isNotBlank() } ?: descEn.orEmpty()

    /** Pretty duration: "15:00" or "1:23". */
    val durationLabel: String get() {
        val m = durationSec / 60
        val s = durationSec % 60
        return "%d:%02d".format(m, s)
    }
}
