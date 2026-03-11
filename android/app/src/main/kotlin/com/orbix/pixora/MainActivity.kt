package com.orbix.pixora

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.orbix.pixora/wallpaper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setWallpaper" -> {
                        val path = call.argument<String>("path")
                        val target = call.argument<Int>("target") ?: 0
                        if (path != null) {
                            val success = setWallpaper(path, target)
                            result.success(success)
                        } else {
                            result.error("INVALID_ARG", "Path is required", null)
                        }
                    }
                    "setLiveWallpaper" -> {
                        val path = call.argument<String>("path")
                        val glowColor = call.argument<String>("glowColor") ?: "#7C4DFF"
                        if (path != null) {
                            setLiveWallpaper(path, glowColor)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARG", "Path is required", null)
                        }
                    }
                    "saveToGallery" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            val success = saveToGallery(path)
                            result.success(success)
                        } else {
                            result.error("INVALID_ARG", "Path is required", null)
                        }
                    }
                    "startStory" -> {
                        val storyId = call.argument<String>("storyId") ?: ""
                        val imagePaths = call.argument<List<String>>("imagePaths") ?: emptyList()
                        val captions = call.argument<List<String>>("captions") ?: emptyList()
                        val glowColor = call.argument<String>("glowColor") ?: "#7C4DFF"
                        val intervalMinutes = call.argument<Int>("intervalMinutes") ?: 30
                        val success = StoryWorker.startStory(
                            applicationContext, storyId, imagePaths, captions, glowColor, intervalMinutes
                        )
                        // Set first frame immediately and activate live wallpaper
                        if (success && imagePaths.isNotEmpty()) {
                            val firstCaption = if (captions.isNotEmpty()) captions[0] else null
                            val prefs = getSharedPreferences("pixora_live", 0)
                            prefs.edit()
                                .putString("wallpaper_path", imagePaths[0])
                                .putString("glow_color", glowColor)
                                .putString("caption", firstCaption)
                                .putLong("changed_at", System.currentTimeMillis())
                                .apply()
                            // Launch live wallpaper picker to ensure service is active
                            val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
                            intent.putExtra(
                                WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
                                ComponentName(this@MainActivity, PixoraWallpaperService::class.java)
                            )
                            startActivity(intent)
                        }
                        result.success(success)
                    }
                    "stopStory" -> {
                        val success = StoryWorker.stopStory(applicationContext)
                        result.success(success)
                    }
                    "getStoryStatus" -> {
                        val status = StoryWorker.getStatus(applicationContext)
                        result.success(status)
                    }
                    "startAutoRotate" -> {
                        val catalogData = call.argument<List<String>>("catalogData") ?: emptyList()
                        val intervalMinutes = call.argument<Int>("intervalMinutes") ?: 5
                        val target = call.argument<Int>("target") ?: 2
                        val category = call.argument<String>("category")
                        val success = AutoRotateWorker.start(
                            applicationContext, catalogData, intervalMinutes, target, category
                        )
                        result.success(success)
                    }
                    "stopAutoRotate" -> {
                        val success = AutoRotateWorker.stop(applicationContext)
                        result.success(success)
                    }
                    "getAutoRotateStatus" -> {
                        val status = AutoRotateWorker.getStatus(applicationContext)
                        result.success(status)
                    }
                    "clearAutoRotateCache" -> {
                        AutoRotateWorker.clearCache(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setLiveWallpaper(imagePath: String, glowColor: String) {
        // Stop any active story to prevent it from overriding this wallpaper
        StoryWorker.stopStory(applicationContext)

        // Save config for the WallpaperService to read
        val prefs = getSharedPreferences("pixora_live", 0)
        prefs.edit()
            .putString("wallpaper_path", imagePath)
            .putString("glow_color", glowColor)
            .remove("caption")
            .apply()

        // Launch the live wallpaper picker
        val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
        intent.putExtra(
            WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
            ComponentName(this, PixoraWallpaperService::class.java)
        )
        startActivity(intent)
    }

    private fun setWallpaper(path: String, target: Int): Boolean {
        // Stop any active story to prevent it from interfering
        StoryWorker.stopStory(applicationContext)

        return try {
            val file = File(path)
            if (!file.exists()) return false

            val bitmap = BitmapFactory.decodeFile(path) ?: return false
            val manager = WallpaperManager.getInstance(applicationContext)

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
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun saveToGallery(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false

            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, file.name)
                put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/webp")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Pixora")
                }
            }

            val uri = contentResolver.insert(
                android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                values
            ) ?: return false

            contentResolver.openOutputStream(uri)?.use { output ->
                file.inputStream().use { input ->
                    input.copyTo(output)
                }
            }
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
