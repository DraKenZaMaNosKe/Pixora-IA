package com.orbix.pixora

import android.content.Context
import android.os.Environment
import android.os.StatFs
import android.util.Log
import androidx.work.*
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * AutoRotateWorker — periodically downloads and sets a random wallpaper.
 *
 * Features:
 * - Picks a random wallpaper from the catalog (avoids repeating last 5)
 * - Downloads to temp file first, renames on success (crash-safe)
 * - Enforces max cache size (10 wallpapers, ~50MB)
 * - Checks available disk space before downloading
 * - Handles no internet gracefully (uses cached wallpaper)
 * - Pre-downloads next wallpaper for instant swap
 */
class AutoRotateWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val catalogJson = prefs.getString("catalog_json", null)

        if (catalogJson.isNullOrEmpty()) {
            Log.e(TAG, "No catalog data available")
            return scheduleNextAndSucceed(prefs)
        }

        // Parse catalog entries: "id|imageFile|glowColor" separated by newlines
        val entries = catalogJson.split("\n").filter { it.isNotEmpty() }
        if (entries.isEmpty()) {
            Log.e(TAG, "Empty catalog")
            return scheduleNextAndSucceed(prefs)
        }

        // Get recent history to avoid repeats
        val history = prefs.getString("history", "")!!.split("|").filter { it.isNotEmpty() }
        val maxHistory = minOf(5, entries.size - 1) // don't exclude all

        // Pick a random entry not in recent history
        val available = entries.filter { entry ->
            val id = entry.split("|").firstOrNull() ?: ""
            id !in history.takeLast(maxHistory)
        }.ifEmpty { entries } // fallback to all if everything filtered

        val chosen = available.random()
        val parts = chosen.split("|")
        if (parts.size < 3) {
            Log.e(TAG, "Invalid catalog entry: $chosen")
            return scheduleNextAndSucceed(prefs)
        }

        val wallpaperId = parts[0]
        val imageFile = parts[1]
        val glowColor = parts[2]

        Log.d(TAG, "Selected wallpaper: $wallpaperId ($imageFile)")

        // Check disk space (need at least 20MB free)
        if (!hasSufficientSpace(20L * 1024 * 1024)) {
            Log.w(TAG, "Low disk space, cleaning cache...")
            cleanOldCache(prefs, keepCount = 3)
            if (!hasSufficientSpace(10L * 1024 * 1024)) {
                Log.e(TAG, "Still not enough space, using cached wallpaper")
                setFromCacheAndSchedule(prefs)
                return scheduleNextAndSucceed(prefs)
            }
        }

        // Enforce max cache size before downloading
        enforceMaxCache(prefs)

        val cacheDir = getWallpaperCacheDir()
        val targetFile = File(cacheDir, imageFile.replace("/", "_"))
        val tempFile = File(cacheDir, "${targetFile.name}.tmp")

        val success = if (targetFile.exists()) {
            Log.d(TAG, "Using cached: ${targetFile.name}")
            setWallpaper(targetFile.absolutePath, glowColor, prefs)
        } else {
            // Download to temp file first
            val downloaded = downloadFile(
                "${SUPABASE_STORAGE_BASE}/$imageFile",
                tempFile
            )
            if (downloaded) {
                tempFile.renameTo(targetFile)
                setWallpaper(targetFile.absolutePath, glowColor, prefs)
            } else {
                Log.w(TAG, "Download failed, trying cached wallpaper")
                setFromCacheAndSchedule(prefs)
                return scheduleNextAndSucceed(prefs)
            }
        }

        if (success) {
            // Update history
            val newHistory = (history + wallpaperId).takeLast(10).joinToString("|")
            prefs.edit()
                .putString("history", newHistory)
                .putString("current_id", wallpaperId)
                .putString("current_path", targetFile.absolutePath)
                .putString("current_glow", glowColor)
                .apply()

            Log.d(TAG, "Wallpaper set: $wallpaperId")

            // Pre-download next wallpaper in background
            preDownloadNext(entries, history + wallpaperId)
        }

        return scheduleNextAndSucceed(prefs)
    }

    private fun scheduleNextAndSucceed(prefs: android.content.SharedPreferences): Result {
        val intervalMinutes = prefs.getInt("interval_minutes", 5).toLong()
        scheduleNext(applicationContext, intervalMinutes)
        return Result.success()
    }

    private fun setWallpaper(path: String, glowColor: String, prefs: android.content.SharedPreferences): Boolean {
        return try {
            // Update live wallpaper prefs — PixoraWallpaperService listens for changes
            // and reloads the image with clock, equalizer, battery, system rings
            val livePrefs = applicationContext.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
            livePrefs.edit()
                .putString("wallpaper_path", path)
                .putString("glow_color", glowColor)
                .putLong("changed_at", System.currentTimeMillis()) // trigger listener
                .apply()

            Log.d(TAG, "Wallpaper prefs updated: $path, glow=$glowColor")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set wallpaper: ${e.message}")
            false
        }
    }

    private fun setFromCacheAndSchedule(prefs: android.content.SharedPreferences): Boolean {
        val cacheDir = getWallpaperCacheDir()
        val cached = cacheDir.listFiles()
            ?.filter { it.extension != "tmp" && it.length() > 0 }
            ?.randomOrNull()

        return if (cached != null) {
            val glowColor = prefs.getString("current_glow", "#7C4DFF") ?: "#7C4DFF"
            setWallpaper(cached.absolutePath, glowColor, prefs)
        } else {
            Log.w(TAG, "No cached wallpapers available")
            false
        }
    }

    private fun downloadFile(url: String, target: File): Boolean {
        return try {
            target.parentFile?.mkdirs()
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 15_000
            conn.readTimeout = 30_000

            if (conn.responseCode == HttpURLConnection.HTTP_OK) {
                conn.inputStream.use { input ->
                    target.outputStream().use { output ->
                        input.copyTo(output, bufferSize = 8192)
                    }
                }
                Log.d(TAG, "Downloaded: ${target.name} (${target.length()} bytes)")
                true
            } else {
                Log.e(TAG, "HTTP ${conn.responseCode} for $url")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Download error: ${e.message}")
            target.delete() // clean up partial download
            false
        }
    }

    private fun preDownloadNext(entries: List<String>, currentHistory: List<String>) {
        try {
            val maxHistory = minOf(5, entries.size - 1)
            val available = entries.filter { entry ->
                val id = entry.split("|").firstOrNull() ?: ""
                id !in currentHistory.takeLast(maxHistory)
            }.ifEmpty { entries }

            val next = available.random()
            val parts = next.split("|")
            if (parts.size < 2) return

            val imageFile = parts[1]
            val cacheDir = getWallpaperCacheDir()
            val targetFile = File(cacheDir, imageFile.replace("/", "_"))

            if (!targetFile.exists()) {
                Log.d(TAG, "Pre-downloading next: ${parts[0]}")
                val tempFile = File(cacheDir, "${targetFile.name}.tmp")
                if (downloadFile("${SUPABASE_STORAGE_BASE}/$imageFile", tempFile)) {
                    tempFile.renameTo(targetFile)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Pre-download failed (non-critical): ${e.message}")
        }
    }

    private fun hasSufficientSpace(minBytes: Long): Boolean {
        return try {
            val stat = StatFs(Environment.getDataDirectory().path)
            stat.availableBytes > minBytes
        } catch (_: Exception) { true }
    }

    private fun enforceMaxCache(prefs: android.content.SharedPreferences) {
        val maxCached = prefs.getInt("max_cached", MAX_CACHED_WALLPAPERS)
        val cacheDir = getWallpaperCacheDir()
        val files = cacheDir.listFiles()
            ?.filter { it.extension != "tmp" }
            ?.sortedBy { it.lastModified() } ?: return

        if (files.size > maxCached) {
            val currentPath = prefs.getString("current_path", "")
            val toDelete = files.size - maxCached
            var deleted = 0
            for (file in files) {
                if (deleted >= toDelete) break
                if (file.absolutePath != currentPath) {
                    file.delete()
                    deleted++
                    Log.d(TAG, "Cache cleanup: deleted ${file.name}")
                }
            }
        }
    }

    private fun cleanOldCache(prefs: android.content.SharedPreferences, keepCount: Int) {
        val cacheDir = getWallpaperCacheDir()
        val files = cacheDir.listFiles()
            ?.filter { it.extension != "tmp" }
            ?.sortedBy { it.lastModified() } ?: return

        val currentPath = prefs.getString("current_path", "")
        val toDelete = maxOf(0, files.size - keepCount)
        var deleted = 0
        for (file in files) {
            if (deleted >= toDelete) break
            if (file.absolutePath != currentPath) {
                file.delete()
                deleted++
            }
        }
    }

    private fun getWallpaperCacheDir(): File {
        val dir = File(applicationContext.filesDir, "auto_rotate_cache")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    companion object {
        private const val TAG = "PixoraAutoRotate"
        const val WORK_NAME = "pixora_auto_rotate"
        const val PREFS_NAME = "pixora_auto_rotate"
        private const val MAX_CACHED_WALLPAPERS = 10
        private const val SUPABASE_STORAGE_BASE =
            "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public/wallpaper-images"

        fun scheduleNext(context: Context, delayMinutes: Long) {
            val request = OneTimeWorkRequestBuilder<AutoRotateWorker>()
                .setInitialDelay(delayMinutes, TimeUnit.MINUTES)
                .addTag(WORK_NAME)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniqueWork(
                    WORK_NAME,
                    ExistingWorkPolicy.REPLACE,
                    request
                )
            Log.d(TAG, "Next rotation in ${delayMinutes}min")
        }

        /**
         * Start auto-rotate with catalog data.
         * @param catalogData List of "id|imageFile|glowColor" strings
         * @param intervalMinutes Minutes between wallpaper changes
         * @param target 0=Home, 1=Lock, 2=Both
         */
        fun start(
            context: Context,
            catalogData: List<String>,
            intervalMinutes: Int,
            target: Int = 2,
            category: String? = null
        ): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()
                .putString("catalog_json", catalogData.joinToString("\n"))
                .putInt("interval_minutes", intervalMinutes)
                .putInt("target", target)
                .putBoolean("enabled", true)
            if (category != null) editor.putString("category", category)
            else editor.remove("category")
            editor.apply()

            // Start immediately
            val request = OneTimeWorkRequestBuilder<AutoRotateWorker>()
                .addTag(WORK_NAME)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniqueWork(
                    WORK_NAME,
                    ExistingWorkPolicy.REPLACE,
                    request
                )

            Log.d(TAG, "Auto-rotate started: ${catalogData.size} wallpapers, ${intervalMinutes}min interval, target=$target")
            return true
        }

        fun stop(context: Context): Boolean {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putBoolean("enabled", false).apply()
            Log.d(TAG, "Auto-rotate stopped")
            return true
        }

        fun getStatus(context: Context): Map<String, Any?> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val cacheDir = File(context.filesDir, "auto_rotate_cache")
            val cachedCount = cacheDir.listFiles()
                ?.count { it.extension != "tmp" } ?: 0
            val cacheSize = cacheDir.listFiles()
                ?.filter { it.extension != "tmp" }
                ?.sumOf { it.length() } ?: 0L

            return mapOf(
                "enabled" to prefs.getBoolean("enabled", false),
                "currentId" to prefs.getString("current_id", null),
                "intervalMinutes" to prefs.getInt("interval_minutes", 5),
                "target" to prefs.getInt("target", 2),
                "category" to prefs.getString("category", null),
                "cachedCount" to cachedCount,
                "cacheSizeMB" to String.format("%.1f", cacheSize / 1024.0 / 1024.0),
                "historyCount" to (prefs.getString("history", "")?.split("|")?.filter { it.isNotEmpty() }?.size ?: 0)
            )
        }

        fun clearCache(context: Context) {
            val cacheDir = File(context.filesDir, "auto_rotate_cache")
            cacheDir.listFiles()?.forEach { it.delete() }
            Log.d(TAG, "Cache cleared")
        }
    }
}
