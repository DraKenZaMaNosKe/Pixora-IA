package com.orbix.pixora.data.db

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Single-row table holding the user's diamond balance.
 * We keep ID fixed at 1 so updates are deterministic.
 */
@Entity(tableName = "credits")
data class CreditEntity(
    @PrimaryKey val id: Int = SINGLETON_ID,
    val balance: Long,
    val totalEarned: Long,
    val totalSpent: Long,
    val updatedAt: Long,
) {
    companion object {
        const val SINGLETON_ID = 1
    }
}
