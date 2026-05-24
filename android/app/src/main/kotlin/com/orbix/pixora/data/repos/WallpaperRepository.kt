package com.orbix.pixora.data.repos

import com.orbix.pixora.data.models.Wallpaper
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository for wallpapers — single source of truth for the UI layer.
 *
 * v1 had both a JSON-static catalog (legacy) and Postgres `wallpapers_v`
 * view. v2 reads ONLY from Postgres (the JSON fallback caused several
 * bugs in v1, e.g. wallpapers_v drift bugs from missing column refreshes).
 *
 * In-memory cache lives in the ViewModel layer (StateFlow). This repo
 * is stateless — every call hits Supabase. Add disk caching (Room) when
 * we need offline support.
 */
@Singleton
class WallpaperRepository @Inject constructor(
    private val supabase: SupabaseClient,
) {
    /**
     * Fetch all published wallpapers ordered by sort_order ASC.
     * Returns empty list on error (logged via Kotlin's println — replace
     * with proper logging when we set up Timber).
     */
    suspend fun fetchAll(): List<Wallpaper> = runCatching {
        val list = supabase.from("wallpapers_v")
            .select {
                order(column = "sort_order", order = Order.ASCENDING)
            }
            .decodeList<Wallpaper>()
        println("[WallpaperRepo] fetchAll OK — ${list.size} items")
        if (list.isNotEmpty()) {
            println("[WallpaperRepo] first item: ${list[0].id} previewUrl=${list[0].previewUrl}")
        }
        list
    }.getOrElse {
        println("[WallpaperRepo] fetchAll failed: ${it.message}")
        it.printStackTrace()
        emptyList()
    }

    /** Fetch wallpapers filtered by category (case-insensitive). */
    suspend fun fetchByCategory(category: String): List<Wallpaper> = runCatching {
        supabase.from("wallpapers_v")
            .select {
                filter {
                    eq("category", category.uppercase())
                }
                order(column = "sort_order", order = Order.ASCENDING)
            }
            .decodeList<Wallpaper>()
    }.getOrElse {
        println("[WallpaperRepo] fetchByCategory($category) failed: ${it.message}")
        emptyList()
    }
}
