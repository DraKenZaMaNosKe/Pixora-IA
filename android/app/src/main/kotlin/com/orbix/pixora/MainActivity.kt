package com.orbix.pixora

import android.app.ActivityManager
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.provider.MediaStore
import android.provider.Settings as AndroidSettings
import android.graphics.BitmapFactory
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.orbix.pixora/wallpaper"

    /** Check if PixoraWallpaperService is the currently active live wallpaper */
    private fun isPixoraLiveWallpaperActive(): Boolean {
        val manager = WallpaperManager.getInstance(applicationContext)
        val info = manager.wallpaperInfo ?: return false
        return info.component == ComponentName(applicationContext, PixoraWallpaperService::class.java)
    }

    /** Launch the live wallpaper picker only if not already active */
    private fun ensureLiveWallpaperActive() {
        // Always show picker so user sees preview, even if already active
        val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
        intent.putExtra(
            WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
            ComponentName(this, PixoraWallpaperService::class.java)
        )
        startActivity(intent)
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
                        val glowColor = call.argument<String>("glowColor") ?: "#C9A650"
                        val interactive = call.argument<Boolean>("interactive") ?: false
                        // Optional: data-driven canvas scene id. When provided, the
                        // wallpaper service activates CanvasSceneRenderer with the
                        // spec previously cached at filesDir/scene_specs/<id>.json
                        // by Dart's SceneSpecService.
                        val sceneId = call.argument<String>("sceneId")
                        if (path != null) {
                            setLiveWallpaper(path, glowColor, interactive, sceneId)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARG", "Path is required", null)
                        }
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
                        val glowColor = call.argument<String>("glowColor") ?: "#C9A650"
                        val intervalMinutes = call.argument<Int>("intervalMinutes") ?: 30
                        val success = StoryWorker.startStory(
                            applicationContext, storyId, imagePaths, captions, glowColor, intervalMinutes
                        )
                        // Set first frame immediately and activate live wallpaper
                        if (success && imagePaths.isNotEmpty()) {
                            val firstCaption = if (captions.isNotEmpty()) captions[0] else null
                            val prefs = getSharedPreferences("pixora_live", 0)
                            // commit() (sync) so the file is flushed BEFORE killing the
                            // wallpaper process — apply() races with the kill and the
                            // respawned engine may read stale prefs.
                            // ALSO clear scene_id + interactive so a previously-active
                            // parallax/scene wallpaper doesn't override the story frame.
                            prefs.edit()
                                .putString("wallpaper_path", imagePaths[0])
                                .putString("glow_color", glowColor)
                                .putString("caption", firstCaption)
                                .remove("scene_id")
                                .putBoolean("interactive", false)
                                .putLong("changed_at", System.currentTimeMillis())
                                .commit()

                            // Kill the :wallpaper process so its stale SharedPreferences cache
                            // is discarded. SharedPreferences is NOT multi-process safe —
                            // without this, an engine that was running a previous live wallpaper
                            // (e.g. firefly) keeps showing that wallpaper because its cached
                            // value of wallpaper_path never sees the write from this process.
                            killWallpaperProcess()

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
                        val glowColor = call.argument<String>("glowColor") ?: "#C9A650"
                        val target = call.argument<Int>("target") ?: 0
                        // Stop any active story
                        StoryWorker.stopStory(applicationContext)
                        val success = DayCycleWorker.start(
                            applicationContext, themeId,
                            morningPath, afternoonPath, eveningPath, nightPath,
                            glowColor, target,
                        )
                        if (success) {
                            // Clear scene_id + interactive so a previously-active parallax
                            // wallpaper doesn't override the day-cycle frame. Use commit()
                            // so the file is flushed BEFORE killing the process.
                            val livePrefs = getSharedPreferences("pixora_live", 0)
                            livePrefs.edit()
                                .remove("scene_id")
                                .putBoolean("interactive", false)
                                .putLong("changed_at", System.currentTimeMillis())
                                .commit()

                            // Same multi-process cache reason as startStory —
                            // force :wallpaper to respawn with fresh prefs.
                            killWallpaperProcess()
                            ensureLiveWallpaperActive()
                        }
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
                    "startLunarUpdater" -> {
                        val signIndex = call.argument<Int>("signIndex") ?: -1
                        val glowColor = call.argument<String>("glowColor") ?: "#D4AF37"
                        val success = LunarPhaseWorker.start(
                            applicationContext, signIndex, glowColor,
                        )
                        result.success(success)
                    }
                    "stopLunarUpdater" -> {
                        val success = LunarPhaseWorker.stop(applicationContext)
                        result.success(success)
                    }
                    "getLunarStatus" -> {
                        val status = LunarPhaseWorker.getStatus(applicationContext)
                        result.success(status)
                    }
                    "getOverlayVisibility" -> {
                        val prefs = getSharedPreferences("pixora_live", 0)
                        val map = mapOf(
                            "clock" to prefs.getBoolean("show_clock", true),
                            "battery" to prefs.getBoolean("show_battery", true),
                            "ram" to prefs.getBoolean("show_ram", true),
                            "storage" to prefs.getBoolean("show_storage", true),
                            "equalizer" to prefs.getBoolean("show_equalizer", true),
                        )
                        result.success(map)
                    }
                    "setOverlayVisibility" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<Boolean>("value")
                        if (key == null || value == null) {
                            result.error("INVALID_ARG", "key and value required", null)
                            return@setMethodCallHandler
                        }
                        val allowed = setOf("clock", "battery", "ram", "storage", "equalizer")
                        if (key !in allowed) {
                            result.error("INVALID_ARG", "key must be one of $allowed", null)
                            return@setMethodCallHandler
                        }
                        val prefs = getSharedPreferences("pixora_live", 0)
                        prefs.edit().putBoolean("show_$key", value).apply()
                        // Notify :wallpaper process — SharedPreferences is NOT multi-
                        // process safe, so the engine's cached flags won't refresh
                        // without this broadcast. See tech_sharedprefs_multi_process.md.
                        val intent = Intent("com.orbix.pixora.OVERLAY_SETTINGS_CHANGED")
                            .setPackage(packageName)
                        sendBroadcast(intent)
                        result.success(true)
                    }
                    "getTouchTrail" -> {
                        val prefs = getSharedPreferences("pixora_live", 0)
                        result.success(prefs.getString("touch_trail_style", "aurora"))
                    }
                    "setTouchTrail" -> {
                        val style = call.argument<String>("style") ?: "aurora"
                        val prefs = getSharedPreferences("pixora_live", 0)
                        prefs.edit().putString("touch_trail_style", style).apply()
                        // Reuse the existing overlay-changed broadcast — wallpaper
                        // engine listens to it and re-reads the trail pref too.
                        val intent = Intent("com.orbix.pixora.OVERLAY_SETTINGS_CHANGED")
                            .setPackage(packageName)
                        sendBroadcast(intent)
                        result.success(true)
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

    private fun setLiveWallpaper(
        imagePath: String,
        glowColor: String,
        interactive: Boolean = false,
        sceneId: String? = null,
    ) {
        // Stop any active story/day cycle to prevent them from overriding this wallpaper
        StoryWorker.stopStory(applicationContext)
        DayCycleWorker.stop(applicationContext)

        // Save config for the WallpaperService to read.
        // Use commit() (not apply()) so the file is flushed BEFORE we kill the wallpaper
        // process — otherwise the respawned process might read stale prefs.
        val prefs = getSharedPreferences("pixora_live", 0)
        val edit = prefs.edit()
            .putString("wallpaper_path", imagePath)
            .putString("glow_color", glowColor)
            .putBoolean("interactive", interactive)
            .remove("caption")
            .putLong("changed_at", System.currentTimeMillis())
        // Scene id drives the data-driven CanvasSceneRenderer. Cleared
        // explicitly when null so previous scene mode doesn't persist.
        if (sceneId.isNullOrBlank()) edit.remove("scene_id")
        else edit.putString("scene_id", sceneId)
        edit.commit()

        // For canvas_scene wallpapers with image_layers (parallax scenes
        // like Iah Egyptian), tell Samsung the logical wallpaper is wider
        // than the screen. Samsung's launcher uses this to decide whether
        // to deliver onOffsetsChanged during home page swipes and to
        // composite the wallpaper with horizontal pan — same treatment
        // it gives static panoramic wallpapers via setBitmap.
        // Without this, canvas_scene WallpaperServices stay locked to
        // screen width and the launcher never sends scroll events.
        try {
            val isParallaxScene = !sceneId.isNullOrBlank() && hasImageLayers(sceneId!!)
            val wm = WallpaperManager.getInstance(applicationContext)
            val dm = resources.displayMetrics
            if (isParallaxScene) {
                // 2× screen width matches the reach of typical 2-page home
                // setups (xOffset 0..1 sweeps across the whole logical size).
                wm.suggestDesiredDimensions(dm.widthPixels * 2, dm.heightPixels)
                android.util.Log.d("PixoraEQ", "suggestDesiredDimensions: " +
                    "${dm.widthPixels * 2}x${dm.heightPixels} for parallax scene $sceneId")
            } else {
                // Reset to screen dims for non-parallax wallpapers (videos,
                // shaders, plain canvas scenes) so we don't keep a stale
                // wide-suggestion from a previous parallax scene.
                wm.suggestDesiredDimensions(dm.widthPixels, dm.heightPixels)
            }
        } catch (e: Exception) {
            android.util.Log.w("PixoraEQ", "suggestDesiredDimensions failed: ${e.message}")
        }

        // Kill the wallpaper engine process so Android recreates it with a fresh Surface.
        // This is mandatory because Canvas (image/explore) and MediaPlayer (video) cannot
        // share the same Surface — switching between them corrupts the producer state and
        // setVideoSurfaceTexture fails with -22. Killing forces a clean Surface.
        killWallpaperProcess()

        // Only show picker if live wallpaper isn't already active
        ensureLiveWallpaperActive()
    }

    /** Inspects the scene spec on disk to determine if it declares image_layers
     *  (i.e. parallax background). Used to gate suggestDesiredDimensions to
     *  scenes that actually benefit from a wider logical surface. */
    private fun hasImageLayers(sceneId: String): Boolean = try {
        val f = File(filesDir, "scene_specs/$sceneId.json")
        if (!f.isFile) false
        else {
            val json = org.json.JSONObject(f.readText())
            val layers = json.optJSONArray("image_layers")
            layers != null && layers.length() > 0
        }
    } catch (_: Exception) { false }

    /**
     * Kills the ":wallpaper" process so Android respawns the WallpaperService with
     * a fresh Engine + Surface. Required to switch cleanly between Canvas-based and
     * MediaPlayer-based wallpaper modes (the Surface producer can't be re-bound).
     */
    private fun killWallpaperProcess() {
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return
            val myPid = android.os.Process.myPid()
            val target = "${packageName}:wallpaper"
            am.runningAppProcesses?.forEach { proc ->
                if (proc.processName == target && proc.pid != myPid) {
                    android.util.Log.d("PixoraEQ", "Killing wallpaper process pid=${proc.pid}")
                    android.os.Process.killProcess(proc.pid)
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("PixoraEQ", "killWallpaperProcess: ${e.message}")
        }
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
