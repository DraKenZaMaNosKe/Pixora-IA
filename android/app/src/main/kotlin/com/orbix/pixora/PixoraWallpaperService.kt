package com.orbix.pixora

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.graphics.*
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.wallpaper.WallpaperService
import android.util.Log
import android.view.MotionEvent
import android.view.SurfaceHolder
import com.orbix.pixora.renderers.*
import java.io.File
import kotlin.math.abs

class PixoraWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = PixoraEngine()

    inner class PixoraEngine : Engine(), EqualizerRenderer.AudioCallback {
        private val handler = Handler(Looper.getMainLooper())
        private var wallpaperBitmap: Bitmap? = null
        @Volatile private var scaledBitmap: Bitmap? = null
        private val glowDots = mutableListOf<GlowDot>()
        @Volatile private var drawing = false
        private var surfaceWidth = 0
        private var surfaceHeight = 0
        private var glowColor = Color.parseColor("#C9A650")

        // Bitmap scaling version counter — prevents stale Thread results
        @Volatile private var scaleVersion = 0

        // Panoramic scroll
        private var isPanoramic = false
        @Volatile private var panoramicBitmap: Bitmap? = null
        private var touchStartX = 0f
        private var scrollOffsetPx = 0f
        private var targetScrollPx = 0f
        private var scrollVelocity = 0f

        // Animation
        private var animationPhase = 0f
        private var idleMode = false
        private var isRainWallpaper = false
        private var currentWallpaperPath: String? = null

        // Video wallpaper (MediaPlayer for Auto Play — no codec conflicts)
        private var mediaPlayer: MediaPlayer? = null
        @Volatile private var isVideoWallpaper = false
        private var isInteractive = false // touch scrubbing mode

        // Frame scrub mode: extracted frames rendered via Canvas
        private val frameScrubRenderer = FrameScrubRenderer()
        private var isFrameMode = false // true when interactive uses extracted frames
        private val frameScrubUpdateRunnable = object : Runnable {
            override fun run() {
                if (!isFrameMode || !frameScrubRenderer.isReady) return
                if (frameScrubRenderer.update()) {
                    drawFrame()
                    // Only keep running if animation is active (seeking to target)
                    handler.postDelayed(this, 30)
                }
                // If update() returns false (no movement), stop loop — saves CPU
                // Will be restarted on next touch event
            }
        }

        // Lock for bitmap field access across threads
        private val bitmapLock = Object()

        // Lock for ExoPlayer start/stop synchronization
        private val videoLock = Object()

        // Video loop fade: darkens near end, brightens at start
        // NOTE: Fade overlay was REMOVED. It used Canvas drawing on the SAME Surface
        // where MediaPlayer renders the video, which corrupted the surface producer state
        // and caused setVideoSurfaceTexture to fail with -22 on the next video install.
        // Canvas (CPU producer) and MediaPlayer (hardware producer) cannot share a Surface.
        // For loop fade-in/out, bake it into the video file with ffmpeg:
        //   ffmpeg -i in.mp4 -vf "fade=in:0:12,fade=out:st=4.5:d=0.5" out.mp4
        private var cachedDuration = 0L

        // Pre-allocated paint for glow dots
        private val glowDotPaint = Paint(Paint.ANTI_ALIAS_FLAG)

        // Renderers
        private val clockRenderer = ClockRenderer()
        private val equalizerRenderer = EqualizerRenderer(applicationContext)
        private val rainRenderer = RainEffectRenderer()
        private val batteryIndicator = BatteryIndicator(applicationContext)
        private val systemRings = SystemRingsRenderer(applicationContext)
        private val captionOverlay = CaptionOverlay()
        private val aquariumRenderer = AquariumRenderer(applicationContext)
        private val bubbleRenderer = BubbleRenderer()
        private val fireflyRenderer = FireflyRenderer()
        private val jellyfishRenderer = JellyfishRenderer(applicationContext)
        private var isAquariumMode = false
        private var isFireflyMode = false
        private var isJellyfishMode = false

        // Any wallpaper that uses code-driven animated sprites over a static background.
        // Keeps the engine at full FPS so animations and the clock second-hand stay smooth.
        private val hasAnimatedCanvasOverlay: Boolean
            get() = isAquariumMode || isFireflyMode || isJellyfishMode

        // Auto-rotate: listen for wallpaper path changes from AutoRotateWorker
        private var prefsListener: SharedPreferences.OnSharedPreferenceChangeListener? = null

        // Cached KeyguardManager — authoritative source for lock state in drawFrame.
        // Avoids getSystemService() overhead every frame.
        private val keyguardManager by lazy {
            getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        }

        // User-controlled overlay visibility — loaded from pixora_live prefs,
        // refreshed via OVERLAY_SETTINGS_CHANGED broadcast so Settings toggles take
        // effect instantly (the :wallpaper process can't see main-process pref
        // writes directly — see tech_sharedprefs_multi_process.md).
        @Volatile private var showClock = true
        @Volatile private var showBattery = true
        @Volatile private var showEqualizer = true

        private val overlaySettingsReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                loadOverlaySettings()
                if (drawing) handler.post { drawFrame() }
            }
        }

        // Receives wallpaper-path changes from Workers running in the main process
        // (StoryWorker, AutoRotateWorker, DayCycleWorker). We can't rely on
        // OnSharedPreferenceChangeListener because SharedPreferences is not
        // multi-process safe — writes from the main process don't notify :wallpaper
        // and the cache stays stale. Trick: the Worker puts the new values in Intent
        // extras, and we re-apply them to prefs from inside :wallpaper. Our own
        // apply() updates the local cache (disk write is a no-op since the XML
        // already has these values) AND fires the in-process prefs listener, which
        // handles the debounced loadWallpaperImage() + createScaledBitmap() for us.
        private val wallpaperPathReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val newPath = intent?.getStringExtra("wallpaper_path") ?: return
                val newGlow = intent.getStringExtra("glow_color")
                val newCaption = intent.getStringExtra("caption")
                val prefs = applicationContext.getSharedPreferences("pixora_live", 0)
                val editor = prefs.edit().putString("wallpaper_path", newPath)
                if (newGlow != null) editor.putString("glow_color", newGlow)
                editor.putString("caption", newCaption)
                editor.putLong("changed_at", System.currentTimeMillis())
                editor.apply()
            }
        }

        private fun loadOverlaySettings() {
            val prefs = applicationContext.getSharedPreferences("pixora_live", 0)
            showClock = prefs.getBoolean("show_clock", true)
            showBattery = prefs.getBoolean("show_battery", true)
            showEqualizer = prefs.getBoolean("show_equalizer", true)
            systemRings.showRam = prefs.getBoolean("show_ram", true)
            systemRings.showStorage = prefs.getBoolean("show_storage", true)
        }

        // Set true only for the "last frame before sleep" so the cached frame Android
        // shows on the lock screen has overlays hidden. Reset right after the draw.
        // Everything else defers to KeyguardManager.isKeyguardLocked.
        @Volatile private var forceHideOverlays = false

        // Broadcast receiver only forces a redraw on screen events — doesn't own state.
        // This way a missed ACTION_USER_PRESENT (which happens on some Samsung configs
        // with fast biometric unlock) doesn't leave overlays permanently hidden.
        private val keyguardReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (drawing) handler.post { drawFrame() }
            }
        }

        private val drawRunnable = object : Runnable {
            override fun run() {
                if (drawing) {
                    drawFrame()
                    // In frame mode (Explore), use slow refresh — only clock needs updating
                    val delay = when {
                        isFrameMode -> IDLE_FRAME_DELAY // 1fps — clock updates every second
                        idleMode -> IDLE_FRAME_DELAY
                        else -> FRAME_DELAY
                    }
                    handler.postDelayed(this, delay)
                }
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder?) {
            super.onCreate(surfaceHolder)
            setTouchEventsEnabled(true)
            equalizerRenderer.audioCallback = this
            loadOverlaySettings()
            loadWallpaperImage()
            batteryIndicator.registerBatteryReceiver()
            registerPrefsListener()
            registerKeyguardReceiver()
            registerOverlaySettingsReceiver()
            registerWallpaperPathReceiver()
            Log.d(TAG, "Engine onCreate")
        }

        private fun registerWallpaperPathReceiver() {
            val filter = IntentFilter("com.orbix.pixora.WALLPAPER_PATH_CHANGED")
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    applicationContext.registerReceiver(
                        wallpaperPathReceiver, filter, Context.RECEIVER_NOT_EXPORTED
                    )
                } else {
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    applicationContext.registerReceiver(wallpaperPathReceiver, filter)
                }
            } catch (e: Exception) {
                Log.w(TAG, "wallpaperPathReceiver register failed: ${e.message}")
            }
        }

        private fun unregisterWallpaperPathReceiver() {
            try {
                applicationContext.unregisterReceiver(wallpaperPathReceiver)
            } catch (_: Exception) { /* not registered */ }
        }

        private fun registerOverlaySettingsReceiver() {
            val filter = IntentFilter("com.orbix.pixora.OVERLAY_SETTINGS_CHANGED")
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    applicationContext.registerReceiver(
                        overlaySettingsReceiver, filter, Context.RECEIVER_NOT_EXPORTED
                    )
                } else {
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    applicationContext.registerReceiver(overlaySettingsReceiver, filter)
                }
            } catch (e: Exception) {
                Log.w(TAG, "overlaySettingsReceiver register failed: ${e.message}")
            }
        }

        private fun unregisterOverlaySettingsReceiver() {
            try {
                applicationContext.unregisterReceiver(overlaySettingsReceiver)
            } catch (_: Exception) { /* not registered */ }
        }

        private fun registerKeyguardReceiver() {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    applicationContext.registerReceiver(
                        keyguardReceiver, filter, Context.RECEIVER_NOT_EXPORTED
                    )
                } else {
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    applicationContext.registerReceiver(keyguardReceiver, filter)
                }
            } catch (e: Exception) {
                Log.w(TAG, "keyguardReceiver register failed: ${e.message}")
            }
        }

        private fun unregisterKeyguardReceiver() {
            try {
                applicationContext.unregisterReceiver(keyguardReceiver)
            } catch (_: Exception) { /* not registered */ }
        }

        // EqualizerRenderer.AudioCallback
        override fun onAudioStarted() {
            if (!drawing) {
                equalizerRenderer.silentFrames = 0
                drawing = true
                handler.post(drawRunnable)
            }
        }

        @Volatile private var pendingReload: Runnable? = null

        private fun registerPrefsListener() {
            val prefs = applicationContext.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
            prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                if (key == "changed_at" || key == "wallpaper_path") {
                    Log.d(TAG, "Prefs changed: $key — scheduling reload")
                    // Debounce: only reload once after 300ms of no changes
                    pendingReload?.let { handler.removeCallbacks(it) }
                    val reload = Runnable {
                        Log.d(TAG, "Executing debounced reload")
                        loadWallpaperImage()
                        if (!isVideoWallpaper) createScaledBitmap()
                    }
                    pendingReload = reload
                    handler.postDelayed(reload, 300)
                }
            }
            prefs.registerOnSharedPreferenceChangeListener(prefsListener)
        }

        private fun unregisterPrefsListener() {
            prefsListener?.let {
                val prefs = applicationContext.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                prefs.unregisterOnSharedPreferenceChangeListener(it)
            }
            prefsListener = null
        }

        private fun loadWallpaperImage() {
            try {
                val prefs = applicationContext.getSharedPreferences("pixora_live", 0)
                val path = prefs.getString("wallpaper_path", null)
                val color = prefs.getString("glow_color", "#C9A650")
                val caption = prefs.getString("caption", null)
                isInteractive = prefs.getBoolean("interactive", false)

                // Reset animated overlay state on wallpaper change
                aquariumRenderer.recycle()
                bubbleRenderer.reset()
                fireflyRenderer.reset()
                jellyfishRenderer.recycle()

                // Update caption: show immediately on change, then cycle every 3 min
                if (caption != captionOverlay.currentCaption) {
                    captionOverlay.currentCaption = caption
                    val now = System.currentTimeMillis()
                    captionOverlay.lastCaptionChange = now
                    captionOverlay.lastCaptionShowTime = now
                }

                color?.let {
                    try { glowColor = Color.parseColor(it) } catch (_: Exception) {}
                }

                // Pick clock style based on wallpaper path hash
                clockRenderer.clockStyle = abs((path ?: "").hashCode()) % 4
                currentWallpaperPath = path
                isRainWallpaper = path?.contains("lofi_girl_rain") == true

                // Firefly mode: glowing fireflies + luna moths over enchanted forest
                isFireflyMode = path?.contains("firefly") == true
                if (isFireflyMode && surfaceWidth > 0 && surfaceHeight > 0) {
                    fireflyRenderer.surfaceWidth = surfaceWidth
                    fireflyRenderer.surfaceHeight = surfaceHeight
                    aquariumRenderer.surfaceWidth = surfaceWidth
                    aquariumRenderer.surfaceHeight = surfaceHeight
                    // moth_a, moth_d face left (canonical); moth_b, moth_c face right (mirror)
                    aquariumRenderer.loadFishSprites("aquarium/firefly/moth_a")
                    aquariumRenderer.loadFishSprites("aquarium/firefly/moth_b", mirrorOnLoad = true)
                    aquariumRenderer.loadFishSprites("aquarium/firefly/moth_c", mirrorOnLoad = true)
                    aquariumRenderer.loadFishSprites("aquarium/firefly/moth_d")
                    if (aquariumRenderer.fishCount == 0) {
                        aquariumRenderer.addFish(1, "aquarium/firefly/moth_a", scaleMin = 0.6f, scaleMax = 0.8f, speedMin = 0.5f, speedMax = 1.5f)
                        aquariumRenderer.addFish(1, "aquarium/firefly/moth_b", scaleMin = 0.5f, scaleMax = 0.7f, speedMin = 0.5f, speedMax = 1.5f)
                        aquariumRenderer.addFish(1, "aquarium/firefly/moth_c", scaleMin = 0.5f, scaleMax = 0.7f, speedMin = 0.5f, speedMax = 1.5f)
                        aquariumRenderer.addFish(1, "aquarium/firefly/moth_d", scaleMin = 0.6f, scaleMax = 0.8f, speedMin = 0.5f, speedMax = 1.5f)
                        // Owl: stationary, perched on upper-right branch
                        aquariumRenderer.addFish(1, "aquarium/firefly/owl", scaleMin = 0.7f, scaleMax = 0.7f, speedMin = 0f, speedMax = 0f)
                        aquariumRenderer.setLastFishPosition(surfaceWidth * 0.78f, surfaceHeight * 0.02f)
                    }
                    Log.d(TAG, "Firefly mode activated: 4 luna moths + 1 owl + fireflies (${surfaceWidth}x${surfaceHeight})")
                }

                // Jellyfish mode: bioluminescent jellies rise through deep-ocean column
                isJellyfishMode = path?.contains("jellyfish") == true
                if (isJellyfishMode && surfaceWidth > 0 && surfaceHeight > 0) {
                    jellyfishRenderer.surfaceWidth = surfaceWidth
                    jellyfishRenderer.surfaceHeight = surfaceHeight
                    // Main species: blue moon jellies (always present)
                    jellyfishRenderer.loadSprites("aquarium/jellyfish_blue")
                    // Optional species: load if present. Silently skip otherwise.
                    jellyfishRenderer.loadSprites("aquarium/jellyfish_gold")
                    if (jellyfishRenderer.jellyCount == 0) {
                        // Blue moon: 2 distant, 3 mid, 1 big foreground
                        jellyfishRenderer.addJellies(
                            count = 2,
                            spriteFolder = "aquarium/jellyfish_blue",
                            scaleMin = 0.35f, scaleMax = 0.5f,
                            speedMin = 0.2f, speedMax = 0.4f,
                            swayAmpMin = 10f, swayAmpMax = 20f,
                        )
                        jellyfishRenderer.addJellies(
                            count = 3,
                            spriteFolder = "aquarium/jellyfish_blue",
                            scaleMin = 0.6f, scaleMax = 0.85f,
                            speedMin = 0.35f, speedMax = 0.7f,
                            swayAmpMin = 20f, swayAmpMax = 35f,
                        )
                        jellyfishRenderer.addJellies(
                            count = 1,
                            spriteFolder = "aquarium/jellyfish_blue",
                            scaleMin = 1.0f, scaleMax = 1.3f,
                            speedMin = 0.5f, speedMax = 0.8f,
                            swayAmpMin = 30f, swayAmpMax = 50f,
                        )
                        // Golden lion's mane: 1 hero piece (only spawns if sprites loaded)
                        if (jellyfishRenderer.hasSprites("aquarium/jellyfish_gold")) {
                            jellyfishRenderer.addJellies(
                                count = 1,
                                spriteFolder = "aquarium/jellyfish_gold",
                                scaleMin = 0.9f, scaleMax = 1.15f,
                                speedMin = 0.25f, speedMax = 0.5f,
                                swayAmpMin = 25f, swayAmpMax = 45f,
                            )
                        }
                    }

                    // Rising bubble streams — calm abyss respiration
                    bubbleRenderer.surfaceWidth = surfaceWidth
                    bubbleRenderer.surfaceHeight = surfaceHeight

                    // Occasional bioluminescent squid (horizontal jetter)
                    aquariumRenderer.surfaceWidth = surfaceWidth
                    aquariumRenderer.surfaceHeight = surfaceHeight
                    aquariumRenderer.loadFishSprites("aquarium/squid_bio")
                    if (aquariumRenderer.fishCount == 0) {
                        aquariumRenderer.addFish(
                            count = 1,
                            spriteFolder = "aquarium/squid_bio",
                            scaleMin = 0.5f, scaleMax = 0.6f,
                            speedMin = 0.8f, speedMax = 1.2f,
                        )
                    }

                    Log.d(TAG, "Jellyfish mode activated: jellies + bubbles + squid over ocean abyss (${surfaceWidth}x${surfaceHeight})")
                }

                // Aquarium mode: animated fish over background image
                isAquariumMode = path?.contains("aquarium") == true
                if (isAquariumMode && surfaceWidth > 0 && surfaceHeight > 0) {
                    aquariumRenderer.surfaceWidth = surfaceWidth
                    aquariumRenderer.surfaceHeight = surfaceHeight
                    aquariumRenderer.loadFishSprites("aquarium/betta")
                    aquariumRenderer.loadFishSprites("aquarium/angel", mirrorOnLoad = true)
                    aquariumRenderer.loadFishSprites("aquarium/neon", mirrorOnLoad = true)
                    bubbleRenderer.surfaceWidth = surfaceWidth
                    bubbleRenderer.surfaceHeight = surfaceHeight
                    if (aquariumRenderer.fishCount == 0) {
                        aquariumRenderer.addFish(3, "aquarium/betta")
                        aquariumRenderer.addFish(3, "aquarium/angel")
                        // Neon tetra school: 5 small, fast fish
                        aquariumRenderer.addFish(
                            count = 5,
                            spriteFolder = "aquarium/neon",
                            scaleMin = 0.8f,
                            scaleMax = 1.3f,
                            speedMin = 2f,
                            speedMax = 4f,
                        )
                        Log.d(TAG, "Aquarium mode activated: 3 betta + 3 angelfish + 5 neon tetras (${surfaceWidth}x${surfaceHeight})")
                    }
                }

                if (path != null) {
                    val file = File(path)
                    Log.d(TAG, "loadWallpaperImage: path=$path exists=${file.exists()} len=${if(file.exists()) file.length() else -1}")
                    if (file.exists()) {
                        // Frames directory: pre-downloaded images for Explore mode
                        if (file.isDirectory) {
                            isInteractive = true
                            isVideoWallpaper = true
                            startVideoWallpaper(path)
                            return
                        }

                        val isVideo = path.endsWith(".mp4", ignoreCase = true) ||
                            path.endsWith(".webm", ignoreCase = true)

                        if (isVideo) {
                            startVideoWallpaper(path)
                            return
                        }

                        // Stop video/shader if switching to image
                        stopVideoWallpaper()
                        // (shaders use separate service)

                        val opts = BitmapFactory.Options()
                        opts.inJustDecodeBounds = true
                        BitmapFactory.decodeFile(path, opts)
                        Log.d(TAG, "decodeFile bounds: ${opts.outWidth}x${opts.outHeight} mimeType=${opts.outMimeType}")

                        if (opts.outWidth <= 0 || opts.outHeight <= 0) {
                            Log.e(TAG, "Invalid bitmap dimensions: ${opts.outWidth}x${opts.outHeight}")
                            return
                        }

                        // Use actual surface height, or screen height as fallback
                        val targetH = if (surfaceHeight > 0) surfaceHeight else
                            resources.displayMetrics.heightPixels
                        opts.inSampleSize = calculateInSampleSize(opts, opts.outWidth, targetH)
                        opts.inJustDecodeBounds = false
                        opts.inPreferredConfig = Bitmap.Config.RGB_565

                        val decoded = try {
                            BitmapFactory.decodeFile(path, opts)
                        } catch (oom: OutOfMemoryError) {
                            Log.e(TAG, "OOM decoding bitmap, retrying with higher sample: ${oom.message}")
                            opts.inSampleSize *= 2
                            BitmapFactory.decodeFile(path, opts)
                        }

                        if (decoded != null) {
                            wallpaperBitmap = decoded
                            Log.d(TAG, "Bitmap decoded OK: ${decoded.width}x${decoded.height} config=${decoded.config}")
                        } else {
                            Log.e(TAG, "Failed to decode bitmap: $path (sampleSize=${opts.inSampleSize})")
                        }
                    } else {
                        Log.e(TAG, "loadWallpaperImage: FILE NOT FOUND at $path")
                    }
                } else {
                    Log.w(TAG, "loadWallpaperImage: path is null in SharedPreferences")
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadWallpaperImage error: ${e.message}")
            }
        }

        // Guard against multiple simultaneous video starts
        @Volatile private var videoStarting = false

        private var videoRetryCount = 0
        private val MAX_VIDEO_RETRIES = 10

        private fun startVideoWallpaper(path: String) {
            synchronized(videoLock) {
                if (videoStarting) return
                videoStarting = true
            }
            Log.d(TAG, "Starting video: $path")

            // Stop canvas drawing
            drawing = false
            handler.removeCallbacks(drawRunnable)
            equalizerRenderer.releaseVisualizer()
            synchronized(bitmapLock) {
                scaledBitmap = null
                panoramicBitmap = null
                wallpaperBitmap = null
            }

            stopVideoWallpaper()
            isVideoWallpaper = true

            // Explore mode: load pre-downloaded frames (no codec needed)
            if (isInteractive) {
                if (isFrameMode) {
                    synchronized(videoLock) { videoStarting = false }
                    return
                }
                isFrameMode = true
                synchronized(videoLock) { videoStarting = false }

                val pathFile = File(path)
                if (pathFile.isDirectory) {
                    Log.d(TAG, "Explore: loading frames from $path")
                    if (frameScrubRenderer.loadFromDirectory(path)) {
                        drawing = true
                        handler.post(drawRunnable)
                        handler.post(frameScrubUpdateRunnable)
                    } else {
                        isFrameMode = false
                    }
                }
                return
            }

            // Auto Play: use MediaPlayer — wait for valid surface
            val surface = surfaceHolder?.surface
            if (surface == null || !surface.isValid) {
                // Surface not ready yet — retry shortly (reset guard so retry can enter)
                synchronized(videoLock) { videoStarting = false }
                if (videoRetryCount < MAX_VIDEO_RETRIES) {
                    videoRetryCount++
                    Log.d(TAG, "Surface not ready, retry $videoRetryCount/$MAX_VIDEO_RETRIES")
                    handler.postDelayed({ startVideoWallpaper(path) }, 200)
                } else {
                    Log.e(TAG, "Surface never became ready after $MAX_VIDEO_RETRIES retries")
                    videoRetryCount = 0
                    isVideoWallpaper = false
                }
                return
            }
            videoRetryCount = 0

            val videoFile = File(path)
            if (!videoFile.exists()) {
                Log.e(TAG, "Video not found: $path")
                synchronized(videoLock) { videoStarting = false }
                isVideoWallpaper = false
                return
            }

            var mp: MediaPlayer? = null
            try {
                // Re-check surface validity right before use (can become invalid between check and use)
                val currentSurface = surfaceHolder?.surface
                if (currentSurface == null || !currentSurface.isValid) {
                    Log.w(TAG, "Surface became invalid before MediaPlayer setup")
                    synchronized(videoLock) { videoStarting = false }
                    isVideoWallpaper = false
                    return
                }
                val player = MediaPlayer()
                mp = player
                player.setDataSource(path)
                player.setSurface(currentSurface)
                player.setVolume(0f, 0f)
                player.isLooping = true

                player.setOnPreparedListener {
                    Log.d(TAG, "MediaPlayer READY: $path")
                    synchronized(videoLock) {
                        mediaPlayer = player
                        videoStarting = false
                    }
                    try { player.start() } catch (e: Exception) { Log.e(TAG, "start failed: ${e.message}") }
                }

                player.setOnErrorListener { _, what, extra ->
                    Log.e(TAG, "MediaPlayer error: what=$what extra=$extra")
                    releaseMediaPlayerSafely(player)
                    synchronized(videoLock) {
                        if (mediaPlayer === player) mediaPlayer = null
                        videoStarting = false
                    }
                    isVideoWallpaper = false
                    handler.post {
                        drawing = true
                        handler.post(drawRunnable)
                    }
                    true
                }

                // Silence other events so GC never finds unhandled ones
                player.setOnCompletionListener { /* loop handles it */ }
                player.setOnInfoListener { _, _, _ -> true }
                player.setOnBufferingUpdateListener { _, _ -> }
                player.setOnSeekCompleteListener { /* no-op */ }
                player.setOnVideoSizeChangedListener { _, _, _ -> }

                player.prepareAsync()
                Log.d(TAG, "MediaPlayer preparing...")
            } catch (e: Exception) {
                Log.e(TAG, "MediaPlayer FAILED: ${e.javaClass.simpleName}: ${e.message}")
                e.printStackTrace()
                // Critical: release the local instance so it doesn't leak (was causing
                // "finalized without being released" and stuck Surface for next attempts)
                if (mp != null) releaseMediaPlayerSafely(mp)
                synchronized(videoLock) { videoStarting = false }
                isVideoWallpaper = false
            }
        }

        /**
         * Releases a MediaPlayer cleanly: clears all listeners (avoids "went away with
         * unhandled events"), detaches surface, stops, and releases native resources.
         */
        private fun releaseMediaPlayerSafely(mp: MediaPlayer) {
            try { mp.setOnPreparedListener(null) } catch (_: Exception) {}
            try { mp.setOnErrorListener(null) } catch (_: Exception) {}
            try { mp.setOnCompletionListener(null) } catch (_: Exception) {}
            try { mp.setOnInfoListener(null) } catch (_: Exception) {}
            try { mp.setOnBufferingUpdateListener(null) } catch (_: Exception) {}
            try { mp.setOnSeekCompleteListener(null) } catch (_: Exception) {}
            try { mp.setOnVideoSizeChangedListener(null) } catch (_: Exception) {}
            try { mp.setSurface(null) } catch (_: Exception) {}
            try { mp.stop() } catch (_: Exception) {}
            try { mp.reset() } catch (_: Exception) {}
            try { mp.release() } catch (_: Exception) {}
        }

        private fun stopVideoWallpaper() {
            handler.removeCallbacks(frameScrubUpdateRunnable)
            frameScrubRenderer.release()
            isFrameMode = false
            cachedDuration = 0L
            videoRetryCount = 0
            val mp: MediaPlayer?
            synchronized(videoLock) {
                mp = mediaPlayer
                mediaPlayer = null
                isVideoWallpaper = false
                videoStarting = false
            }
            if (mp != null) {
                releaseMediaPlayerSafely(mp)
                Log.d(TAG, "MediaPlayer released")
            }
        }

        private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
            val (height, width) = options.outHeight to options.outWidth
            var inSampleSize = 1
            if (height > reqHeight || width > reqWidth) {
                val halfH = height / 2
                val halfW = width / 2
                while ((halfH / inSampleSize) >= reqHeight && (halfW / inSampleSize) >= reqWidth) {
                    inSampleSize *= 2
                }
            }
            return inSampleSize
        }

        private fun createScaledBitmap() {
            val bmp = wallpaperBitmap ?: return
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return

            // Increment version — any Thread with an older version will discard its result
            val myVersion = ++scaleVersion

            // DON'T nullify scaledBitmap/panoramicBitmap here!
            // The old bitmap continues to be drawn until the new one is ready.
            // This prevents the black flash between nullification and Thread completion.

            // Capture dimensions at call time (they could change during thread execution)
            val targetW = surfaceWidth
            val targetH = surfaceHeight

            Thread {
                try {
                    val srcRatio = bmp.width.toFloat() / bmp.height.toFloat()
                    val dstRatio = targetW.toFloat() / targetH.toFloat()

                    val panoramic = srcRatio > dstRatio * 1.5f

                    if (panoramic) {
                        val scaledHeight = targetH
                        val scaledWidth = (bmp.width.toFloat() / bmp.height.toFloat() * scaledHeight).toInt()
                        val newPanBmp = Bitmap.createScaledBitmap(bmp, scaledWidth, scaledHeight, true)

                        // Only apply if this is still the latest scaling request
                        if (myVersion == scaleVersion) {
                            synchronized(bitmapLock) {
                                val oldScaled = scaledBitmap
                                val oldPan = panoramicBitmap
                                if (wallpaperBitmap === bmp) wallpaperBitmap = null
                                scaledBitmap = null
                                panoramicBitmap = newPanBmp
                                isPanoramic = true
                                oldScaled?.recycle()
                                oldPan?.recycle()
                            }
                            bmp.recycle()
                            Log.d(TAG, "Panoramic: ${scaledWidth}x${scaledHeight} (scroll range: ${scaledWidth - targetW}px)")
                        } else {
                            Log.d(TAG, "Stale panoramic scaling (v$myVersion vs current v$scaleVersion), discarding")
                            newPanBmp.recycle()
                            bmp.recycle()
                        }
                    } else {
                        val (cropW, cropH) = if (srcRatio > dstRatio) {
                            Pair((bmp.height * dstRatio).toInt(), bmp.height)
                        } else {
                            Pair(bmp.width, (bmp.width / dstRatio).toInt())
                        }

                        val x = (bmp.width - cropW) / 2
                        val y = (bmp.height - cropH) / 2

                        val cropped = Bitmap.createBitmap(bmp, x, y, cropW, cropH)
                        val scaled = Bitmap.createScaledBitmap(cropped, targetW, targetH, true)
                        // Only recycle cropped if it's a different object from both bmp and scaled
                        if (cropped !== scaled && cropped !== bmp) cropped.recycle()

                        if (myVersion == scaleVersion) {
                            synchronized(bitmapLock) {
                                val oldScaled = scaledBitmap
                                val oldPan = panoramicBitmap
                                if (wallpaperBitmap === bmp) wallpaperBitmap = null
                                panoramicBitmap = null
                                scaledBitmap = scaled
                                isPanoramic = false
                                // Only recycle old bitmaps if they're different objects
                                if (oldScaled !== scaled) oldScaled?.recycle()
                                if (oldPan !== scaled) oldPan?.recycle()
                            }
                            // Don't recycle bmp if Android reused it as the scaled result
                            // (createScaledBitmap returns the same object when dims match)
                            if (bmp !== scaled && bmp !== cropped) bmp.recycle()
                            Log.d(TAG, "Scaled: ${targetW}x${targetH} (v$myVersion) bmp===scaled:${bmp===scaled}")
                        } else {
                            Log.d(TAG, "Stale scaling (v$myVersion vs current v$scaleVersion), discarding")
                            if (scaled !== bmp && scaled !== cropped) scaled.recycle()
                            if (cropped !== bmp) cropped.recycle()
                            bmp.recycle()
                        }
                    }
                    // Force a redraw with the new bitmap (verify surface still valid)
                    handler.post {
                        if (drawing && surfaceHolder?.surface?.isValid == true) drawFrame()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "createScaledBitmap error: ${e.message}")
                }
            }.start()
        }

        private fun updateRendererState() {
            // Sync shared state to all renderers
            clockRenderer.surfaceWidth = surfaceWidth
            clockRenderer.surfaceHeight = surfaceHeight
            clockRenderer.glowColor = glowColor
            clockRenderer.animationPhase = animationPhase

            equalizerRenderer.surfaceWidth = surfaceWidth
            equalizerRenderer.surfaceHeight = surfaceHeight
            equalizerRenderer.glowColor = glowColor
            equalizerRenderer.animationPhase = animationPhase

            rainRenderer.surfaceWidth = surfaceWidth
            rainRenderer.surfaceHeight = surfaceHeight
            rainRenderer.glowColor = glowColor
            rainRenderer.animationPhase = animationPhase
            rainRenderer.isRainWallpaper = isRainWallpaper
            rainRenderer.hasAudio = equalizerRenderer.hasAudio
            rainRenderer.smoothLevels = equalizerRenderer.smoothLevels

            batteryIndicator.surfaceWidth = surfaceWidth
            batteryIndicator.surfaceHeight = surfaceHeight
            batteryIndicator.glowColor = glowColor

            systemRings.surfaceWidth = surfaceWidth
            systemRings.surfaceHeight = surfaceHeight
            systemRings.glowColor = glowColor

            captionOverlay.surfaceWidth = surfaceWidth
            captionOverlay.surfaceHeight = surfaceHeight
            captionOverlay.glowColor = glowColor
        }

        override fun onOffsetsChanged(xOffset: Float, yOffset: Float, xStep: Float, yStep: Float, xPixelOffset: Int, yPixelOffset: Int) {
            if (isPanoramic && xStep > 0f && xStep < 1f) {
                val panBmp = panoramicBitmap
                if (panBmp != null) {
                    val maxScroll = (panBmp.width - surfaceWidth).toFloat().coerceAtLeast(0f)
                    targetScrollPx = xOffset * maxScroll
                    scrollVelocity = 0f
                    if (!drawing) drawFrame()
                }
            }
        }

        override fun onSurfaceChanged(holder: SurfaceHolder?, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            val dimensionsChanged = surfaceWidth != width || surfaceHeight != height
            surfaceWidth = width
            surfaceHeight = height

            // Re-attach surface to existing MediaPlayer
            synchronized(videoLock) {
                val player = mediaPlayer
                if (player != null && holder?.surface != null && holder.surface.isValid) {
                    player.setSurface(holder.surface)
                    Log.d(TAG, "MediaPlayer surface re-attached")
                    return
                }
            }

            if (dimensionsChanged) {
                Log.d(TAG, "Surface changed: ${width}x${height}")
                loadWallpaperImage()
            }
            if (!isVideoWallpaper) {
                createScaledBitmap()
                drawFrame()
            }
        }

        override fun onVisibilityChanged(visible: Boolean) {
            Log.d(TAG, "visibility=$visible isVideo=$isVideoWallpaper isFrame=$isFrameMode videoStarting=$videoStarting")
            if (visible) {
                batteryIndicator.registerBatteryReceiver()
                if (videoStarting) return

                // Frame mode (Explore): already rendering via Canvas, just resume drawing
                if (isFrameMode) {
                    if (!drawing) {
                        drawing = true
                        handler.post(drawRunnable)
                    }
                    return
                }

                // Video: resume MediaPlayer if still alive and playing
                val player = mediaPlayer
                if (player != null) {
                    try {
                        if (!isInteractive && !player.isPlaying) player.start()
                        Log.d(TAG, "MediaPlayer resumed")
                    } catch (e: Exception) {
                        Log.w(TAG, "MediaPlayer resume failed: ${e.message}")
                        // Player is in bad state, clean up
                        stopVideoWallpaper()
                    }
                    return
                }

                // Reload wallpaper config — may need to restart video
                loadWallpaperImage()
                if (!isVideoWallpaper && !videoStarting) {
                    createScaledBitmap()
                    equalizerRenderer.setupVisualizer()
                    drawing = true
                    handler.post(drawRunnable)
                }
            } else {
                // Paint one final frame with overlays hidden BEFORE we stop drawing.
                // Otherwise Android caches the last drawn frame (with clock + rings)
                // and flashes it briefly on the lock screen when the device wakes.
                // This only matters for Canvas-based modes; video wallpapers don't
                // render Canvas overlays anyway.
                if (drawing && !isVideoWallpaper) {
                    forceHideOverlays = true
                    drawFrame()
                    forceHideOverlays = false
                }

                // Only pause video, don't stop/release — it will be resumed on visibility=true
                val player = mediaPlayer
                if (player != null) {
                    player.pause()
                    Log.d(TAG, "MediaPlayer paused")
                } else if (!videoStarting) {
                    drawing = false
                    handler.removeCallbacks(drawRunnable)
                    equalizerRenderer.releaseVisualizer()
                }
            }
        }

        override fun onTouchEvent(event: MotionEvent?) {
            event ?: return

            // Aquarium: fish flee from touch
            if (isAquariumMode && event.action == MotionEvent.ACTION_DOWN) {
                aquariumRenderer.onTouch(event.x, event.y)
            }

            // Interactive mode: tap position on screen = position in video/frames
            if (isInteractive && isVideoWallpaper) {
                if (event.action == MotionEvent.ACTION_DOWN) {
                    val pct = (event.x / surfaceWidth.toFloat()).coerceIn(0f, 1f)

                    if (isFrameMode && frameScrubRenderer.isReady) {
                        // Frame mode: seek through extracted frames
                        frameScrubRenderer.seekTo(pct)
                        // Restart animation loop to process the seek
                        handler.removeCallbacks(frameScrubUpdateRunnable)
                        handler.post(frameScrubUpdateRunnable)
                    } else {
                        // ExoPlayer fallback: animated seek
                        val player = mediaPlayer
                        if (player != null && player.duration > 0) {
                            player.seekTo((pct * player.duration).toInt().coerceIn(0, player.duration - 1))
                        }
                    }
                }
                return
            }

            // Panoramic touch scroll
            if (isPanoramic) {
                val panBmp = panoramicBitmap
                if (panBmp != null) {
                    val maxScroll = (panBmp.width - surfaceWidth).toFloat().coerceAtLeast(0f)
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            touchStartX = event.rawX
                            scrollVelocity = 0f
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val deltaX = touchStartX - event.rawX
                            touchStartX = event.rawX
                            scrollVelocity = deltaX * 2f
                            targetScrollPx = (targetScrollPx + deltaX * 2f).coerceIn(0f, maxScroll)
                        }
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                            // Keep velocity for inertia fling
                        }
                    }
                }
            }

            when (event.action) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                    glowDots.add(GlowDot(event.x, event.y, System.currentTimeMillis(), glowColor))
                    if (!drawing) {
                        drawing = true
                        handler.post(drawRunnable)
                    }
                }
            }
        }

        private fun drawFrame() {
            if (!drawing) return
            val holder = surfaceHolder ?: return
            var canvas: Canvas? = null
            try {
                canvas = holder.lockCanvas() ?: return
                updateRendererState()

                // Frame mode: draw extracted frame instead of wallpaper bitmap
                if (isFrameMode && frameScrubRenderer.isReady) {
                    frameScrubRenderer.draw(canvas)
                } else {
                    drawBackground(canvas)
                }

                // Firefly: luna moths + glowing dots over enchanted forest
                if (isFireflyMode) {
                    aquariumRenderer.surfaceWidth = surfaceWidth
                    aquariumRenderer.surfaceHeight = surfaceHeight
                    aquariumRenderer.draw(canvas)
                    fireflyRenderer.surfaceWidth = surfaceWidth
                    fireflyRenderer.surfaceHeight = surfaceHeight
                    fireflyRenderer.update()
                    fireflyRenderer.draw(canvas)
                }

                // Aquarium: draw animated fish over the background, plus rising bubbles
                if (isAquariumMode) {
                    aquariumRenderer.surfaceWidth = surfaceWidth
                    aquariumRenderer.surfaceHeight = surfaceHeight
                    aquariumRenderer.draw(canvas)
                    bubbleRenderer.surfaceWidth = surfaceWidth
                    bubbleRenderer.surfaceHeight = surfaceHeight
                    bubbleRenderer.update()
                    bubbleRenderer.draw(canvas)
                }

                // Jellyfish: jellies rising + bubbles + occasional squid
                if (isJellyfishMode) {
                    jellyfishRenderer.surfaceWidth = surfaceWidth
                    jellyfishRenderer.surfaceHeight = surfaceHeight
                    jellyfishRenderer.draw(canvas)
                    // Horizontal jetting squid (skipped if no sprites loaded)
                    aquariumRenderer.surfaceWidth = surfaceWidth
                    aquariumRenderer.surfaceHeight = surfaceHeight
                    aquariumRenderer.draw(canvas)
                    // Rising bubbles on top
                    bubbleRenderer.surfaceWidth = surfaceWidth
                    bubbleRenderer.surfaceHeight = surfaceHeight
                    bubbleRenderer.update()
                    bubbleRenderer.draw(canvas)
                }

                rainRenderer.draw(canvas)
                if (isRainWallpaper) rainRenderer.drawHeadphoneGlow(canvas)

                // Hide our decorative overlays on the lock screen (KeyguardManager is
                // authoritative) AND respect user toggles from Settings. forceHideOverlays
                // is only set for the "last frame before sleep" so the cached lockscreen
                // frame is clean.
                val isLocked = forceHideOverlays ||
                    keyguardManager?.isKeyguardLocked == true
                if (!isLocked && showClock) {
                    clockRenderer.draw(canvas)
                }
                if (showBattery) {
                    batteryIndicator.draw(canvas)
                }
                if (!isLocked) {
                    // SystemRings internally respects its own showRam/showStorage flags.
                    systemRings.draw(canvas)
                }
                if (showEqualizer) {
                    equalizerRenderer.draw(canvas)
                }
                if (!isLocked) captionOverlay.draw(canvas)
                drawGlowEffects(canvas)
            } catch (e: Exception) {
                Log.e(TAG, "drawFrame error: ${e.message}")
            } finally {
                if (canvas != null) {
                    try { holder.unlockCanvasAndPost(canvas) } catch (_: Exception) {}
                }
            }

            animationPhase += 0.05f

            val now = System.currentTimeMillis()
            glowDots.removeAll { now - it.startTime > GLOW_DURATION }

            // Switch to idle mode (low fps) when no audio and no touch
            val scrolling = isPanoramic && abs(scrollVelocity) > 0.5f
            if (!equalizerRenderer.hasAudio && glowDots.isEmpty() && !isRainWallpaper && !scrolling && !hasAnimatedCanvasOverlay) {
                equalizerRenderer.silentFrames++
                if (equalizerRenderer.silentFrames > 30 && !idleMode) {
                    idleMode = true
                    equalizerRenderer.releaseVisualizer()
                }
            } else {
                equalizerRenderer.silentFrames = 0
                if (idleMode) {
                    idleMode = false
                    equalizerRenderer.setupVisualizer()
                }
            }
        }

        private fun drawBackground(canvas: Canvas) {
            // Read bitmap references under lock to prevent use-after-recycle
            val panBmp: Bitmap?
            val stdBmp: Bitmap?
            val pan: Boolean
            synchronized(bitmapLock) {
                panBmp = panoramicBitmap
                stdBmp = scaledBitmap
                pan = isPanoramic
            }

            if (pan && panBmp != null && !panBmp.isRecycled) {
                val maxScroll = (panBmp.width - surfaceWidth).toFloat().coerceAtLeast(0f)

                if (abs(scrollVelocity) > 0.5f) {
                    targetScrollPx = (targetScrollPx + scrollVelocity).coerceIn(0f, maxScroll)
                    scrollVelocity *= 0.92f
                }
                scrollOffsetPx += (targetScrollPx - scrollOffsetPx) * 0.15f

                canvas.drawBitmap(panBmp, -scrollOffsetPx, 0f, null)
                return
            }
            if (stdBmp != null && !stdBmp.isRecycled) {
                canvas.drawBitmap(stdBmp, 0f, 0f, null)
            } else {
                canvas.drawColor(Color.BLACK)
            }
        }

        private fun drawGlowEffects(canvas: Canvas) {
            val now = System.currentTimeMillis()
            for (dot in glowDots) {
                val elapsed = now - dot.startTime
                val progress = (elapsed.toFloat() / GLOW_DURATION).coerceIn(0f, 1f)
                val radius = MAX_RADIUS * progress
                val alpha = ((1f - progress) * 0.45f * 255).toInt().coerceIn(0, 255)
                if (alpha <= 0 || radius <= 0f) continue

                val dr = Color.red(dot.color)
                val dg = Color.green(dot.color)
                val db = Color.blue(dot.color)

                glowDotPaint.shader = RadialGradient(
                    dot.x, dot.y, radius,
                    intArrayOf(
                        Color.argb(alpha, dr, dg, db),
                        Color.argb((alpha * 0.3f).toInt(), dr, dg, db),
                        Color.argb(0, dr, dg, db)
                    ),
                    floatArrayOf(0f, 0.5f, 1f),
                    Shader.TileMode.CLAMP
                )
                canvas.drawCircle(dot.x, dot.y, radius, glowDotPaint)
            }
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder?) {
            drawing = false
            handler.removeCallbacks(drawRunnable)
            pendingReload?.let { handler.removeCallbacks(it) }
            equalizerRenderer.releaseVisualizer()
            batteryIndicator.unregisterBatteryReceiver()
            // Don't release ExoPlayer here — surface may be recreated (visibility change).
            // Only detach the surface so it doesn't draw to a destroyed one.
            synchronized(videoLock) {
                mediaPlayer?.setSurface(null)
            }
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            drawing = false
            handler.removeCallbacks(drawRunnable)
            pendingReload?.let { handler.removeCallbacks(it) }
            equalizerRenderer.releaseVisualizer()
            stopVideoWallpaper()
            aquariumRenderer.recycle()
            bubbleRenderer.reset()
            fireflyRenderer.reset()
            jellyfishRenderer.recycle()
            batteryIndicator.release()
            unregisterPrefsListener()
            unregisterKeyguardReceiver()
            unregisterOverlaySettingsReceiver()
            unregisterWallpaperPathReceiver()
            synchronized(bitmapLock) {
                wallpaperBitmap?.recycle()
                scaledBitmap?.recycle()
                panoramicBitmap?.recycle()
                wallpaperBitmap = null
                scaledBitmap = null
                panoramicBitmap = null
            }
            super.onDestroy()
        }
    }

    data class GlowDot(val x: Float, val y: Float, val startTime: Long, val color: Int)

    companion object {
        private const val TAG = "PixoraEQ"
        const val GLOW_DURATION = 700L
        const val MAX_RADIUS = 120f
        const val BAR_COUNT = 6
        const val FRAME_DELAY = 33L // ~30fps
        const val IDLE_FRAME_DELAY = 1000L
        const val SILENCE_THRESHOLD = 0.05f
        const val RAIN_DROP_COUNT = 120
        const val GLASS_DROP_COUNT = 15
        const val CITY_LIGHT_COUNT = 35
    }
}
