package com.orbix.pixora.data.repos

import com.orbix.pixora.data.SupabaseConfig
import com.orbix.pixora.data.models.LiveWallpaper
import com.orbix.pixora.data.models.LiveWallpaperCatalog
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Live wallpapers come from the JSON catalog in Storage (not Postgres).
 * Same convention as v1 — keep dual-stack until we migrate every vertical
 * to Postgres in a later sweep.
 */
@Singleton
class LiveWallpaperRepository @Inject constructor(
    private val http: HttpClient,
) {
    suspend fun fetchAll(): List<LiveWallpaper> = runCatching {
        val url = SupabaseConfig.catalogUrl(
            bucket = SupabaseConfig.VIDEOS_BUCKET,
            file = SupabaseConfig.CATALOG_LIVE,
        )
        val catalog: LiveWallpaperCatalog = http.get(url).body()
        // Highest sortOrder first (matches v1's reverse-sort UX).
        catalog.wallpapers.sortedByDescending { it.sortOrder ?: 0 }
    }.getOrElse {
        println("[LiveWallpaperRepo] fetchAll failed: ${it.message}")
        it.printStackTrace()
        emptyList()
    }
}
