package com.orbix.pixora

import android.content.Context
import android.util.Log
import androidx.work.*
import org.json.JSONArray
import java.io.File
import java.util.concurrent.TimeUnit

class StoryWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences("pixora_story", Context.MODE_PRIVATE)
        val pathsJson = prefs.getString("image_paths", null) ?: return Result.failure()
        val paths = pathsJson.split("|").filter { it.isNotEmpty() }
        if (paths.isEmpty()) return Result.failure()

        var currentIndex = prefs.getInt("current_index", 0)
        if (currentIndex >= paths.size) currentIndex = 0

        val path = paths[currentIndex]
        val file = File(path)
        if (!file.exists()) {
            Log.e(TAG, "Frame file not found: $path")
            return Result.failure()
        }

        return try {
            // Get caption for this frame from JSON array (preserves UTF-8)
            val captionsJsonArray = prefs.getString("captions_json", null)
            val caption = try {
                val arr = JSONArray(captionsJsonArray ?: "[]")
                if (currentIndex < arr.length()) arr.getString(currentIndex) else ""
            } catch (_: Exception) { "" }

            // Get glow color
            val glowColor = prefs.getString("glow_color", "#7C4DFF") ?: "#7C4DFF"

            // Update live wallpaper prefs — PixoraWallpaperService will pick up the change
            val livePrefs = applicationContext.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
            livePrefs.edit()
                .putString("wallpaper_path", path)
                .putString("glow_color", glowColor)
                .putString("caption", if (caption.isNotEmpty()) caption else null)
                .putLong("changed_at", System.currentTimeMillis())
                .apply()

            // Advance to next frame (loops back to 0)
            val nextIndex = (currentIndex + 1) % paths.size
            prefs.edit().putInt("current_index", nextIndex).apply()

            Log.d(TAG, "Story frame set: ${currentIndex + 1}/${paths.size} -> $path")

            // Schedule next frame
            val intervalMinutes = prefs.getInt("interval_minutes", 30).toLong()
            scheduleNext(applicationContext, intervalMinutes)

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set story wallpaper: ${e.message}")
            Result.failure()
        }
    }

    companion object {
        private const val TAG = "PixoraStory"
        const val WORK_NAME = "pixora_story_rotation"

        fun scheduleNext(context: Context, delayMinutes: Long) {
            val request = OneTimeWorkRequestBuilder<StoryWorker>()
                .setInitialDelay(delayMinutes, TimeUnit.MINUTES)
                .addTag(WORK_NAME)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniqueWork(
                    WORK_NAME,
                    ExistingWorkPolicy.REPLACE,
                    request
                )
        }

        fun startStory(
            context: Context,
            storyId: String,
            imagePaths: List<String>,
            captions: List<String>,
            glowColor: String,
            intervalMinutes: Int
        ): Boolean {
            // Stop auto-rotate so it doesn't interfere with story
            AutoRotateWorker.stop(context)
            Log.d(TAG, "Auto-rotate stopped for story playback")

            val prefs = context.getSharedPreferences("pixora_story", Context.MODE_PRIVATE)

            // Store captions as JSON array to preserve UTF-8 encoding
            val captionsArray = JSONArray()
            captions.forEach { captionsArray.put(it) }

            prefs.edit()
                .putString("story_id", storyId)
                .putString("image_paths", imagePaths.joinToString("|"))
                .putString("captions_json", captionsArray.toString())
                .putString("glow_color", glowColor)
                .putInt("interval_minutes", intervalMinutes)
                .putInt("current_index", 0)
                .putInt("total_frames", imagePaths.size)
                .apply()

            // Set first frame immediately
            val firstRequest = OneTimeWorkRequestBuilder<StoryWorker>()
                .addTag(WORK_NAME)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniqueWork(
                    WORK_NAME,
                    ExistingWorkPolicy.REPLACE,
                    firstRequest
                )

            Log.d(TAG, "Story started: $storyId, ${imagePaths.size} frames, ${intervalMinutes}min interval")
            return true
        }

        fun stopStory(context: Context): Boolean {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            val prefs = context.getSharedPreferences("pixora_story", Context.MODE_PRIVATE)
            prefs.edit().clear().apply()

            // Clear caption from live wallpaper
            val livePrefs = context.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
            livePrefs.edit()
                .remove("caption")
                .putLong("changed_at", System.currentTimeMillis())
                .apply()

            Log.d(TAG, "Story stopped")
            return true
        }

        fun getStatus(context: Context): Map<String, Any?> {
            val prefs = context.getSharedPreferences("pixora_story", Context.MODE_PRIVATE)
            return mapOf(
                "storyId" to prefs.getString("story_id", null),
                "currentIndex" to prefs.getInt("current_index", 0),
                "totalFrames" to prefs.getInt("total_frames", 0),
                "intervalMinutes" to prefs.getInt("interval_minutes", 30)
            )
        }
    }
}
