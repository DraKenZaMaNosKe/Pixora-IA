package com.orbix.pixora.data.repos

import com.orbix.pixora.data.SupabaseConfig
import com.orbix.pixora.data.models.DayCycleCatalog
import com.orbix.pixora.data.models.DayCycleTheme
import com.orbix.pixora.data.models.RingtoneCatalog
import com.orbix.pixora.data.models.RingtonePack
import com.orbix.pixora.data.models.Story
import com.orbix.pixora.data.models.StoryCatalog
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import javax.inject.Inject
import javax.inject.Singleton

/**
 * One file holds all three "small" catalog repos because they're each
 * a one-trick pony (fetch one JSON, decode, return list). Splitting them
 * into three separate files is just ceremony.
 */

@Singleton
class StoryRepository @Inject constructor(private val http: HttpClient) {
    suspend fun fetchAll(): List<Story> = runCatching {
        val url = SupabaseConfig.catalogUrl(SupabaseConfig.IMAGES_BUCKET, SupabaseConfig.CATALOG_STORIES)
        http.get(url).body<StoryCatalog>().stories
    }.getOrElse {
        println("[StoryRepo] fetchAll failed: ${it.message}")
        emptyList()
    }
}

@Singleton
class DayCycleRepository @Inject constructor(private val http: HttpClient) {
    suspend fun fetchAll(): List<DayCycleTheme> = runCatching {
        val url = SupabaseConfig.catalogUrl(SupabaseConfig.IMAGES_BUCKET, SupabaseConfig.CATALOG_DAY_CYCLE)
        http.get(url).body<DayCycleCatalog>().themes
    }.getOrElse {
        println("[DayCycleRepo] fetchAll failed: ${it.message}")
        emptyList()
    }
}

@Singleton
class RingtoneRepository @Inject constructor(private val http: HttpClient) {
    suspend fun fetchAll(): List<RingtonePack> = runCatching {
        val url = SupabaseConfig.catalogUrl(SupabaseConfig.IMAGES_BUCKET, SupabaseConfig.CATALOG_RINGTONES)
        http.get(url).body<RingtoneCatalog>().packs
    }.getOrElse {
        println("[RingtoneRepo] fetchAll failed: ${it.message}")
        emptyList()
    }
}
