package com.orbix.pixora

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.graphics.*
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
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
        // Touch trail renderer — user-selectable, swapped when pref changes.
        private var touchTrail: com.orbix.pixora.touch.TouchTrailRenderer =
            com.orbix.pixora.touch.TouchTrailRegistry.create(
                com.orbix.pixora.touch.TouchTrailRegistry.DEFAULT_ID)
        @Volatile private var drawing = false
        private var surfaceWidth = 0
        private var surfaceHeight = 0
        private var glowColor = Color.parseColor("#C9A650")

        // Bitmap scaling version counter — prevents stale Thread results
        @Volatile private var scaleVersion = 0

        // Decode idempotency guard — skip redundant BitmapFactory.decodeFile when
        // path + surface dims haven't changed since last successful decode. Each
        // engine activation fires loadWallpaperImage() up to 3 times (onSurfaceChanged
        // + onVisibilityChanged + debounced prefs reload), all with identical inputs.
        @Volatile private var lastDecodedPath: String? = null
        @Volatile private var lastDecodedSurfaceW: Int = 0
        @Volatile private var lastDecodedSurfaceH: Int = 0

        // Scaling idempotency guard — same idea for createScaledBitmap(). The
        // versioning counter above protects against applying stale results, but
        // the underlying Bitmap.createScaledBitmap() work (up to ~44 MB alloc
        // for a 9433x2340 panoramic) still runs N times per activation. This
        // guard short-circuits BEFORE the Thread spawns when nothing changed.
        @Volatile private var lastScaledForPath: String? = null
        @Volatile private var lastScaledSurfaceW: Int = 0
        @Volatile private var lastScaledSurfaceH: Int = 0

        // ── Pixora Daily — in-service rotation (robust architecture) ──────────
        // The service rotates the wallpaper ITSELF on wake, instead of relying
        // on a background Worker that Android throttles + a process-kill that
        // Samsung punishes. We detect "daily mode" purely from our own state:
        // if the current wallpaper_path lives in auto_rotate_cache/, we're in
        // daily mode and rotate between the cached files when the interval has
        // elapsed. No cross-process flag, no WorkManager dependency, no kill.
        @Volatile private var dailyIntervalMs = 30 * 60 * 1000L // default 30 min
        @Volatile private var dailyLastRotation = 0L

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

        // Renderers
        // Device tier — resolved once in onCreate. Used by drawRunnable for
        // adaptive frame pacing. See DeviceTier.kt for tier semantics.
        private var deviceTier: com.orbix.pixora.renderers.DeviceTier = com.orbix.pixora.renderers.DeviceTier.MID

        private val clockRenderer = ClockRenderer()
        private val equalizerRenderer = EqualizerRenderer(applicationContext)
        private val rainRenderer = RainEffectRenderer()
        private val batteryIndicator = BatteryIndicator(applicationContext)
        private val systemRings = SystemRingsRenderer(applicationContext)
        private val hudRenderer = HudRenderer(applicationContext)
        private val sacredOrnaments = com.orbix.pixora.renderers.SacredOrnaments()
        private var currentPreset: com.orbix.pixora.renderers.HudPreset =
            com.orbix.pixora.renderers.HudPreset.CLASICO
        private val captionOverlay = CaptionOverlay()
        private val aquariumRenderer = AquariumRenderer(applicationContext)
        private val bubbleRenderer = BubbleRenderer()
        private val fireflyRenderer = FireflyRenderer()
        private val jellyfishRenderer = JellyfishRenderer(applicationContext)
        private val pixoraFriendsRenderer = PixoraFriendsRenderer(applicationContext)
        private val canvasSceneRenderer =
            com.orbix.pixora.scene.CanvasSceneRenderer(applicationContext)
        // Universal Pixora "P" 3D logo. Renders LAST on every wallpaper
        // type so the brand mark is consistent across the entire app.
        private val brandingLogo =
            com.orbix.pixora.scene.BrandingLogo(applicationContext)
        private var brandingTick = 0L
        private var isAquariumMode = false
        private var isFireflyMode = false
        private var isJellyfishMode = false
        private var isPixoraIslandMode = false
        // Data-driven scene mode (volcano_dragon, dusk_fortress, and any future
        // canvas_scene wallpaper). Activated by the 'scene_id' SharedPreference.
        private var isCanvasSceneMode = false

        // ── Gyroscope (parallax) ───────────────────────────────────────────
        // Reads device rotation and feeds smoothed (tilt_x, tilt_y) pixel offsets
        // to the canvas scene renderer. Only registered when a parallax-enabled
        // canvas_scene is active (saves battery for static wallpapers).
        private var sensorManager: SensorManager? = null
        private var gyroSensor: Sensor? = null
        private var sensorMode = 0  // 1=ROTATION_VECTOR, 2=GAME_ROTATION, 3=ACCELEROMETER
        private var gyroRegistered = false
        @Volatile private var tiltXNorm = 0f
        @Volatile private var tiltYNorm = 0f
        private val tiltAmpX get() = (surfaceWidth * 0.07f).coerceAtLeast(40f)
        private val tiltAmpY get() = (surfaceHeight * 0.07f).coerceAtLeast(60f)

        private val gyroListener = object : SensorEventListener {
            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
            override fun onSensorChanged(e: SensorEvent) {
                val rawX: Float
                val rawY: Float
                when (sensorMode) {
                    1, 2 -> {
                        // ROTATION_VECTOR / GAME_ROTATION_VECTOR: values[0..3] is a
                        // quaternion. We approximate roll/pitch from x/y components.
                        rawX = (-e.values[1] * 2f).coerceIn(-1f, 1f)
                        rawY = (-e.values[0] * 2f).coerceIn(-1f, 1f)
                    }
                    3 -> {
                        // Accelerometer fallback: x/y are gravity components in m/s².
                        // ±9.8 = phone fully tilted. Normalize to [-1, +1].
                        rawX = (e.values[0] / 9.81f).coerceIn(-1f, 1f)
                        rawY = (-e.values[1] / 9.81f).coerceIn(-1f, 1f)
                    }
                    else -> return
                }
                val alpha = 0.12f
                tiltXNorm += (rawX - tiltXNorm) * alpha
                tiltYNorm += (rawY - tiltYNorm) * alpha
                canvasSceneRenderer.tiltX = tiltXNorm * tiltAmpX
                canvasSceneRenderer.tiltY = tiltYNorm * tiltAmpY
            }
        }

        private fun registerGyroIfNeeded() {
            if (gyroRegistered) return
            if (sensorManager == null) {
                sensorManager = applicationContext.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            }
            val sm = sensorManager
            if (sm == null) {
                Log.w(TAG, "SensorManager unavailable — parallax disabled")
                return
            }
            // Try in priority order: GAME_ROTATION_VECTOR (best) → ROTATION_VECTOR
            // → ACCELEROMETER (universal fallback that every phone has).
            var s = sm.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
            sensorMode = 2
            if (s == null) {
                s = sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                sensorMode = 1
            }
            if (s == null) {
                s = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                sensorMode = 3
            }
            if (s == null) {
                Log.w(TAG, "No usable sensor found (rotation/accel) — parallax disabled")
                sensorMode = 0
                return
            }
            gyroSensor = s
            sm.registerListener(gyroListener, s, SensorManager.SENSOR_DELAY_GAME)
            gyroRegistered = true
            val modeName = when (sensorMode) { 1->"ROTATION_VECTOR"; 2->"GAME_ROTATION_VECTOR"; 3->"ACCELEROMETER"; else->"?" }
            Log.d(TAG, "Sensor registered: ${s.name} (mode=$modeName)")
        }

        private fun unregisterGyro() {
            if (!gyroRegistered) return
            sensorManager?.unregisterListener(gyroListener)
            gyroRegistered = false
            sensorMode = 0
            tiltXNorm = 0f; tiltYNorm = 0f
            canvasSceneRenderer.tiltX = 0f; canvasSceneRenderer.tiltY = 0f
        }

        // Any wallpaper that uses code-driven animated sprites over a static background.
        // Keeps the engine at full FPS so animations and the clock second-hand stay smooth.
        private val hasAnimatedCanvasOverlay: Boolean
            get() = isAquariumMode || isFireflyMode || isJellyfishMode || isPixoraIslandMode ||
                isCanvasSceneMode

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
                val clearScene = intent.getBooleanExtra("clear_scene", false)
                val prefs = applicationContext.getSharedPreferences("pixora_live", 0)
                val editor = prefs.edit().putString("wallpaper_path", newPath)
                if (newGlow != null) editor.putString("glow_color", newGlow)
                editor.putString("caption", newCaption)
                if (clearScene) {
                    // AutoRotate sends this on every tick: drop the canvas scene
                    // (e.g. goku_genkidama) and any interactive flag so the rotated
                    // image renders clean instead of being overlaid by stale state.
                    editor.remove("scene_id")
                    editor.putBoolean("interactive", false)
                }
                editor.putLong("changed_at", System.currentTimeMillis())
                editor.apply()
            }
        }

        /**
         * Receives `com.orbix.pixora.AD_VISIBLE` broadcasts from the main
         * process before/after AdMob ads. When `visible=true`, we drop the
         * wallpaper into idle mode (1 fps) so canvas scenes stop competing
         * for GPU/CPU with the ad's WebGL/video content. When `visible=false`,
         * we restore normal rendering. Discovered 2026-05-08 night that the
         * `:wallpaper` process renders BEHIND the translucent AdActivity
         * and triggers ANR when both fight for resources.
         */
        private val adVisibilityReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val visible = intent?.getBooleanExtra("visible", false) ?: return
                idleMode = visible
                Log.d(TAG, "adVisibilityReceiver: ad ${if (visible) "visible → idle" else "dismissed → normal"}")
            }
        }

        private fun loadOverlaySettings() {
            val prefs = applicationContext.getSharedPreferences("pixora_live", 0)
            showClock = prefs.getBoolean("show_clock", true)
            showBattery = prefs.getBoolean("show_battery", true)
            showEqualizer = prefs.getBoolean("show_equalizer", true)
            systemRings.showRam = prefs.getBoolean("show_ram", true)
            systemRings.showStorage = prefs.getBoolean("show_storage", true)
            hudRenderer.showRam = systemRings.showRam
            hudRenderer.showStorage = systemRings.showStorage
            // HUD preset — 1 of 10 selectable themes. Defaults to SACRED
            // (the original Pixora gold rings + serif clock) so existing
            // users see no change until they actively pick from Settings.
            val presetKey = prefs.getString("hud_preset", "sacred") ?: "sacred"
            currentPreset = com.orbix.pixora.renderers.HudPreset.fromKey(presetKey)
            clockRenderer.currentPreset = currentPreset
            equalizerRenderer.currentPreset = currentPreset
            hudRenderer.hudStyle = currentPreset.hudStyle
            hudRenderer.accentColor = currentPreset.hudAccent
            // Touch trail style picker — reload on broadcast too, not just on
            // wallpaper switch, so the change is instant from Settings.
            val trailStyle = prefs.getString(
                com.orbix.pixora.touch.TouchTrailRegistry.PREF_KEY,
                com.orbix.pixora.touch.TouchTrailRegistry.DEFAULT_ID,
            ) ?: com.orbix.pixora.touch.TouchTrailRegistry.DEFAULT_ID
            if (touchTrail.id != trailStyle) {
                touchTrail.reset()
                touchTrail = com.orbix.pixora.touch.TouchTrailRegistry.create(trailStyle)
                Log.d(TAG, "Touch trail switched to: $trailStyle")
            }
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
                    // Tier-aware adaptive pacing (2026-06-06):
                    //  · isFrameMode / idleMode → 1fps (clock-only)
                    //  · audio playing → tier.activeFrameDelay (33ms HIGH/MID, 50ms LOW)
                    //  · no audio (idle marquee) → tier.idleMarqueeFrameDelay
                    //    (33ms HIGH, 60ms MID = ~16fps, 100ms LOW = 10fps).
                    //    The marquee wave is slow so 16fps looks fine and
                    //    halves battery cost during the most common case
                    //    (no music). Visualizer stays alive — we don't pay
                    //    re-acquire latency when music starts.
                    val delay = when {
                        isFrameMode -> IDLE_FRAME_DELAY
                        idleMode -> IDLE_FRAME_DELAY
                        equalizerRenderer.hasAudio -> deviceTier.activeFrameDelay
                        else -> deviceTier.idleMarqueeFrameDelay
                    }
                    handler.postDelayed(this, delay)
                }
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder?) {
            super.onCreate(surfaceHolder)
            setTouchEventsEnabled(true)
            // One-shot opt-in for launcher offset notifications. Default is
            // true on most launchers but Samsung One UI sometimes withholds
            // them from non-image WallpaperServices unless we ask. Called
            // exactly once per engine instance (no loop risk).
            try { setOffsetNotificationsEnabled(true) } catch (_: Exception) {}
            // Resolve device performance tier ONCE and propagate to every
            // renderer. Drives shadow radius, per-bar setShadowLayer opt-out,
            // ring halo opt-out, and the frame-pacing in drawRunnable below.
            // 2026-06-06 overhaul: brought Eduardo's mid-range Samsung from
            // ~15fps to 28-30fps consistently. See DeviceTier.kt.
            deviceTier = com.orbix.pixora.renderers.DeviceTier.get(applicationContext)
            clockRenderer.tier = deviceTier
            equalizerRenderer.tier = deviceTier
            systemRings.tier = deviceTier
            equalizerRenderer.audioCallback = this
            loadOverlaySettings()
            loadWallpaperImage()
            batteryIndicator.registerBatteryReceiver()
            registerPrefsListener()
            registerKeyguardReceiver()
            registerOverlaySettingsReceiver()
            registerWallpaperPathReceiver()
            registerAdVisibilityReceiver()
            loadDailyConfig()
            Log.d(TAG, "Engine onCreate")
        }

        /**
         * Read Pixora Daily rotation config. Interval comes from the
         * pixora_auto_rotate prefs (set when the user activates daily, read
         * once here on a fresh process so the cross-process cache pitfall
         * doesn't apply). lastRotation lives in our OWN pixora_live prefs.
         */
        private fun loadDailyConfig() {
            try {
                val arPrefs = applicationContext
                    .getSharedPreferences("pixora_auto_rotate", Context.MODE_PRIVATE)
                // interval_minutes == 0 means "rotate on every unlock". We
                // still apply a 20s floor so quick lock/unlock cycles don't
                // trigger several rotations in a row.
                val mins = arPrefs.getInt("interval_minutes", 30)
                dailyIntervalMs = if (mins <= 0) 20_000L else mins * 60_000L
                val livePrefs = applicationContext
                    .getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                dailyLastRotation = livePrefs.getLong("daily_last_rotation", 0L)
                // First time in daily mode (no timestamp yet): seed it to now so
                // we don't rotate immediately on the first wake.
                if (dailyLastRotation == 0L) {
                    dailyLastRotation = System.currentTimeMillis()
                    livePrefs.edit().putLong("daily_last_rotation", dailyLastRotation).apply()
                }
                Log.d(TAG, "Daily config: interval=${dailyIntervalMs / 60000}min lastRotation=$dailyLastRotation")
            } catch (e: Exception) {
                Log.w(TAG, "loadDailyConfig failed: ${e.message}")
            }
        }

        /**
         * Pixora Daily rotation — called on wake (onVisibilityChanged true).
         * If we're in daily mode (current path lives in auto_rotate_cache/) AND
         * the interval has elapsed, pick a new cached wallpaper and swap to it.
         * The normal loadWallpaperImage() right after picks up the new path.
         *
         * Robust by design: no WorkManager, no process kill, no component touch.
         * Rotates only when the user actually wakes the phone (battery friendly).
         * Degrades gracefully: if no cache or <2 files, does nothing.
         */
        private fun maybeRotateDaily() {
            try {
                val livePrefs = applicationContext
                    .getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                val current = currentWallpaperPath
                    ?: livePrefs.getString("wallpaper_path", null)
                    ?: return
                // Only rotate if we're showing a daily-rotated wallpaper.
                if (!current.contains("auto_rotate_cache")) return

                val now = System.currentTimeMillis()
                if (now - dailyLastRotation < dailyIntervalMs) return

                val cacheDir = File(applicationContext.filesDir, "auto_rotate_cache")
                val files = cacheDir.listFiles()
                    ?.filter { it.extension != "tmp" && it.length() > 0 }
                    ?: return
                if (files.size < 2) return // nothing to rotate to

                val next = files.filter { it.absolutePath != current }.randomOrNull()
                    ?: return

                dailyLastRotation = now
                livePrefs.edit()
                    .putString("wallpaper_path", next.absolutePath)
                    .putLong("daily_last_rotation", now)
                    .remove("scene_id")
                    .putBoolean("interactive", false)
                    .apply()
                currentWallpaperPath = next.absolutePath
                Log.d(TAG, "Daily rotated → ${next.name} (interval ${dailyIntervalMs / 60000}min)")
            } catch (e: Exception) {
                Log.w(TAG, "maybeRotateDaily failed: ${e.message}")
            }
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

        private fun registerAdVisibilityReceiver() {
            val filter = IntentFilter("com.orbix.pixora.AD_VISIBLE")
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    applicationContext.registerReceiver(
                        adVisibilityReceiver, filter, Context.RECEIVER_NOT_EXPORTED
                    )
                } else {
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    applicationContext.registerReceiver(adVisibilityReceiver, filter)
                }
            } catch (e: Exception) {
                Log.w(TAG, "adVisibilityReceiver register failed: ${e.message}")
            }
        }

        private fun unregisterAdVisibilityReceiver() {
            try {
                applicationContext.unregisterReceiver(adVisibilityReceiver)
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
                var path = prefs.getString("wallpaper_path", null)

                // Pixora Daily self-healing: if wallpaper_path points to a file
                // in auto_rotate_cache/ that no longer exists (stale prefs from
                // a previous session, cleanup race with the prefetch worker, or
                // first-activation when Worker wrote a path before cache was
                // populated), redirect to any existing cached file BEFORE
                // proceeding. Without this, the engine renders black forever
                // because every code path below depends on a valid path.
                if (path != null && path.contains("auto_rotate_cache")
                    && !File(path).exists()) {
                    val cacheDir = File(applicationContext.filesDir, "auto_rotate_cache")
                    val fallback = cacheDir.listFiles()
                        ?.filter { it.extension != "tmp" && it.length() > 0 }
                        ?.firstOrNull()
                    if (fallback != null) {
                        Log.w(TAG, "Self-heal: stale wallpaper_path redirected to ${fallback.name}")
                        path = fallback.absolutePath
                        prefs.edit().putString("wallpaper_path", path).apply()
                    } else {
                        Log.w(TAG, "Self-heal: stale path but cache is empty — nothing to do")
                    }
                }
                val color = prefs.getString("glow_color", "#C9A650")
                val caption = prefs.getString("caption", null)
                isInteractive = prefs.getBoolean("interactive", false)

                // User-selected touch trail style — swap if changed
                val trailStyle = prefs.getString(
                    com.orbix.pixora.touch.TouchTrailRegistry.PREF_KEY,
                    com.orbix.pixora.touch.TouchTrailRegistry.DEFAULT_ID,
                ) ?: com.orbix.pixora.touch.TouchTrailRegistry.DEFAULT_ID
                if (touchTrail.id != trailStyle) {
                    touchTrail.reset()
                    touchTrail = com.orbix.pixora.touch.TouchTrailRegistry.create(trailStyle)
                    Log.d(TAG, "Touch trail switched to: $trailStyle")
                }

                // Reset animated overlay state on wallpaper change
                aquariumRenderer.recycle()
                bubbleRenderer.reset()
                fireflyRenderer.reset()
                jellyfishRenderer.recycle()
                pixoraFriendsRenderer.release()
                canvasSceneRenderer.release()

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
                    jellyfishRenderer.loadSprites("aquarium/comb_jelly")
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
                        // Comb jelly (ctenophore): 1 rare iridescent wanderer, very slow + wide sway
                        if (jellyfishRenderer.hasSprites("aquarium/comb_jelly")) {
                            jellyfishRenderer.addJellies(
                                count = 1,
                                spriteFolder = "aquarium/comb_jelly",
                                scaleMin = 0.7f, scaleMax = 0.9f,
                                speedMin = 0.15f, speedMax = 0.3f,
                                swayAmpMin = 35f, swayAmpMax = 55f,
                            )
                        }
                    }

                    // Rising bubble streams — calm abyss respiration
                    bubbleRenderer.surfaceWidth = surfaceWidth
                    bubbleRenderer.surfaceHeight = surfaceHeight

                    // Occasional deep-sea anglerfish (horizontal drifter).
                    // No native lure glow — the GIF already bakes a pulsing
                    // bioluminescent bulb into the animation, and since the
                    // illicium sways per-frame, a static overlay can't track
                    // it correctly. The GIF's built-in glow is enough.
                    aquariumRenderer.surfaceWidth = surfaceWidth
                    aquariumRenderer.surfaceHeight = surfaceHeight
                    aquariumRenderer.loadFishSprites("aquarium/angler_fish")
                    if (aquariumRenderer.fishCount == 0) {
                        aquariumRenderer.addFish(
                            count = 1,
                            spriteFolder = "aquarium/angler_fish",
                            scaleMin = 0.55f, scaleMax = 0.7f,
                            speedMin = 0.4f, speedMax = 0.7f,
                        )
                    }

                    Log.d(TAG, "Jellyfish mode activated: jellies + bubbles + squid over ocean abyss (${surfaceWidth}x${surfaceHeight})")
                }

                // Pixora Island: chibi mascot that cycles idle/walk/eat/sleep by hour
                isPixoraIslandMode = path?.contains("pixora_island") == true
                if (isPixoraIslandMode && surfaceWidth > 0 && surfaceHeight > 0) {
                    pixoraFriendsRenderer.surfaceWidth = surfaceWidth
                    pixoraFriendsRenderer.surfaceHeight = surfaceHeight
                    // Sprite native size 240x~400, decoded at half via inSampleSize=2.
                    // Target ~22% of screen width so the mascot feels present but doesn't
                    // compete with the scene. At 1080 px screen that's ~237 px wide.
                    pixoraFriendsRenderer.scale = (surfaceWidth * 0.22f) / 120f
                    Log.d(TAG, "Pixora Island mode activated: chibi mascot day-cycle (${surfaceWidth}x${surfaceHeight})")
                }

                // Data-driven canvas scenes (volcano_dragon, dusk_fortress, and any
                // future canvas_scene wallpaper). Activated by 'scene_id' pref set
                // from MainActivity.setLiveWallpaper(sceneId=...). The wallpaper
                // path remains the standard background image; the scene spec drives
                // the FX overlay (sprites, particles, events).
                val sceneId = prefs.getString("scene_id", null)
                isCanvasSceneMode = !sceneId.isNullOrBlank()
                if (isCanvasSceneMode && surfaceWidth > 0 && surfaceHeight > 0) {
                    canvasSceneRenderer.surfaceWidth = surfaceWidth
                    canvasSceneRenderer.surfaceHeight = surfaceHeight
                    val ok = canvasSceneRenderer.loadSpec(sceneId!!)
                    if (ok) {
                        canvasSceneRenderer.ensureLoaded()
                        Log.d(TAG, "Canvas scene activated: $sceneId (${surfaceWidth}x${surfaceHeight})")
                        // Register gyroscope only for parallax-enabled scenes
                        if (canvasSceneRenderer.hasParallax) {
                            registerGyroIfNeeded()
                        } else {
                            unregisterGyro()
                        }
                    } else {
                        Log.w(TAG, "Canvas scene failed to load: $sceneId — falling back")
                        isCanvasSceneMode = false
                        unregisterGyro()
                    }
                } else {
                    unregisterGyro()
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

                        // Skip bitmap decode if surface isn't ready yet — onSurfaceChanged
                        // will call us back once it knows the real dimensions. Saves up to
                        // two redundant decodes per engine activation (onCreate fires before
                        // the launcher reports the surface).
                        if (surfaceWidth <= 0 || surfaceHeight <= 0) {
                            Log.d(TAG, "loadWallpaperImage: surface not ready (${surfaceWidth}x${surfaceHeight}), deferring decode")
                            return
                        }

                        // Idempotency guard: if path + surface dims match the last successful
                        // decode AND the bitmap is still alive, skip the decode entirely.
                        // Stops the 2nd/3rd redundant decode from onVisibilityChanged and the
                        // debounced prefs reload.
                        val existing = wallpaperBitmap
                        if (path == lastDecodedPath &&
                            surfaceWidth == lastDecodedSurfaceW &&
                            surfaceHeight == lastDecodedSurfaceH &&
                            existing != null && !existing.isRecycled) {
                            Log.d(TAG, "loadWallpaperImage: bitmap already current ($path @ ${surfaceWidth}x${surfaceHeight}), skipping decode")
                            return
                        }

                        val opts = BitmapFactory.Options()
                        opts.inJustDecodeBounds = true
                        BitmapFactory.decodeFile(path, opts)
                        Log.d(TAG, "decodeFile bounds: ${opts.outWidth}x${opts.outHeight} mimeType=${opts.outMimeType}")

                        if (opts.outWidth <= 0 || opts.outHeight <= 0) {
                            Log.e(TAG, "Invalid bitmap dimensions: ${opts.outWidth}x${opts.outHeight}")
                            return
                        }

                        opts.inSampleSize = calculateInSampleSize(opts, opts.outWidth, surfaceHeight)
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
                            // Recycle previous bitmap if it was replaced without going through
                            // createScaledBitmap's reassignment path (e.g. consecutive reloads
                            // before any scale completes).
                            wallpaperBitmap?.takeIf { it !== decoded && !it.isRecycled }?.recycle()
                            wallpaperBitmap = decoded
                            // Record successful decode so the idempotency guard above can
                            // short-circuit subsequent identical loadWallpaperImage() calls.
                            lastDecodedPath = path
                            lastDecodedSurfaceW = surfaceWidth
                            lastDecodedSurfaceH = surfaceHeight
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

            // Explore mode: load pre-downloaded frames (no codec needed).
            // Only valid when the path is a DIRECTORY of frame images.
            // If interactive=true was set but path is a single MP4 file
            // (catalog inconsistency), fall through to MediaPlayer instead
            // of returning silently (which produced a black screen).
            val pathFile = File(path)
            if (isInteractive && pathFile.isDirectory) {
                if (isFrameMode) {
                    synchronized(videoLock) { videoStarting = false }
                    return
                }
                isFrameMode = true
                synchronized(videoLock) { videoStarting = false }

                Log.d(TAG, "Explore: loading frames from $path")
                if (frameScrubRenderer.loadFromDirectory(path)) {
                    drawing = true
                    handler.post(drawRunnable)
                    handler.post(frameScrubUpdateRunnable)
                } else {
                    isFrameMode = false
                }
                return
            }
            if (isInteractive) {
                Log.w(TAG, "interactive=true but path is not a directory ($path); falling back to MediaPlayer")
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

            // Idempotency guard: if a scaling for this exact path + surface dims
            // has already been committed (either completed OR in-flight), skip
            // the entire Thread spawn + Bitmap.createScaledBitmap allocation.
            // Registration happens synchronously below, BEFORE Thread.spawn —
            // that's what catches the 3-call burst from loadWallpaperImage in
            // onSurfaceChanged + onVisibilityChanged + debounced prefs reload.
            val currentPath = lastDecodedPath
            if (currentPath != null &&
                currentPath == lastScaledForPath &&
                surfaceWidth == lastScaledSurfaceW &&
                surfaceHeight == lastScaledSurfaceH) {
                Log.d(TAG, "createScaledBitmap: already current ($currentPath @ ${surfaceWidth}x${surfaceHeight}), skipping")
                return
            }

            // Increment version — any Thread with an older version will discard its result
            val myVersion = ++scaleVersion

            // Register the in-flight scaling SYNCHRONOUSLY so subsequent burst
            // calls hit the guard above. If this Thread eventually discards as
            // stale or fails, a fresh loadWallpaperImage+createScaledBitmap will
            // be triggered by a new path/dims change and overwrite these fields.
            lastScaledForPath = currentPath
            lastScaledSurfaceW = surfaceWidth
            lastScaledSurfaceH = surfaceHeight

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
                            // (lastScaledFor* already set synchronously before Thread spawn.)
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
                            // (lastScaledFor* already set synchronously before Thread spawn.)
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

            hudRenderer.surfaceWidth = surfaceWidth
            hudRenderer.surfaceHeight = surfaceHeight
            hudRenderer.animationPhase = animationPhase

            sacredOrnaments.surfaceWidth = surfaceWidth
            sacredOrnaments.surfaceHeight = surfaceHeight
            sacredOrnaments.accentColor = currentPreset.hudAccent

            captionOverlay.surfaceWidth = surfaceWidth
            captionOverlay.surfaceHeight = surfaceHeight
            captionOverlay.glowColor = glowColor
        }

        override fun onOffsetsChanged(xOffset: Float, yOffset: Float, xStep: Float, yStep: Float, xPixelOffset: Int, yPixelOffset: Int) {
            Log.d(TAG, "onOffsetsChanged: xOffset=$xOffset xStep=$xStep panoramic=$isPanoramic canvas=$isCanvasSceneMode hasParallax=${canvasSceneRenderer.hasParallax}")
            // Panoramic wallpapers: scroll the wide bitmap horizontally
            if (isPanoramic && xStep > 0f && xStep < 1f) {
                val panBmp = panoramicBitmap
                if (panBmp != null) {
                    val maxScroll = (panBmp.width - surfaceWidth).toFloat().coerceAtLeast(0f)
                    targetScrollPx = xOffset * maxScroll
                    scrollVelocity = 0f
                    if (!drawing) drawFrame()
                }
            }
            // Canvas scenes with image_layers: feed scroll offset to the renderer
            // so each layer pans at its own parallax-weighted speed. We push
            // to TARGET (not the smoothed value) so the renderer's per-frame
            // lerp glides toward it. Don't gate on xStep — Samsung One UI
            // reports xStep=-1.0 for our WallpaperService but still delivers
            // valid xOffset values during home page transitions.
            if (isCanvasSceneMode && canvasSceneRenderer.hasParallax) {
                canvasSceneRenderer.targetScrollOffsetNorm = xOffset.coerceIn(0f, 1f)
                Log.d(TAG, "  → canvasScene targetScrollOffsetNorm=${canvasSceneRenderer.targetScrollOffsetNorm}")
                if (!drawing) { drawing = true; handler.post(drawRunnable) }
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
                // Re-register parallax sensor only if a parallax scene is loaded.
                // We unregistered on visibility=false to save battery while hidden.
                if (isCanvasSceneMode && canvasSceneRenderer.hasParallax) {
                    registerGyroIfNeeded()
                }
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

                // Pixora Daily — rotate to a fresh cached wallpaper if we're in
                // daily mode and the interval elapsed. Mutates wallpaper_path in
                // prefs so the loadWallpaperImage() below picks up the new one.
                maybeRotateDaily()

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

                // Stop the parallax gyro while hidden — at SENSOR_DELAY_GAME (~50 Hz)
                // it drains battery for nothing if the user is in another app.
                // Re-registered on visibility=true above.
                unregisterGyro()

                // Same logic for battery: stop listening for ACTION_BATTERY_CHANGED
                // while the wallpaper isn't visible. Re-registered on visibility=true
                // (above, in the visible branch) before the indicator could redraw.
                batteryIndicator.unregisterBatteryReceiver()

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

            // Canvas scene scroll is now driven entirely by onOffsetsChanged
            // (Samsung treats us as scrollable thanks to
            // suggestDesiredDimensions + SET_WALLPAPER_HINTS). Touch handler
            // removed: launcher already intercepts cross-page swipes on
            // home, and the few stray touches that did reach us caused
            // double-counting with onOffsetsChanged. The launcher is the
            // single source of truth for horizontal scroll position.

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    touchTrail.onDown(event.x, event.y)
                    if (!drawing) { drawing = true; handler.post(drawRunnable) }
                }
                MotionEvent.ACTION_MOVE -> {
                    touchTrail.onMove(event.x, event.y)
                    if (!drawing) { drawing = true; handler.post(drawRunnable) }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    touchTrail.onUp()
                }
            }
        }

        private fun drawFrame() {
            if (!drawing) return
            val holder = surfaceHolder ?: return
            var canvas: Canvas? = null
            try {
                // HARDWARE CANVAS (2026-06-06): on MID/LOW tier, use the
                // GPU-backed canvas so layer bitmap blits run on the GPU
                // (~free) instead of CPU (~70ms each on Mali). HIGH tier
                // keeps the software canvas so setShadowLayer on text/arc
                // still renders the full glow effect. API 26+ required.
                canvas = if (deviceTier.useHardwareCanvas
                    && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    holder.lockHardwareCanvas() ?: holder.lockCanvas()
                } else {
                    holder.lockCanvas()
                } ?: return
                updateRendererState()

                // Frame mode: draw extracted frame instead of wallpaper bitmap
                if (isFrameMode && frameScrubRenderer.isReady) {
                    frameScrubRenderer.draw(canvas)
                } else if (isCanvasSceneMode && canvasSceneRenderer.hasParallax) {
                    // Parallax scenes draw their own image_layers — skip the bg
                    // bitmap to avoid double-drawing. Clear to black first so any
                    // edge pixels (if a layer doesn't fully cover) don't leak.
                    canvas.drawColor(android.graphics.Color.BLACK)
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

                // Pixora Island: chibi mascot that cycles by hour of day
                if (isPixoraIslandMode) {
                    pixoraFriendsRenderer.surfaceWidth = surfaceWidth
                    pixoraFriendsRenderer.surfaceHeight = surfaceHeight
                    pixoraFriendsRenderer.draw(canvas)
                }

                // Data-driven canvas scenes (volcano_dragon, dusk_fortress, and
                // any future canvas_scene wallpaper)
                if (isCanvasSceneMode) {
                    canvasSceneRenderer.surfaceWidth = surfaceWidth
                    canvasSceneRenderer.surfaceHeight = surfaceHeight
                    canvasSceneRenderer.draw(canvas)
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
                // 2026-06-07: BatteryIndicator (small gold circle on left)
                // is CLASICO-only — other presets include BAT inside their
                // HUD (horizontal_meters/hex_leds/etc) so the standalone
                // indicator would duplicate. Gated on hudStyle == GOLD_RINGS
                // (only CLASICO has that style).
                if (showBattery && currentPreset.hudStyle ==
                        com.orbix.pixora.renderers.HudStyle.GOLD_RINGS) {
                    batteryIndicator.draw(canvas)
                }
                if (!isLocked && currentPreset.showSystemHud) {
                    if (currentPreset.hudStyle == com.orbix.pixora.renderers.HudStyle.GOLD_RINGS) {
                        systemRings.draw(canvas)
                    } else {
                        hudRenderer.draw(canvas)
                    }
                    // CLASICO — 4 corner sacred-geometry ornaments. Drawn only
                    // for the CLASICO preset so others keep distinct identities.
                    if (currentPreset == com.orbix.pixora.renderers.HudPreset.CLASICO) {
                        sacredOrnaments.draw(canvas)
                    }
                }
                if (showEqualizer) {
                    equalizerRenderer.draw(canvas)
                }
                if (!isLocked) captionOverlay.draw(canvas)
                drawGlowEffects(canvas)

                // Pixora "P" 3D branding signature — universal, drawn last
                // so it sits on top of every other layer. Hidden on lock
                // screen so it doesn't compete with the system clock.
                if (!isLocked) {
                    brandingTick++
                    // Refresh per-scene overrides each frame (cheap — JSON
                    // already parsed). When current wallpaper isn't a
                    // canvas_scene the override is null and defaults apply.
                    brandingLogo.loadFrom(canvasSceneRenderer.brandingOverride)
                    brandingLogo.draw(canvas, surfaceWidth, surfaceHeight, brandingTick)
                }
            } catch (e: Exception) {
                Log.e(TAG, "drawFrame error: ${e.message}")
            } finally {
                if (canvas != null) {
                    try { holder.unlockCanvasAndPost(canvas) } catch (_: Exception) {}
                }
            }

            animationPhase += 0.05f

            val now = System.currentTimeMillis()

            // Switch to idle mode (low fps) when no audio and no touch
            val scrolling = (isPanoramic && abs(scrollVelocity) > 0.5f) ||
                            (isCanvasSceneMode && canvasSceneRenderer.hasParallax &&
                             canvasSceneRenderer.scrollSettling)
            if (!equalizerRenderer.hasAudio && !touchTrail.isActive && !isRainWallpaper && !scrolling && !hasAnimatedCanvasOverlay) {
                equalizerRenderer.silentFrames++
                // 2026-06-06 fix: do NOT release the Visualizer when going idle.
                // Previously released after 30 silent frames to save battery,
                // but that meant: music starts → Visualizer dead → can't detect
                // → bars stay frozen until the user touched the screen. The
                // Visualizer capture is cheap (<1% CPU); keeping it alive lets
                // hasAudio flip back to true the instant music plays again,
                // exiting idle mode automatically via the else branch below.
                if (equalizerRenderer.silentFrames > 30 && !idleMode) {
                    idleMode = true
                }
            } else {
                equalizerRenderer.silentFrames = 0
                if (idleMode) {
                    idleMode = false
                    // setupVisualizer is now safe to skip — visualizer was
                    // never released. Calling it again would just re-init for
                    // no reason. Left as a no-op comment for future devs.
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
            // Delegated to the user-selectable TouchTrailRenderer.
            // brandingTick doubles as the trail tick — both increment per frame.
            touchTrail.draw(canvas, surfaceWidth, surfaceHeight, brandingTick, glowColor)
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
            unregisterGyro()
            handler.removeCallbacks(drawRunnable)
            pendingReload?.let { handler.removeCallbacks(it) }
            equalizerRenderer.releaseVisualizer()
            stopVideoWallpaper()
            aquariumRenderer.recycle()
            bubbleRenderer.reset()
            fireflyRenderer.reset()
            jellyfishRenderer.recycle()
            pixoraFriendsRenderer.release()
            canvasSceneRenderer.release()
            brandingLogo.release()
            batteryIndicator.release()
            unregisterPrefsListener()
            unregisterKeyguardReceiver()
            unregisterOverlaySettingsReceiver()
            unregisterWallpaperPathReceiver()
            unregisterAdVisibilityReceiver()
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

    companion object {
        private const val TAG = "PixoraEQ"
        const val BAR_COUNT = 32  // bumped from 6 (2026-06-04) — thinner bars + more detail
        const val FRAME_DELAY = 33L // ~30fps
        const val IDLE_FRAME_DELAY = 1000L
        // Lowered 2026-06-06 from 0.05 → 0.02 so quiet music + voices trip
        // hasAudio sooner — user feedback: bars took too long to react.
        const val SILENCE_THRESHOLD = 0.02f
        const val RAIN_DROP_COUNT = 120
        const val GLASS_DROP_COUNT = 15
        const val CITY_LIGHT_COUNT = 35
    }
}
