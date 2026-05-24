package com.orbix.pixora.data.repos

import com.orbix.pixora.data.models.AuraTrack
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuraRepository @Inject constructor(
    private val supabase: SupabaseClient,
) {
    suspend fun fetchAll(): List<AuraTrack> = runCatching {
        supabase.from("aura_tracks")
            .select {
                order(column = "category", order = Order.ASCENDING)
                order(column = "sort_order", order = Order.ASCENDING)
            }
            .decodeList<AuraTrack>()
    }.getOrElse {
        println("[AuraRepo] fetchAll failed: ${it.message}")
        it.printStackTrace()
        emptyList()
    }
}
