package com.orbix.pixora

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.provider.MediaStore
import android.provider.Settings as AndroidSettings
import android.graphics.BitmapFactory
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.orbix.pixora/wallpaper"

    /** Check if PixoraWallpaperService is the currently active live wallpaper */
    private fun isPixoraLiveWallpaperActive(): Boolean {
        val manager = WallpaperManager.getInstance(applicationContext)
        val info = manager.wallpaperInfo ?: return false
        return info.component == ComponentName(applicationContext, PixoraWallpaperService::class.java)
    }

    /** Launch the live wallpaper picker only if not already active */
    private fun ensureLiveWallpaperActive() {
        if (!isPixoraLiveWallpaperActive()) {
            val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
            intent.putExtra(
                WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
                ComponentName(this, PixoraWallpaperService::class.java)
            )
            startActivity(intent)
        }
    }

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
                        val interactive = call.argument<Boolean>("interactive") ?: false
                        if (path != null) {
                            setLiveWallpaper(path, glowColor, interactive)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARG", "Path is required", null)
                        }
                    }
                    "checkVideoCodec" -> {
                        result.success(isVideoCodecAvailable())
                    }
                    "resetEngine" -> {
                        try {
                            // Clear frame caches
                            cacheDir.listFiles()
                                ?.filter { it.isDirectory && it.name.startsWith("frames_") }
                                ?.forEach { it.deleteRecursively() }
                            // Clear video caches
                            val liveDir = java.io.File(filesDir, "app_flutter/live_wallpapers")
                            if (liveDir.exists()) liveDir.deleteRecursively()
                            // Reset prefs
                            val prefs = getSharedPreferences("pixora_live", 0)
                            prefs.edit()
                                .putBoolean("interactive", false)
                                .putLong("changed_at", System.currentTimeMillis())
                                .apply()
                            System.gc()
                            android.util.Log.d("PixoraEQ", "Engine reset: caches cleared")
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
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
                            // Only show picker if live wallpaper isn't already active
                            ensureLiveWallpaperActive()
                        }
                        result.success(success)
                    }
                    "setShaderWallpaper" -> {
                        val shaderName = call.argument<String>("shaderName")
                        if (shaderName != null) {
                            // Save shader name for ShaderWallpaperService to read
                            val prefs = getSharedPreferences("pixora_shader", 0)
                            prefs.edit()
                                .putString("shader_name", shaderName)
                                .apply()

                            // Launch shader wallpaper picker (uses ShaderWallpaperService)
                            val intent = android.content.Intent(android.app.WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
                            intent.putExtra(
                                android.app.WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
                                android.content.ComponentName(applicationContext, com.orbix.pixora.gl.ShaderWallpaperService::class.java)
                            )
                            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARG", "shaderName required", null)
                        }
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
                    "startDayCycle" -> {
                        val themeId = call.argument<String>("themeId") ?: ""
                        val morningPath = call.argument<String>("morningPath") ?: ""
                        val afternoonPath = call.argument<String>("afternoonPath") ?: ""
                        val eveningPath = call.argument<String>("eveningPath") ?: ""
                        val nightPath = call.argument<String>("nightPath") ?: ""
                        val glowColor = call.argument<String>("glowColor") ?: "#7C4DFF"
                        val target = call.argument<Int>("target") ?: 0
                        // Stop any active story
                        StoryWorker.stopStory(applicationContext)
                        val success = DayCycleWorker.start(
                            applicationContext, themeId,
                            morningPath, afternoonPath, eveningPath, nightPath,
                            glowColor, target,
                        )
                        // Ensure live wallpaper is active for panoramic scroll
                        if (success) ensureLiveWallpaperActive()
                        result.success(success)
                    }
                    "stopDayCycle" -> {
                        val success = DayCycleWorker.stop(applicationContext)
                        result.success(success)
                    }
                    "getDayCycleStatus" -> {
                        val status = DayCycleWorker.getStatus(applicationContext)
                        result.success(status)
                    }
                    "setRingtone" -> {
                        val path = call.argument<String>("path") ?: ""
                        val title = call.argument<String>("title") ?: "Pixora Ringtone"
                        val type = call.argument<Int>("type") ?: 1
                        val success = setRingtone(path, title, type)
                        result.success(success)
                    }
                    "checkWriteSettingsPermission" -> {
                        result.success(AndroidSettings.System.canWrite(applicationContext))
                    }
                    "requestWriteSettingsPermission" -> {
                        val intent = Intent(AndroidSettings.ACTION_MANAGE_WRITE_SETTINGS)
                        intent.data = Uri.parse("package:$packageName")
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setRingtone(path: String, title: String, type: Int): Boolean {
        return try {
            // Check WRITE_SETTINGS permission
            if (!AndroidSettings.System.canWrite(applicationContext)) {
                val intent = Intent(AndroidSettings.ACTION_MANAGE_WRITE_SETTINGS)
                intent.data = Uri.parse("package:${applicationContext.packageName}")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return false
            }

            val file = File(path)
            if (!file.exists()) {
                android.util.Log.e("PixoraRingtone", "File not found: $path")
                return false
            }

            if (file.length() == 0L) {
                android.util.Log.e("PixoraRingtone", "File is empty: $path")
                return false
            }

            val ringtoneType = when (type) {
                0 -> RingtoneManager.TYPE_RINGTONE
                1 -> RingtoneManager.TYPE_NOTIFICATION
                2 -> RingtoneManager.TYPE_ALARM
                else -> RingtoneManager.TYPE_NOTIFICATION
            }

            val relativePath = when (type) {
                0 -> "Ringtones"
                1 -> "Notifications"
                2 -> "Alarms"
                else -> "Notifications"
            }

            // Clean filename — keep alphanumeric, spaces, dashes, underscores
            var cleanTitle = title.replace(Regex("[^a-zA-Z0-9\\s_-]"), "").trim()
            if (cleanTitle.isEmpty()) cleanTitle = "Pixora_${System.currentTimeMillis()}"
            val fileName = "$cleanTitle.mp3"

            // Delete existing entry with same name to avoid duplicates
            try {
                contentResolver.delete(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    "${MediaStore.MediaColumns.DISPLAY_NAME} = ?",
                    arrayOf(fileName)
                )
            } catch (_: Exception) {}

            // Insert into MediaStore with IS_PENDING=1 so we can write before it's visible
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.TITLE, title)
                put(MediaStore.MediaColumns.MIME_TYPE, "audio/mpeg")
                put(MediaStore.MediaColumns.SIZE, file.length())
                put(MediaStore.Audio.Media.IS_RINGTONE, type == 0 || type == 1 || type == 2)
                put(MediaStore.Audio.Media.IS_NOTIFICATION, type == 0 || type == 1 || type == 2)
                put(MediaStore.Audio.Media.IS_ALARM, type == 0 || type == 1 || type == 2)
                put(MediaStore.Audio.Media.IS_MUSIC, false)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }

            val uri = contentResolver.insert(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                values
            )

            if (uri == null) {
                android.util.Log.e("PixoraRingtone", "MediaStore insert returned null")
                return false
            }

            // Copy file content to MediaStore URI
            val outputStream = contentResolver.openOutputStream(uri)
            if (outputStream == null) {
                android.util.Log.e("PixoraRingtone", "Failed to open output stream for $uri")
                // Clean up the empty entry
                try { contentResolver.delete(uri, null, null) } catch (_: Exception) {}
                return false
            }

            outputStream.use { output ->
                file.inputStream().use { input ->
                    val bytesCopied = input.copyTo(output)
                    android.util.Log.d("PixoraRingtone", "Copied $bytesCopied bytes to MediaStore")
                }
                output.flush()
            }

            // Mark as no longer pending — makes the file visible to the system
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val updateValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                contentResolver.update(uri, updateValues, null, null)
            }

            // Small delay to let MediaStore fully index the file
            Thread.sleep(200)

            // Verify file is accessible before setting as default
            try {
                val testStream = contentResolver.openInputStream(uri)
                val readable = testStream != null
                testStream?.close()
                android.util.Log.d("PixoraRingtone", "File readable after insert: $readable")
            } catch (e: Exception) {
                android.util.Log.w("PixoraRingtone", "File verify failed: ${e.message}")
            }

            // Set as default ringtone/notification/alarm
            RingtoneManager.setActualDefaultRingtoneUri(applicationContext, ringtoneType, uri)
            android.util.Log.d("PixoraRingtone", "setActualDefaultRingtoneUri OK: type=$ringtoneType uri=$uri")

            // Verify it was set correctly
            val verifyUri = RingtoneManager.getActualDefaultRingtoneUri(applicationContext, ringtoneType)
            val verified = verifyUri?.toString() == uri.toString()
            android.util.Log.d("PixoraRingtone", "Verify: expected=$uri actual=$verifyUri match=$verified")

            if (!verified) {
                // Some devices need the content:// URI with the specific ID
                // Try alternative approach: set via Settings.System directly
                try {
                    val settingKey = when (type) {
                        0 -> AndroidSettings.System.RINGTONE
                        1 -> AndroidSettings.System.NOTIFICATION_SOUND
                        2 -> AndroidSettings.System.ALARM_ALERT
                        else -> AndroidSettings.System.NOTIFICATION_SOUND
                    }
                    AndroidSettings.System.putString(contentResolver, settingKey, uri.toString())
                    android.util.Log.d("PixoraRingtone", "Fallback: Settings.System.putString($settingKey, $uri)")
                } catch (e: Exception) {
                    android.util.Log.w("PixoraRingtone", "Settings.System fallback failed: ${e.message}")
                }
            }

            android.util.Log.d("PixoraRingtone", "SUCCESS: '$title' type=$type uri=$uri path=$relativePath")
            true
        } catch (e: Exception) {
            android.util.Log.e("PixoraRingtone", "Failed: ${e.message}", e)
            false
        }
    }

    /** Check if video codec is available, force-release if not */
    private fun isVideoCodecAvailable(): Boolean {
        return try {
            val codec = android.media.MediaCodec.createDecoderByType("video/avc")
            codec.release()
            true
        } catch (e: Exception) {
            android.util.Log.w("PixoraEQ", "Video codec unavailable, forcing release...")
            // Force GC multiple times to release zombie codecs
            System.gc()
            Runtime.getRuntime().gc()
            Thread.sleep(500)
            System.gc()
            // Try again
            try {
                val codec = android.media.MediaCodec.createDecoderByType("video/avc")
                codec.release()
                android.util.Log.d("PixoraEQ", "Codec available after force release")
                true
            } catch (e2: Exception) {
                android.util.Log.e("PixoraEQ", "Codec still unavailable after force release")
                false
            }
        }
    }

    private fun setLiveWallpaper(imagePath: String, glowColor: String, interactive: Boolean = false) {
        // Stop any active story/day cycle to prevent them from overriding this wallpaper
        StoryWorker.stopStory(applicationContext)
        DayCycleWorker.stop(applicationContext)

        // If Auto Play and codec not available, force Explore mode
        var actualInteractive = interactive
        val isVideo = imagePath.endsWith(".mp4", ignoreCase = true)
        if (isVideo && !interactive && !isVideoCodecAvailable()) {
            android.util.Log.w("PixoraEQ", "Codec unavailable — forcing Explore mode")
            actualInteractive = true
        }

        // Save config for the WallpaperService to read
        val prefs = getSharedPreferences("pixora_live", 0)
        prefs.edit()
            .putString("wallpaper_path", imagePath)
            .putString("glow_color", glowColor)
            .putBoolean("interactive", actualInteractive)
            .remove("caption")
            .putLong("changed_at", System.currentTimeMillis())
            .apply()

        // Only show picker if live wallpaper isn't already active
        ensureLiveWallpaperActive()
    }

    private fun setWallpaper(path: String, target: Int): Boolean {
        // Stop any active story/day cycle to prevent them from interfering
        StoryWorker.stopStory(applicationContext)
        DayCycleWorker.stop(applicationContext)

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
