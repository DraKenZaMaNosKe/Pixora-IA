package com.orbix.pixora.data.favorites

import com.orbix.pixora.data.db.FavoriteDao
import com.orbix.pixora.data.db.FavoriteEntity
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Single source of truth for favorites. UI observes flows from here;
 * mutations go through [toggle] / [remove]. Stays kind-agnostic so
 * Wallpapers, Live, AURA, Tones, Stories, Day Cycle all share it.
 */
@Singleton
class FavoriteService @Inject constructor(
    private val dao: FavoriteDao,
) {

    fun observeAll(): Flow<List<FavoriteEntity>> = dao.observeAll()

    fun observeByKind(kind: String): Flow<List<FavoriteEntity>> = dao.observeByKind(kind)

    fun observeCount(): Flow<Int> = dao.observeCount()

    fun observeIsFavorite(id: String): Flow<Boolean> = dao.observeIsFavorite(id)

    /**
     * Add the item to favorites if not present; remove it otherwise.
     * Returns the new state (true = now favorite, false = removed).
     */
    suspend fun toggle(
        id: String,
        kind: String,
        name: String,
        previewUrl: String,
        accentHex: String,
    ): Boolean {
        val wasFav = dao.isFavorite(id)
        if (wasFav) {
            dao.deleteById(id)
            return false
        }
        dao.insert(
            FavoriteEntity(
                id = id,
                kind = kind,
                name = name,
                previewUrl = previewUrl,
                accentHex = accentHex,
                addedAt = System.currentTimeMillis(),
            )
        )
        return true
    }

    suspend fun remove(id: String) = dao.deleteById(id)
}
