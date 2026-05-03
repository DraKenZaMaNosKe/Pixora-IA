package com.orbix.pixora

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.io.File
import java.net.URL
import java.util.concurrent.TimeUnit
import kotlin.math.floor

/**
 * Keeps the Iah lunar wallpaper synced to the real moon phase.
 *
 * Once the user installs the Iah wallpaper, this worker:
 *  - Computes today's phase index (0..7) from the current timestamp using
 *    a simplified Meeus synodic-month formula.
 *  - Compares against the last applied phase.
 *  - If different, downloads the matching variant (or uses local cache) and
 *    pushes the new path into the live wallpaper engine via SharedPreferences
 *    + the WALLPAPER_PATH_CHANGED broadcast (the same flow DayCycleWorker uses).
 *
 * On install we also pre-cache all 8 phase variants for the user's sign in
 * a background thread so future updates work offline.
 *
 * The worker reschedules itself every 6 hours. With ~3.7 days per phase, that
 * gives at most ~6 hours of lag when a phase boundary crosses, which is
 * imperceptible at the visual scale of moon shadow movement.
 */
class LunarPhaseWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    companion object {
        private const val TAG = "LunarPhaseWorker"
        private const val WORK_NAME = "pixora_lunar_phase"
        private const val PREFS_NAME = "pixora_lunar_phase"
        private const val CHECK_INTERVAL_HOURS = 6L

        // 8 phase keys, in order, matching the Dart MoonPhase enum AND the
        // Python build script's filename suffix.
        private val PHASE_KEYS = arrayOf(
            "new", "waxing_crescent", "first_quarter", "waxing_gibbous",
            "full", "waning_gibbous", "third_quarter", "waning_crescent",
        )

        // Synodic month length (Meeus) — days
        private const val SYNODIC_MONTH = 29.530588853
        // Reference new moon: 2000-01-06 18:14 UTC = Unix epoch ms 947182440000
        private const val EPOCH_NEW_MOON_MS = 947182440000L

        private const val SUPABASE_BUCKET_BASE =
            "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public/wallpaper-images"

        fun start(context: Context, signIndex: Int, glowColor: String): Boolean {
            return try {
                // Mark current phase as already applied — Flutter just called
                // setLiveWallpaper for this phase a moment ago, so we don't
                // need to re-apply. The worker will detect and apply only
                // when the phase actually changes.
                val nowPhase = currentPhaseIndex()
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit()
                    .putBoolean("enabled", true)
                    .putInt("sign_index", signIndex)
                    .putString("glow_color", glowColor)
                    .putInt("last_phase", nowPhase)
                    .apply()

                // Pre-cache + schedule are non-blocking and safe on main thread.
                // (preCacheVariants runs the actual network on its own thread.)
                preCacheVariants(context, signIndex)
                scheduleNext(context)

                Log.d(TAG, "Lunar updater started for sign $signIndex (phase $nowPhase)")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start lunar updater", e)
                false
            }
        }

        fun stop(context: Context): Boolean {
            return try {
                WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putBoolean("enabled", false).apply()
                Log.d(TAG, "Lunar updater stopped")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop lunar updater", e)
                false
            }
        }

