package com.orbix.pixora.data.db

import androidx.room.Database
import androidx.room.RoomDatabase

/**
 * Pixora local database.
 *
 * Right now this only holds the credit balance — favorites, view counts,
 * download history etc. land here as future features get wired. Bump the
 * version + write a migration when adding new tables.
 */
@Database(
    entities = [CreditEntity::class, FavoriteEntity::class],
    version = 2,
    exportSchema = false,
)
abstract class PixoraDatabase : RoomDatabase() {
    abstract fun creditDao(): CreditDao
    abstract fun favoriteDao(): FavoriteDao

    companion object {
        const val DB_NAME = "pixora.db"
    }
}
