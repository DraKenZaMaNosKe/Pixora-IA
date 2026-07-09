package com.orbix.pixora

import android.content.Context
import android.content.Intent
import android.os.Environment
import android.os.StatFs
import android.util.Log
import androidx.work.*
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * AutoRotateWorker — PRE-DOWNLOAD ONLY (Phase 2, 2026-05-27).
 *
 * The actual wallpaper rotation now lives INSIDE PixoraWallpaperService
 * (rotates on-wake among cached files — see §7.Z in the master doc and
 * tech_pixora_daily_in_service_rotation memory). This worker no longer
 * applies wallpapers; it only keeps `auto_rotate_cache/` stocked with fresh
 * content so the in-service rotation always has material to rotate through.
 *
 * Why the split:
 * - Rotation must NOT depend on WorkManager: Android's App Standby quota
 *   throttles background jobs, so a rotation-via-Worker chain dies after
 *   hours. Rotation belongs in the always-running wallpaper service.
 * - This prefetch worker is best-effort: if Android throttles it, no harm —
 *   the service simply rotates whatever is already cached.
 * - Runs as a low-frequency PeriodicWork (6h) with a network constraint, so
 *   it plays nicely with Doze instead of fighting it.
 */
class AutoRotateWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        if (!prefs.getBoolean("enabled", false)) {
            Log.d(TAG, "Daily disabled — prefetch worker exits")
            return Result.success()
        }

        val catalogJson = prefs.getString("catalog_json", null)
        if (catalogJson.isNullOrEmpty()) {
            Log.d(TAG, "No catalog — nothing to prefetch")
            return Result.success()
        }
        val entries = catalogJson.split("\n").filter { it.isNotEmpty() }
        if (entries.isEmpty()) return Result.success()

        if (!hasSufficientSpace(20L * 1024 * 1024)) {
            Log.w(TAG, "Low disk space — trimming cache, skipping prefetch")
            cleanOldCache(prefs, keepCount = 3)
            return Result.success()
        }

        prefetchToCache(entries)
        enforceMaxCache(prefs)
        sweepOrphanSceneMarkers()
        seedDailyIfNeeded()
        Log.d(TAG, "Prefetch tick done")
        return Result.success()
    }

    /**
     * Remove scene markers whose spec is gone (2026-07-07). FCM clearCache can
     * wipe scene_specs/ after a marker was written; such a marker can't render
     * as a scene, so drop it from the pool. Dart's prefetch re-creates it on
     * the next activation / cold start. Cheap: one File.isFile per marker.
     */
    private fun sweepOrphanSceneMarkers() {
        val cacheDir = getWallpaperCacheDir()
        cacheDir.listFiles()
            ?.filter { it.name.endsWith(PixoraWallpaperService.SCENE_MARKER_SUFFIX) }
            ?.forEach { m ->
                val id = m.name.removeSuffix(PixoraWallpaperService.SCENE_MARKER_SUFFIX)
                if (!File(applicationContext.filesDir, "scene_specs/$id.json").isFile) {
                    if (m.delete()) Log.d(TAG, "Swept orphan scene marker: ${m.name}")
                }
            }
    }

    /**
     * Seed daily mode on first activation. The in-service rotation only kicks
     * in when the current wallpaper_path lives in auto_rotate_cache/. On a
     * fresh activation that path still points at whatever the user had before,
     * so we do ONE soft apply (broadcast, never kill) to point it at a cached
     * file. After this, PixoraWallpaperService takes over rotation on-wake.
     * No-op if already seeded (path already in the cache).
     */
    private fun seedDailyIfNeeded() {
        val livePrefs = applicationContext
            .getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
        val currentPath = livePrefs.getString("wallpaper_path", "") ?: ""
        if (currentPath.contains("auto_rotate_cache")) return // already seeded

        val cacheDir = getWallpaperCacheDir()
        val all = cacheDir.listFiles()
            ?.filter { it.extension != "tmp" && it.length() > 0 }
            ?: return
        if (all.isEmpty()) return
        // 2026-07-07 — prefer a plain image for the seed (cheapest, no scene
        // init). Only seed a scene marker if the pool is scenes-only.
        val suffix = PixoraWallpaperService.SCENE_MARKER_SUFFIX
        val plain = all.filter { !it.name.endsWith(suffix) }
        val first = (plain.ifEmpty { all }).randomOrNull() ?: return
        val seedSceneId = first.name.takeIf { it.endsWith(suffix) }?.removeSuffix(suffix)

        val now = System.currentTimeMillis()
        val prefEditor = livePrefs.edit()
            .putString("wallpaper_path", first.absolutePath)
            .putBoolean("interactive", false)
            .putLong("changed_at", now)
            .putLong("daily_last_rotation", now)
        if (seedSceneId != null) prefEditor.putString("scene_id", seedSceneId)
        else prefEditor.remove("scene_id")
        prefEditor.apply()

        val notify = Intent("com.orbix.pixora.WALLPAPER_PATH_CHANGED")
            .setPackage(applicationContext.packageName)
            .putExtra("wallpaper_path", first.absolutePath)
        if (seedSceneId != null) notify.putExtra("scene_id", seedSceneId)
        else notify.putExtra("clear_scene", true)
        applicationContext.sendBroadcast(notify)
        Log.d(TAG, "Daily seeded with ${first.name}${if (seedSceneId != null) " (scene)" else ""}")
    }

    /**
     * Download up to [maxNew] catalog images that aren't cached yet, so the
     * in-service rotation always has fresh material. No wallpaper apply here.
     */
    // Bumped maxNew default 5 → 10 (2026-06-09) so the cache fills up to
    // MAX_CACHED_WALLPAPERS (25) in 2-3 worker runs instead of 5+. Catch-up
    // is faster when user activates Daily or when new catalog items appear.
    private fun prefetchToCache(entries: List<String>, maxNew: Int = 10) {
        val cacheDir = getWallpaperCacheDir()
        val cachedNames = cacheDir.listFiles()
            ?.filter { it.extension != "tmp" }
            ?.map { it.name }
            ?.toSet() ?: emptySet()

        var downloaded = 0
        for (entry in entries.shuffled()) {
            if (downloaded >= maxNew) break
            val parts = entry.split("|")
            if (parts.size < 2) continue
            val file = parts[1]
            // Type tag — format: "id|file|glow|type". Missing 4th = static.
            val type = parts.getOrNull(3) ?: "static"
            // 2026-06-10 — skip live entries. Daily no longer rotates videos
            // (product decision: live = manual + ad). Belt-and-suspenders:
            // even if the Dart layer accidentally sent a "live" entry, we
            // refuse to download it so the on-device cache stays mp4-free
            // and the maybeRotateDaily filter has nothing to defend against.
            // 2026-07-07 — skip scenes too. canvas_scene content (spec + layers
            // + sprites) is downloaded by Dart's SceneSpecService, and Dart
            // writes the "<id>__scene.webp" marker into this cache. The worker
            // never downloads scenes. Cross-version safe: an old worker seeing
            // type=scene skips here (or would 404 on the image bucket anyway).
            if (type == "live" || type == "scene") continue
            val targetName = file.replace("/", "_")
            if (targetName in cachedNames) continue // already cached

            val targetFile = File(cacheDir, targetName)
            val tempFile = File(cacheDir, "$targetName.tmp")
            val url = "$SUPABASE_BUCKET_BASE/$BUCKET_IMAGES/$file"
            if (downloadFile(url, tempFile)) {
                tempFile.renameTo(targetFile)
                downloaded++
                Log.d(TAG, "Prefetched: $targetName")
            }
        }
        Log.d(TAG, "Prefetch: $downloaded new files (cache had ${cachedNames.size})")
    }

    private fun downloadFile(url: String, target: File): Boolean {
        var conn: HttpURLConnection? = null
        return try {
            target.parentFile?.mkdirs()
            conn = URL(url).openConnection() as HttpURLConnection
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
        } finally {
            conn?.disconnect()
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
            // Protect BOTH the auto-rotate current_path AND the live wallpaper
            // path — the in-service rotation may be showing a cached file right
            // now, and deleting it would leave the wallpaper blank.
            val protectedPaths = setOfNotNull(
                prefs.getString("current_path", "")?.takeIf { it.isNotEmpty() },
                applicationContext
                    .getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                    .getString("wallpaper_path", "")?.takeIf { it.isNotEmpty() },
            )
            val toDelete = files.size - maxCached
            var deleted = 0
            for (file in files) {
                if (deleted >= toDelete) break
                if (file.absolutePath !in protectedPaths) {
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

        val protectedPaths = setOfNotNull(
            prefs.getString("current_path", "")?.takeIf { it.isNotEmpty() },
            applicationContext
                .getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                .getString("wallpaper_path", "")?.takeIf { it.isNotEmpty() },
        )
        val toDelete = maxOf(0, files.size - keepCount)
        var deleted = 0
        for (file in files) {
            if (deleted >= toDelete) break
            if (file.absolutePath !in protectedPaths) {
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
        const val WORK_NAME = "pixora_auto_rotate"              // immediate one-shot prefetch
        const val WORK_NAME_PERIODIC = "pixora_auto_rotate_periodic" // 6h refresh
        const val PREFS_NAME = "pixora_auto_rotate"
        // 2026-06-09 (Phase 4 — live + static + panoramic):
        // Bumped from 10 → 25 to match DAILY_DISK_MAX in the wallpaper
        // service. With 10% live ratio and a typical mix of static +
        // panoramic + live, 25 gives 2-3× more variety per cycle so the
        // seen-set reset is less frequent (better perceived randomness).
        // Disk impact: 25 × avg 250 KB = ~6 MB (live videos pull avg up
        // to ~1 MB each, but they're rare).
        private const val MAX_CACHED_WALLPAPERS = 25
        private const val PREFETCH_PERIOD_HOURS = 6L
        private const val SUPABASE_BUCKET_BASE =
            "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public"
        private const val BUCKET_IMAGES = "wallpaper-images"
        private const val BUCKET_VIDEOS = "wallpaper-videos"
        // Back-compat alias used by entries that don't carry a type field.
        private const val SUPABASE_STORAGE_BASE =
            "$SUPABASE_BUCKET_BASE/$BUCKET_IMAGES"

        private fun networkConstraints() = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        /**
         * Activate Pixora Daily. Stores the catalog + interval + enabled flag
         * (the interval is read by PixoraWallpaperService for the actual
         * rotation), fires an immediate prefetch so the cache is stocked, and
         * schedules a 6h periodic prefetch to keep content fresh.
         *
         * @param catalogData List of "id|imageFile|glowColor" strings
         * @param intervalMinutes Minutes between rotations (used by the SERVICE)
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

            // 2026-06-22 — Fix: limpiar el filesystem cache cuando cambia la
            // category O cuando el cache contiene archivos cuyo basename NO está
            // en el catalog actual. El catalog de SharedPrefs sí se actualiza,
            // pero la rotación in-service pickea de `auto_rotate_cache/` que
            // tiene archivos del category anterior (Seiya/Elvira aparecían en
            // PAISAJES por esto). Forzamos re-download del prefetch worker.
            val previousCategory = prefs.getString("category", null)
            val cacheDir = File(context.filesDir, "auto_rotate_cache")
            val catalogIds = catalogData.mapNotNull { line ->
                line.split("|").firstOrNull()
            }.toSet()

            val shouldClear = previousCategory != category || run {
                // Cache contains files whose ID prefix isn't in the new catalog
                val cachedNames = cacheDir.listFiles()
                    ?.map { it.nameWithoutExtension }
                    ?.filter { !it.endsWith(".tmp") } ?: emptyList()
                cachedNames.any { name ->
                    catalogIds.none { id -> name.startsWith(id) }
                }
            }

            if (shouldClear && cacheDir.exists()) {
                val deleted = cacheDir.listFiles()?.count { it.delete() } ?: 0
                Log.d(TAG, "Cache mismatch ($previousCategory → $category): " +
                    "cleared $deleted stale files")
                prefs.edit().remove("current_path").apply()
                context.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                    .edit().remove("wallpaper_path").apply()
            }

            val editor = prefs.edit()
                .putString("catalog_json", catalogData.joinToString("\n"))
                .putInt("interval_minutes", intervalMinutes)
                .putInt("target", target)
                .putBoolean("enabled", true)
            if (category != null) editor.putString("category", category)
            else editor.remove("category")
            editor.apply()

            val wm = WorkManager.getInstance(context)

            // Immediate prefetch — stock the cache for the first rotations.
            val immediate = OneTimeWorkRequestBuilder<AutoRotateWorker>()
                .setConstraints(networkConstraints())
                .addTag(WORK_NAME)
                .build()
            wm.enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, immediate)

            // Periodic prefetch every 6h — best-effort fresh content.
            val periodic = PeriodicWorkRequestBuilder<AutoRotateWorker>(
                PREFETCH_PERIOD_HOURS, TimeUnit.HOURS
            )
                .setConstraints(networkConstraints())
                .addTag(WORK_NAME_PERIODIC)
                .build()
            wm.enqueueUniquePeriodicWork(
                WORK_NAME_PERIODIC,
                ExistingPeriodicWorkPolicy.UPDATE,
                periodic
            )

            Log.d(
                TAG,
                "Daily started: ${catalogData.size} wallpapers · rotation every " +
                    "${intervalMinutes}min (in-service) · prefetch every ${PREFETCH_PERIOD_HOURS}h"
            )
            return true
        }

        /**
         * Refresh the catalog data WITHOUT touching the wallpaper component,
         * killing the :wallpaper process, or showing the live wallpaper
         * picker. Used by the Flutter cold-start `refreshIfRunning()` flow so
         * new wallpapers in Supabase flow into the active Daily rotation
         * without the user having to toggle Daily off/on.
         *
         * Critical: must NOT call ensureLiveWallpaperActive(). If Pixora was
         * tumbled out of being the live wallpaper (Android safety fallback
         * after a crash), calling start() would trigger the system picker on
         * every cold start — exactly the bug we're fixing here.
         *
         * No-op if Daily isn't enabled.
         */
        fun updateCatalog(
            context: Context,
            catalogData: List<String>,
            intervalMinutes: Int? = null,
            target: Int? = null,
            category: String? = null
        ): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (!prefs.getBoolean("enabled", false)) {
                Log.d(TAG, "updateCatalog skipped — Daily not enabled")
                return false
            }
            val editor = prefs.edit()
                .putString("catalog_json", catalogData.joinToString("\n"))
            if (intervalMinutes != null) editor.putInt("interval_minutes", intervalMinutes)
            if (target != null) editor.putInt("target", target)
            // category null is meaningful (all-categories), so we don't touch
            // it here — the previous value stays.
            editor.apply()
            Log.d(TAG, "Catalog updated: ${catalogData.size} entries (no picker, no kill)")
            return true
        }

        fun stop(context: Context): Boolean {
            val wm = WorkManager.getInstance(context)
            wm.cancelUniqueWork(WORK_NAME)
            wm.cancelUniqueWork(WORK_NAME_PERIODIC)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putBoolean("enabled", false).apply()
            Log.d(TAG, "Daily stopped (prefetch cancelled)")
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