        fun getStatus(context: Context): Map<String, Any?> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val phaseIdx = currentPhaseIndex()
            return mapOf(
                "enabled" to prefs.getBoolean("enabled", false),
                "signIndex" to prefs.getInt("sign_index", -1),
                "lastPhase" to prefs.getInt("last_phase", -1),
                "currentPhase" to phaseIdx,
                "currentPhaseName" to PHASE_KEYS[phaseIdx],
            )
        }

        /** Current moon phase index 0..7 from system clock + Meeus epoch. */
        fun currentPhaseIndex(): Int {
            val nowMs = System.currentTimeMillis()
            val daysSinceEpoch = (nowMs - EPOCH_NEW_MOON_MS).toDouble() / (1000.0 * 86400.0)
            val age = ((daysSinceEpoch % SYNODIC_MONTH) + SYNODIC_MONTH) % SYNODIC_MONTH
            val idx = floor(age / SYNODIC_MONTH * 8.0).toInt()
            return idx.coerceIn(0, 7)
        }

        private fun phaseFileName(phaseIdx: Int, signIdx: Int): String {
            val phaseKey = PHASE_KEYS[phaseIdx]
            val sign = String.format("%02d", signIdx)
            return "pixora_iah_egyptian_giza_lunar_${phaseKey}_${sign}.webp"
        }

        private fun phaseUrl(phaseIdx: Int, signIdx: Int): String =
            "$SUPABASE_BUCKET_BASE/${phaseFileName(phaseIdx, signIdx)}"

        private fun localFile(context: Context, phaseIdx: Int, signIdx: Int): File {
            val dir = File(context.filesDir.parentFile, "app_flutter/wallpapers")
            if (!dir.exists()) dir.mkdirs()
            return File(dir, phaseFileName(phaseIdx, signIdx))
        }

        private fun ensureCached(context: Context, phaseIdx: Int, signIdx: Int): File? {
            val f = localFile(context, phaseIdx, signIdx)
            if (f.exists() && f.length() > 0) return f
            return try {
                URL(phaseUrl(phaseIdx, signIdx)).openStream().use { input ->
                    f.outputStream().use { output -> input.copyTo(output) }
                }
                Log.d(TAG, "Cached: ${f.name} (${f.length() / 1024} KB)")
                f
            } catch (e: Exception) {
                Log.e(TAG, "Failed to cache $phaseIdx for sign $signIdx", e)
                null
            }
        }

        private fun preCacheVariants(context: Context, signIndex: Int) {
            // Off-thread so install UI doesn't block on 8 downloads (~5 MB total).
            // Future phase changes can then read from disk without network.
            Thread {
                for (i in 0..7) {
                    ensureCached(context, i, signIndex)
                }
                Log.d(TAG, "Pre-cache done for sign $signIndex")
            }.start()
        }

        private fun applyCurrentPhase(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val signIdx = prefs.getInt("sign_index", -1)
            if (signIdx !in 0..11) return

            val phaseIdx = currentPhaseIndex()
            val lastPhase = prefs.getInt("last_phase", -1)

            if (lastPhase == phaseIdx) {
                Log.d(TAG, "Phase unchanged: $phaseIdx (${PHASE_KEYS[phaseIdx]}), skipping")
                return
            }

            val file = ensureCached(context, phaseIdx, signIdx) ?: run {
                Log.e(TAG, "Cache miss + download failed; will retry next tick")
                return
            }
            val glowColor = prefs.getString("glow_color", "#D4AF37") ?: "#D4AF37"

            try {
                // Push new path to live wallpaper SharedPreferences
                val livePrefs = context.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                livePrefs.edit()
                    .putString("wallpaper_path", file.absolutePath)
                    .putString("glow_color", glowColor)
                    .remove("caption")
                    .putLong("changed_at", System.currentTimeMillis())
                    .apply()

                // Notify :wallpaper process — SharedPreferences cache is stale across
                // processes (see tech_sharedprefs_multi_process.md).
                val notify = Intent("com.orbix.pixora.WALLPAPER_PATH_CHANGED")
                    .setPackage(context.packageName)
                    .putExtra("wallpaper_path", file.absolutePath)
                    .putExtra("glow_color", glowColor)
                    .putExtra("caption", null as String?)
                context.sendBroadcast(notify)

                prefs.edit().putInt("last_phase", phaseIdx).apply()
                Log.d(TAG, "Lunar phase applied: ${PHASE_KEYS[phaseIdx]} for sign $signIdx")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to apply lunar phase", e)
            }
        }

        private fun scheduleNext(context: Context) {
            // Only fire when device has network — avoids waking the worker
            // for guaranteed-failed downloads when offline. Once the 8
            // variants are pre-cached locally, the worker still needs
            // network only on the very first scheduled run; later phase
            // updates read from disk.
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val request = OneTimeWorkRequestBuilder<LunarPhaseWorker>()
                .setInitialDelay(CHECK_INTERVAL_HOURS, TimeUnit.HOURS)
                .setConstraints(constraints)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
        }
    }

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("enabled", false)) {
            Log.d(TAG, "Lunar updater disabled, not rescheduling")
            return Result.success()
        }

        applyCurrentPhase(applicationContext)
        scheduleNext(applicationContext)

        return Result.success()
    }
}
