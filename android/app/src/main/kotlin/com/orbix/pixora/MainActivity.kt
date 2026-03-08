package com.orbix.pixora

import android.app.WallpaperManager
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
                    "saveToGallery" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            val success = saveToGallery(path)
                            result.success(success)
                        } else {
                            result.error("INVALID_ARG", "Path is required", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setWallpaper(path: String, target: Int): Boolean {
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
