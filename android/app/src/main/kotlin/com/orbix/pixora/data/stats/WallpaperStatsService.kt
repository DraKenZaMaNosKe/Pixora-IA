package com.orbix.pixora.data.stats

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Fire-and-forget wallpaper analytics.
 *
 * Reads current counters and writes back current+1. Race conditions
 * may drop a count when two devices increment in the same instant —
 * acceptable for v2 alpha telemetry. Upgrade to a Postgres RPC
 * (`increment_wallpaper_view`) once we have a Functions Supabase
 * migration ready.
 */
@Singleton
class WallpaperStatsService @Inject constructor(
    private val supabase: SupabaseClient,
) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Track a wallpaper viewer open. */
    fun trackView(id: String) {
        scope.launch { increment(id, isDownload = false) }
    }

    /** Track an apply / acquire / download success. */
    fun trackDownload(id: String) {
        scope.launch { increment(id, isDownload = true) }
    }

    private suspend fun increment(id: String, isDownload: Boolean) {
        runCatching {
            val current = supabase.from("wallpapers")
                .select {
                    filter { eq("id", id) }
                    limit(1)
                }
                .decodeList<Counters>()
                .firstOrNull() ?: return

            supabase.from("wallpapers").update(
                {
                    if (isDownload) {
                        set("install_count", (current.installCount ?: 0) + 1)
                    } else {
                        set("view_count", (current.viewCount ?: 0) + 1)
                    }
                },
            ) {
                filter { eq("id", id) }
            }
        }.onFailure {
            println("[WallpaperStatsService] track ${if (isDownload) "DL" else "VIEW"} failed: ${it.message}")
        }
    }

    @Serializable
    private data class Counters(
        @SerialName("view_count") val viewCount: Long? = 0,
        @SerialName("install_count") val installCount: Long? = 0,
    )
}
