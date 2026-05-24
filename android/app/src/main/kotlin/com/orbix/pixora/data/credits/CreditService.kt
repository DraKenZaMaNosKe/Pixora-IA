package com.orbix.pixora.data.credits

import com.orbix.pixora.data.db.CreditDao
import com.orbix.pixora.data.db.CreditEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Diamond balance gatekeeper. Single source of truth for the user's
 * credits — the UI observes [balance] and never writes to the DB directly.
 *
 * Mirrors v1's CreditService.instance semantics: earnFromAd() / spend()
 * are the only mutation entry points. Auto-awards 1 diamond per ad
 * dismissal (called from AdService); spend() will gate premium actions
 * (Pixora IA generation, etc.) when those land.
 */
@Singleton
class CreditService @Inject constructor(
    private val dao: CreditDao,
) {

    /** Observable balance — starts at 0 if no row exists yet. */
    val balance: Flow<Long> = dao.observe().map { it?.balance ?: 0L }

    suspend fun earnFromAd(amount: Long = 1L) {
        mutate { it.copy(balance = it.balance + amount, totalEarned = it.totalEarned + amount) }
    }

    /** Returns true if the spend succeeded (had enough balance), false otherwise. */
    suspend fun spend(amount: Long): Boolean {
        val current = dao.get() ?: blank()
        if (current.balance < amount) return false
        dao.upsert(
            current.copy(
                balance = current.balance - amount,
                totalSpent = current.totalSpent + amount,
                updatedAt = System.currentTimeMillis(),
            )
        )
        return true
    }

    suspend fun current(): Long = (dao.get() ?: blank()).balance

    private suspend fun mutate(transform: (CreditEntity) -> CreditEntity) {
        val current = dao.get() ?: blank()
        dao.upsert(transform(current).copy(updatedAt = System.currentTimeMillis()))
    }

    private fun blank(): CreditEntity = CreditEntity(
        balance = 0L,
        totalEarned = 0L,
        totalSpent = 0L,
        updatedAt = System.currentTimeMillis(),
    )
}
