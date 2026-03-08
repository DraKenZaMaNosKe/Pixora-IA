package com.orbix.pixora

import android.app.WallpaperManager
import android.content.Context
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import androidx.work.*
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
            val bitmap = BitmapFactory.decodeFile(path) ?: return Result.failure()
            val manager = WallpaperManager.getInstance(applicationContext)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                manager.setBitmap(bitmap, null, true,
                    WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK)
            } else {
                manager.setBitmap(bitmap)
            }
            bitmap.recycle()

            // Advance to next frame
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
            intervalMinutes: Int
        ): Boolean {
            val prefs = context.getSharedPreferences("pixora_story", Context.MODE_PRIVATE)
            prefs.edit()
                .putString("story_id", storyId)
                .putString("image_paths", imagePaths.joinToString("|"))
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
