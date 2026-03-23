package com.orbix.pixora

import android.app.WallpaperManager
import android.content.Context
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import androidx.work.*
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * WorkManager task that periodically checks the time of day
 * and switches the system wallpaper to the corresponding period image.
 *
 * Periods:
 *   Morning:   06:00 - 11:59
 *   Afternoon:  12:00 - 17:59
 *   Evening:   18:00 - 20:59
 *   Night:     21:00 - 05:59
 */
class DayCycleWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    companion object {
        private const val TAG = "DayCycleWorker"
        private const val WORK_NAME = "pixora_day_cycle"
        private const val PREFS_NAME = "pixora_day_cycle"
        private const val CHECK_INTERVAL_MINUTES = 15L

        fun start(
            context: Context,
            themeId: String,
            morningPath: String,
            afternoonPath: String,
            eveningPath: String,
            nightPath: String,
            glowColor: String,
            target: Int,
        ): Boolean {
            return try {
                // Save config
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit()
                    .putBoolean("enabled", true)
                    .putString("theme_id", themeId)
                    .putString("morning_path", morningPath)
                    .putString("afternoon_path", afternoonPath)
                    .putString("evening_path", eveningPath)
                    .putString("night_path", nightPath)
                    .putString("glow_color", glowColor)
                    .putInt("target", target)
                    .putString("last_period", "")
                    .apply()

                // Apply wallpaper for current period immediately
                applyCurrentPeriod(context)

                // Schedule periodic checks
                scheduleNext(context)

                Log.d(TAG, "Day cycle started: $themeId")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start day cycle", e)
                false
            }
        }

        fun stop(context: Context): Boolean {
            return try {
                WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putBoolean("enabled", false).apply()
                Log.d(TAG, "Day cycle stopped")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop day cycle", e)
                false
            }
        }

        fun getStatus(context: Context): Map<String, Any?> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return mapOf(
                "enabled" to prefs.getBoolean("enabled", false),
                "themeId" to prefs.getString("theme_id", null),
                "lastPeriod" to prefs.getString("last_period", null),
                "currentPeriod" to getCurrentPeriod(),
            )
        }

        private fun getCurrentPeriod(): String {
            val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            return when {
                hour in 6..11 -> "morning"
                hour in 12..17 -> "afternoon"
                hour in 18..20 -> "evening"
                else -> "night"
            }
        }

        private fun getPathForPeriod(prefs: android.content.SharedPreferences, period: String): String? {
            return prefs.getString("${period}_path", null)
        }

        private fun applyCurrentPeriod(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val period = getCurrentPeriod()
            val lastPeriod = prefs.getString("last_period", "")
            val path = getPathForPeriod(prefs, period) ?: return
            val target = prefs.getInt("target", 0)

            // Always apply on first run, then only when period changes
            if (lastPeriod == period) {
                Log.d(TAG, "Period unchanged: $period, skipping")
                return
            }

            try {
                val bitmap = BitmapFactory.decodeFile(path) ?: return
                val manager = WallpaperManager.getInstance(context)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    val flag = when (target) {
                        0 -> WallpaperManager.FLAG_SYSTEM
                        1 -> WallpaperManager.FLAG_LOCK
                        else -> WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK
                    }
                    manager.setBitmap(bitmap, null, true, flag)
                } else {
                    manager.setBitmap(bitmap)
                }
                bitmap.recycle()

                prefs.edit().putString("last_period", period).apply()
                Log.d(TAG, "Wallpaper changed to $period: $path")

                // Also update live wallpaper prefs if active
                val livePrefs = context.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                val glowColor = prefs.getString("glow_color", "#7C4DFF") ?: "#7C4DFF"
                livePrefs.edit()
                    .putString("wallpaper_path", path)
                    .putString("glow_color", glowColor)
                    .putLong("changed_at", System.currentTimeMillis())
                    .apply()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to apply wallpaper for $period", e)
            }
        }

        private fun scheduleNext(context: Context) {
            val request = OneTimeWorkRequestBuilder<DayCycleWorker>()
                .setInitialDelay(CHECK_INTERVAL_MINUTES, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
        }
    }

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("enabled", false)) {
            Log.d(TAG, "Day cycle disabled, not rescheduling")
            return Result.success()
        }

        applyCurrentPeriod(applicationContext)
        scheduleNext(applicationContext)

        return Result.success()
    }
}
