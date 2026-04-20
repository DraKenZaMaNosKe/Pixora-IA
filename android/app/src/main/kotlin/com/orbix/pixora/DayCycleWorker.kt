package com.orbix.pixora

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.*
import java.util.Calendar
import java.util.concurrent.TimeUnit

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

                applyCurrentPeriod(context)
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

            if (lastPeriod == period) {
                Log.d(TAG, "Period unchanged: $period, skipping")
                return
            }

            try {
                // Update live wallpaper prefs — PixoraWallpaperService picks up the change
                // This enables panoramic scroll for wide images
                val livePrefs = context.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                val glowColor = prefs.getString("glow_color", "#C9A650") ?: "#C9A650"
                livePrefs.edit()
                    .putString("wallpaper_path", path)
                    .putString("glow_color", glowColor)
                    .remove("caption")
                    .putLong("changed_at", System.currentTimeMillis())
                    .apply()

                // Notify :wallpaper process — SharedPreferences cache is stale across
                // processes, see tech_sharedprefs_multi_process.md. Passing null as
                // caption extra so the receiver clears any existing caption.
                val notify = Intent("com.orbix.pixora.WALLPAPER_PATH_CHANGED")
                    .setPackage(context.packageName)
                    .putExtra("wallpaper_path", path)
                    .putExtra("glow_color", glowColor)
                    .putExtra("caption", null as String?)
                context.sendBroadcast(notify)

                prefs.edit().putString("last_period", period).apply()
                Log.d(TAG, "Wallpaper changed to $period: $path (via live wallpaper)")
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
