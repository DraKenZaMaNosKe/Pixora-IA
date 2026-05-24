package com.orbix.pixora.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface CreditDao {

    @Query("SELECT * FROM credits WHERE id = ${CreditEntity.SINGLETON_ID}")
    fun observe(): Flow<CreditEntity?>

    @Query("SELECT * FROM credits WHERE id = ${CreditEntity.SINGLETON_ID}")
    suspend fun get(): CreditEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: CreditEntity)
}
