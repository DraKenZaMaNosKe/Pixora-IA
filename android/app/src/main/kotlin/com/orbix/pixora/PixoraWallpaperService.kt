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

        // 2026-06-10 — loadWallpaperImage early-return key. Holds a compact
        // string of every pref that influences the load result (path, scene,
        // interactive, color, caption, trail). When onVisibilityChanged +
        // onSurfaceChanged + the debounced prefs reload fire back-to-back
        // with identical state (the common case), we skip the entire body —
        // recycler reset, sprite loads, mode flag flips, decode-bounds probe.
        // Roughly 15-25ms saved per redundant call on MID tier.
        @Volatile private var lastLoadedConfigKey: String? = null
        // FCM catalog_invalidate bumps changed_at — bypass config/bitmap idempotency
        // so canvas_scene layers + flat wallpaper re-decode after remote edits.
        @Volatile private var lastHandledChangedAt: Long = 0L

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
        // 2026-06-15 — drag-relative scrub anchors
        private var scrubDragStartX = 0f       // dedo X cuando empezó el drag
        private var scrubDragStartIndex = 0    // frame en el que estaba al empezar
        // Sensibilidad del drag: cuántos px de movimiento = 1 frame de delta.
        // 80px/frame → para recorrer un video de 24 frames hay que arrastrar
        // 80*24 = 1920px (~1.8 swipes del ancho de pantalla 1080). Esto da
        // una sensación natural similar a otros sliders touch nativos.
        private val scrubPixelsPerFrame = 80f
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
                (isCanvasSceneMode && canvasSceneRenderer.needsContinuousAnimation)

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
        // Defaults flipped to FALSE 2026-06-20 (Eduardo): la mayoría de
        // wallpapers se ven mejor SIN HUD overlays. Esto también lleva
        // el live wallpaper a 0 fps efectivos cuando todo está estático,
        // ahorrando GPU y batería. User puede activar desde Settings.
        @Volatile private var showClock = false
        @Volatile private var showBattery = false
        @Volatile private var showEqualizer = false
        // Master switch para el HUD del preset (systemRings/hudRenderer/
        // sacredOrnaments) + branding logo. Off por default — el preset
        // sigue persistido pero NO se dibuja hasta que el user activa.
        @Volatile private var showHudOverlays = false

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
            showClock = prefs.getBoolean("show_clock", false)
            showBattery = prefs.getBoolean("show_battery", false)
            showEqualizer = prefs.getBoolean("show_equalizer", false)
            showHudOverlays = prefs.getBoolean("show_hud_overlays", false)
            systemRings.showRam = prefs.getBoolean("show_ram", false)
            systemRings.showStorage = prefs.getBoolean("show_storage", false)
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

        // 2026-06-10 — track when the user actually unlocked the device.
        // ACTION_USER_PRESENT fires ONLY on a real lockscreen → home unlock.
        // We use this to gate the "every unlock" rotation mode so that
        // returning from WhatsApp / switching apps (which also fires
        // onVisibilityChanged(true)) does NOT trigger a rotation.
        // 5-second window matches the natural gap between USER_PRESENT
        // and onVisibilityChanged(true) on Samsung One UI, even with slow
        // biometric paths.
        @Volatile private var lastUserPresentAt = 0L

        // Broadcast receiver only forces a redraw on screen events — doesn't own state.
        // This way a missed ACTION_USER_PRESENT (which happens on some Samsung configs
        // with fast biometric unlock) doesn't leave overlays permanently hidden.
        private val keyguardReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_USER_PRESENT) {
                    lastUserPresentAt = System.currentTimeMillis()
                }
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
                    // Canvas scenes with bob animation (e.g. Throotle's
                    // floating turtle) MUST stay at marquee fps even when
                    // idle — at 1fps the bob looks like teleporting jumps
                    // instead of a smooth float.
                    val sceneBobbing = isCanvasSceneMode &&
                        canvasSceneRenderer.needsContinuousAnimation
                    val delay = when {
                        isFrameMode -> IDLE_FRAME_DELAY
                        sceneBobbing -> deviceTier.idleMarqueeFrameDelay
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

                // 2026-06-10 — "every unlock" mode (intervalMinutes=0) must
                // only fire on a REAL device unlock, not on any visibility
                // change. Returning from WhatsApp / switching apps also
                // triggers onVisibilityChanged(true) but does NOT fire
                // ACTION_USER_PRESENT. Gate the rotation on a recent
                // USER_PRESENT broadcast (5s window covers Samsung One UI
                // biometric paths). Without this gate, the wallpaper changed
                // every time the user came back to home from another app.
                if (dailyIntervalMs == 0L) {
                    val sincePresent = now - lastUserPresentAt
                    if (sincePresent > 5000L) {
                        // visibility=true without a real unlock — ignore
                        return
                    }
                    // Prevent double-rotation in the same unlock event.
                    // Samsung One UI fires onVisibilityChanged(true) multiple
                    // times within ~1s of a single unlock. If we already
                    // rotated AFTER this USER_PRESENT, skip.
                    if (dailyLastRotation > lastUserPresentAt) {
                        return
                    }
                } else if (now - dailyLastRotation < dailyIntervalMs) {
                    return
                }

                val cacheDir = File(applicationContext.filesDir, "auto_rotate_cache")
                // 2026-06-10 (Eduardo) — Daily ONLY rotates static + panoramic
                // wallpapers, NEVER live videos. See AutoRotateService.start
                // comment for the full rationale. The filter here is DEFENSIVE:
                // if a stale .mp4 lingers in the cache from a prior version
                // (or some edge case future-prefetch leaks one in), we ignore
                // it instead of risking the canvas↔video transition crash.
                val files = cacheDir.listFiles()
                    ?.filter {
                        it.extension != "tmp" &&
                        it.length() > 0 &&
                        !it.name.endsWith(".mp4", ignoreCase = true)
                    }
                    ?: return
                if (files.size < 2) return // nothing to rotate to

                // ── Seen tracking (2026-06-09) ─────────────────────────────
                // BUG FIX: previous logic used `files.filter{..}.randomOrNull()`
                // with no memory of past picks. With a typical cache of ~20
                // images, birthday-paradox math made obvious repeats within
                // ~5 rotations. Users reported "siempre son las mismas".
                // Fix: persist seen filenames; pick from un-seen only;
                // when every cached file has been shown, reset (cycle complete).
                val seenKey = "daily_seen_names"
                val seen = livePrefs.getStringSet(seenKey, null)?.toMutableSet()
                    ?: mutableSetOf()

                // 2026-06-10 — prune ghost entries.
                // The AutoRotateWorker (background prefetch) cleans up old
                // cache files via LRU when files.size > MAX_CACHED_WALLPAPERS,
                // but it lives in a different SharedPreferences and CANNOT
                // touch our `daily_seen_names` set. Without this prune step,
                // seen accumulates names of files that were deleted by the
                // worker. Symptom: "seen 26/25", "seen 27/25" in logcat — and
                // eventually the rotation stalls because most of `seen`
                // points at ghosts so the un-seen pool shrinks faster than
                // files do, and the cycle-complete reset (`seen.clear`)
                // never fires because there's always some genuinely-new file.
                val currentFilenames = files.mapTo(HashSet()) { it.name }
                val beforePrune = seen.size
                seen.removeAll { it !in currentFilenames }
                if (seen.size != beforePrune) {
                    Log.d(TAG, "Daily: pruned ${beforePrune - seen.size} ghost names from seen set (worker deleted them)")
                }

                // Mark the OUTGOING file as seen (it's about to be replaced).
                seen.add(File(current).name)

                // Selection — static + panoramic only (2026-06-10 decision).
                // Live was removed from the pool above. Pick a random un-seen
                // file; when the set is exhausted, reset (cycle complete).
                fun unseen(pool: List<java.io.File>) = pool.filter {
                    it.name !in seen && it.absolutePath != current
                }
                var candidates = unseen(files)

                // Every cached file shown → reset per user spec
                // ("ya que vio todos, pues reset completo").
                if (candidates.isEmpty()) {
                    Log.d(TAG, "Daily cycle complete (${seen.size} files seen) — resetting seen set")
                    seen.clear()
                    seen.add(File(current).name)  // keep outgoing so we don't pick it next
                    candidates = unseen(files)
                    if (candidates.isEmpty()) {
                        candidates = files.filter { it.absolutePath != current }
                    }
                }

                val next = candidates.randomOrNull() ?: return
                dailyLastRotation = now

                // ── Cache cleanup ─────────────────────────────────────────
                // Cap disk footprint at DAILY_DISK_MAX files. When exceeded,
                // delete the oldest already-seen files (LRU on mtime).
                if (files.size > DAILY_DISK_MAX) {
                    val toDelete = files
                        .filter { it.name in seen && it.absolutePath != next.absolutePath }
                        .sortedBy { it.lastModified() }
                        .take(files.size - DAILY_DISK_MAX)
                    var deleted = 0
                    for (f in toDelete) {
                        if (f.delete()) {
                            seen.remove(f.name)
                            deleted++
                        }
                    }
                    if (deleted > 0) {
                        Log.d(TAG, "Daily cleanup: deleted $deleted oldest-seen files")
                    }
                }

                // ── Type-aware transition (Phase 4 — 2026-06-09) ─────────
                // Detect canvas↔video mode change via .mp4 extension.
                // Same-mode (static→static OR live→live within same Surface
                // producer): soft transition via prefs broadcast — instant.
                // Cross-mode (static↔live): MUST kill self so Android respawns
                // the engine with a clean Surface. The Canvas producer's
                // touch state survives unlockCanvasAndPost(), so a fresh
                // MediaPlayer.setSurface() on the same Engine would fail
                // with -22 (EINVAL). See CLAUDE.md pitfall A + commit history.
                val wasLive = current.endsWith(".mp4", ignoreCase = true)
                val nextIsLive = next.name.endsWith(".mp4", ignoreCase = true)
                val typeTransition = wasLive != nextIsLive

                val editor = livePrefs.edit()
                    .putString("wallpaper_path", next.absolutePath)
                    .putLong("daily_last_rotation", now)
                    .remove("scene_id")
                    .putBoolean("interactive", false)
                    .putStringSet(seenKey, seen)

                if (typeTransition) {
                    // CRITICAL: commit() (synchronous) is REQUIRED before
                    // self-kill. With .apply() the daily_last_rotation write
                    // is async and gets dropped when killProcess fires before
                    // disk flush — the respawned engine then reads the STALE
                    // timestamp, sees enough time has passed, rotates AGAIN,
                    // self-kills AGAIN. Android falls back to ImageWallpaper
                    // after 2-3 rapid kills (saw this on 2026-06-10).
                    editor.commit()
                    currentWallpaperPath = next.absolutePath
                    Log.d(TAG, "Daily TYPE transition (canvas↔video) — self-kill so Surface resets cleanly → ${next.name}")
                    android.os.Process.killProcess(android.os.Process.myPid())
                    return
                }

                // Same-type rotation: apply() (async) is fine and faster.
                editor.apply()
                currentWallpaperPath = next.absolutePath
                Log.d(TAG, "Daily rotated → ${next.name} (seen ${seen.size}/${files.size}, interval ${dailyIntervalMs / 60000}min)")
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

        /**
         * 2026-06-15 — Centralizar inferencia + persistencia de scene flags.
         *
         * Antes esta lógica vivía inline dentro de loadWallpaperImage() (~170
         * líneas con sub-inits intercalados), que SOLO corre para wallpapers
         * static. Cuando aplicabas un video/frame, esa función NO corre y los
         * flags del wallpaper anterior persistían — drawFrame() pintaba el
         * nuevo wallpaper + ENCIMA los renderers viejos (peces, fireflies,
         * etc.). Lo descubrimos con Snoopy Explore tras venir de Aquarium.
         *
         * Ahora TODO entry point que active un wallpaper llama applySceneFlags
         * para garantizar el state está limpio:
         *   · loadWallpaperImage → applySceneFlags(path, sceneId)
         *   · startVideoWallpaper → applySceneFlags(null, null) al inicio
         *
         * @param path path del wallpaper o null (null = limpiar todos los
         *             scene modes, ej. cuando entras a video puro sin
         *             background image).
         * @param sceneId data-driven canvas scene id o null/blank.
         */
        private fun applySceneFlags(path: String?, sceneId: String?) {
            val p = path ?: ""

            // 2026-06-20 — GPU cleanup en transiciones de wallpaper.
            // Snapshot del estado previo ANTES de actualizar los flags
            // para detectar qué renderers pasan de activo→inactivo y
            // liberar sus assets (sprites, bitmaps, texturas). Sin esto,
            // los assets del wallpaper anterior quedaban residentes en
            // GPU sumando ~60 MB sin razón. El cleanup existente en
            // loadWallpaperImage SOLO cubría static→static — videos,
            // canvas_scenes y frame mode no pasan por ahí.
            val wasFireflyMode = isFireflyMode
            val wasJellyfishMode = isJellyfishMode
            val wasAquariumMode = isAquariumMode
            val wasCanvasSceneMode = isCanvasSceneMode
            val wasPixoraIslandMode = isPixoraIslandMode

            // Inferencia desde keywords en el path — mantener el matching exacto
            // del que estaba antes en loadWallpaperImage() para no romper
            // wallpapers cuyo nombre matchee (ej. aquarium*.webp, firefly_*.png).
            isRainWallpaper = p.contains("lofi_girl_rain")
            isFireflyMode = p.contains("firefly")
            isJellyfishMode = p.contains("jellyfish")
            isPixoraIslandMode = p.contains("pixora_island")
            isAquariumMode = p.contains("aquarium")
            isCanvasSceneMode = !sceneId.isNullOrBlank()

            // Cleanup proactivo de renderers que dejan de estar activos.
            // Cada renderer libera sprites + bitmaps en su recycle/release.
            // firefly y aquarium comparten aquariumRenderer (firefly carga
            // moths como "peces"); solo lo reciclamos cuando NINGUNO de
            // los dos modos está activo.
            val aquariumLikeStillActive = isAquariumMode || isFireflyMode
            if ((wasAquariumMode || wasFireflyMode) && !aquariumLikeStillActive) {
                aquariumRenderer.recycle()
                bubbleRenderer.reset()
            }
            if (wasFireflyMode && !isFireflyMode) {
                fireflyRenderer.reset()
            }
            if (wasJellyfishMode && !isJellyfishMode) {
                jellyfishRenderer.recycle()
            }
            if (wasCanvasSceneMode && !isCanvasSceneMode) {
                canvasSceneRenderer.release()
            }
            if (wasPixoraIslandMode && !isPixoraIslandMode) {
                pixoraFriendsRenderer.release()
            }

            // rainRenderer guarda su propio flag interno — mantener sincronizado
            rainRenderer.isRainWallpaper = isRainWallpaper

            // Persistir sceneId. :wallpaper process puede ser killed por canvas↔video
            // Surface conflict; al respawn lo carga de prefs.
            val editor = applicationContext
                .getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                .edit()
            if (sceneId.isNullOrBlank()) {
                editor.remove("scene_id")
            } else {
                editor.putString("scene_id", sceneId)
            }
            editor.apply()
        }

        /**
         * Init Firefly scene: 4 luna moths + 1 owl + fireflies. Caller responsible
         * de checar isFireflyMode + surface ready. Idempotente — no recarga si
         * los sprites ya están.
         */
        private fun initFireflyScene() {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return
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
                aquariumRenderer.addFish(1, "aquarium/firefly/owl", scaleMin = 0.7f, scaleMax = 0.7f, speedMin = 0f, speedMax = 0f)
                aquariumRenderer.setLastFishPosition(surfaceWidth * 0.78f, surfaceHeight * 0.02f)
            }
            Log.d(TAG, "Firefly mode activated: 4 luna moths + 1 owl + fireflies (${surfaceWidth}x${surfaceHeight})")
        }

        /**
         * Init Jellyfish scene: bioluminescent jellies + bubbles + occasional anglerfish.
         */
        private fun initJellyfishScene() {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return
            jellyfishRenderer.surfaceWidth = surfaceWidth
            jellyfishRenderer.surfaceHeight = surfaceHeight
            jellyfishRenderer.loadSprites("aquarium/jellyfish_blue")
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
                if (jellyfishRenderer.hasSprites("aquarium/jellyfish_gold")) {
                    jellyfishRenderer.addJellies(
                        count = 1,
                        spriteFolder = "aquarium/jellyfish_gold",
                        scaleMin = 0.9f, scaleMax = 1.15f,
                        speedMin = 0.25f, speedMax = 0.5f,
                        swayAmpMin = 25f, swayAmpMax = 45f,
                    )
                }
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
            bubbleRenderer.surfaceWidth = surfaceWidth
            bubbleRenderer.surfaceHeight = surfaceHeight
            // Occasional deep-sea anglerfish
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

        /**
         * Init Pixora Island scene: chibi mascot day-cycle.
         */
        private fun initPixoraIslandScene() {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return
            pixoraFriendsRenderer.surfaceWidth = surfaceWidth
            pixoraFriendsRenderer.surfaceHeight = surfaceHeight
            pixoraFriendsRenderer.scale = (surfaceWidth * 0.22f) / 120f
            Log.d(TAG, "Pixora Island mode activated: chibi mascot day-cycle (${surfaceWidth}x${surfaceHeight})")
        }

        /**
         * Init Canvas Scene: data-driven FX (volcano_dragon, dusk_fortress, etc.).
         * @return true si el spec cargó OK, false si falló (caller debe revertir
         *         isCanvasSceneMode a false).
         */
        private fun initCanvasScene(sceneId: String): Boolean {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return false
            canvasSceneRenderer.surfaceWidth = surfaceWidth
            canvasSceneRenderer.surfaceHeight = surfaceHeight
            val ok = canvasSceneRenderer.loadSpec(sceneId)
            if (ok) {
                canvasSceneRenderer.ensureLoaded()
                Log.d(TAG, "Canvas scene activated: $sceneId (${surfaceWidth}x${surfaceHeight})")
                if (canvasSceneRenderer.hasParallax) {
                    registerGyroIfNeeded()
                } else {
                    unregisterGyro()
                }
            } else {
                Log.w(TAG, "Canvas scene failed to load: $sceneId — falling back")
                unregisterGyro()
            }
            return ok
        }

        /**
         * Init Aquarium scene: betta + angelfish + neon tetras + bubbles.
         */
        private fun initAquariumScene() {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return
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

                // 2026-06-10 — early-return guard. onVisibilityChanged +
                // onSurfaceChanged + the prefs-changed debounce dispatcher
                // all funnel into loadWallpaperImage(), often 3-4 times per
                // rotation with identical state. If nothing meaningful
                // changed since the last successful load AND the bitmap (or
                // MediaPlayer for video) is still alive, skip the entire
                // body — no renderer recycles, no sprite loads, no decode.
                val sceneIdEarly = prefs.getString("scene_id", null)
                val changedAt = prefs.getLong("changed_at", 0L)
                val contentRefresh = changedAt > lastHandledChangedAt
                val configKey =
                    "$path|$sceneIdEarly|$isInteractive|$color|$caption|$trailStyle"
                if (!contentRefresh && configKey == lastLoadedConfigKey) {
                    val hasLiveBitmap = wallpaperBitmap?.let { !it.isRecycled } == true
                    val hasLiveVideo = isVideoWallpaper && mediaPlayer != null
                    if (hasLiveBitmap || hasLiveVideo) {
                        // Cheap consistency: keep currentWallpaperPath in sync
                        // since callers (rotation, broadcast) rely on it.
                        currentWallpaperPath = path
                        return
                    }
                }
                if (contentRefresh) {
                    lastHandledChangedAt = changedAt
                    Log.d(TAG, "loadWallpaperImage: content refresh (changed_at=$changedAt)")
                }
                lastLoadedConfigKey = configKey

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
                // 2026-06-15 refactor — Scene flags + sub-renderer init
                // centralizado en applySceneFlags() + initXxxScene() helpers.
                // Antes vivía aquí inline (~170 líneas) y se duplicaba/leakeaba
                // entre transitions porque otros entry points (startVideoWallpaper,
                // story, etc.) NO corren este código y heredaban flags stale.
                // Ahora ES ÚNICAMENTE el caller que decide los flags vía
                // applySceneFlags(path, sceneId), y los inits son explícitos.
                val sceneId = prefs.getString("scene_id", null)
                applySceneFlags(path, sceneId)

                if (isFireflyMode) initFireflyScene()
                if (isJellyfishMode) initJellyfishScene()
                if (isPixoraIslandMode) initPixoraIslandScene()
                if (isCanvasSceneMode && sceneId != null) {
                    if (!initCanvasScene(sceneId)) {
                        // load falló → applySceneFlags ya seteó isCanvasSceneMode=true
                        // pero el spec no cargó. Revertir.
                        isCanvasSceneMode = false
                        unregisterGyro()
                    }
                } else if (!isCanvasSceneMode) {
                    unregisterGyro()
                }
                if (isAquariumMode) initAquariumScene()

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
                        if (!contentRefresh &&
                            path == lastDecodedPath &&
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
        // 2026-06-15 — Token-based startup race guard.
        //
        // El problema: `videoStarting` es boolean simple y se resetea
        // false en 11 lugares (early returns por surface no ready, file
        // not found, error de MediaPlayer, etc.). Cada reset abre una
        // ventana donde otra startVideoWallpaper (típicamente disparada
        // por onVisibilityChanged callbacks rapidos de Android) entra,
        // pasa la guarda, y crea otro MediaPlayer en paralelo. Resultado
        // observado en logcat: "preparing #1" + "preparing #2" en 100ms
        // + "READY #1" + "READY #2" — 2 MediaPlayer activos, waste de
        // RAM/CPU.
        //
        // Fix: cada startVideoWallpaper incrementa un token. continueVideoStart
        // y los callbacks onPrepared/onError verifican que su token sigue
        // siendo el activo antes de asignar mediaPlayer = player o de
        // resetear flags. Callbacks de tokens viejos hacen release
        // silencioso de su player — el último startup gana siempre.
        @Volatile private var currentStartupToken: Long = 0

        private var videoRetryCount = 0
        private val MAX_VIDEO_RETRIES = 10

        private fun startVideoWallpaper(path: String) {
            // 2026-06-10 fix — idempotency guard.
            // loadWallpaperImage() can fire 4-6 times per video transition
            // (onSurfaceChanged + onVisibilityChanged + prefs reload debounce +
            // engine attach). Without this guard, each fires a fresh
            // startVideoWallpaper, each races to .setSurface(player), and
            // some of them leave the HWUI CanvasContext in an inconsistent
            // state — surfacing later as 'drawRenderNode called on a context
            // with no surface' SIGABRT on the next visibility change. If we
            // already have a MediaPlayer playing this exact path, do nothing.
            synchronized(videoLock) {
                if (isVideoWallpaper && currentWallpaperPath == path &&
                    mediaPlayer != null) {
                    Log.d(TAG, "startVideoWallpaper: already playing $path — skip")
                    return
                }
                if (videoStarting) {
                    Log.d(TAG, "startVideoWallpaper: another start in flight — skip")
                    return
                }
                videoStarting = true
                // 2026-06-15 — bump token. Cada nuevo startup invalida los
                // anteriores; sus callbacks (onPrepared/onError de cualquier
                // MediaPlayer que estuviera preparándose) descartarán sus
                // players porque su token capturado ya no será el activo.
                currentStartupToken++
            }
            val myToken = currentStartupToken
            Log.d(TAG, "Starting video: $path (token=$myToken)")

            // 2026-06-15 — Garantizar que NINGÚN scene overlay del wallpaper
            // anterior (Aquarium, Firefly, Jellyfish, Pixora Island, Canvas
            // Scene, Rain) quede activo cuando entramos a video/frame mode.
            // loadWallpaperImage() infiere scene flags por keyword en path,
            // pero esa función no corre cuando entras a video — sin este
            // cleanup central, los renderers se dibujarían ENCIMA del video
            // o del frame scrub (bug Snoopy Explore 2026-06-15).
            applySceneFlags(null, null)

            // Stop canvas drawing
            drawing = false
            handler.removeCallbacks(drawRunnable)
            equalizerRenderer.releaseVisualizer()
            synchronized(bitmapLock) {
                scaledBitmap = null
                panoramicBitmap = null
                wallpaperBitmap = null
            }

            // 2026-06-10 fix — do NOT call stopVideoWallpaper() here.
            // That helper resets videoStarting=false and isVideoWallpaper=false,
            // re-opening the guard above for any parallel callers and undoing
            // the state we just claimed. Instead, release any existing player
            // inline while preserving our in-flight flags.
            val prevPlayer: MediaPlayer?
            synchronized(videoLock) {
                prevPlayer = mediaPlayer
                mediaPlayer = null
            }
            if (prevPlayer != null) {
                releaseMediaPlayerSafely(prevPlayer)
                Log.d(TAG, "Released previous MediaPlayer before starting new one")
            }
            handler.removeCallbacks(frameScrubUpdateRunnable)
            frameScrubRenderer.release()
            isFrameMode = false
            cachedDuration = 0L
            videoRetryCount = 0
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
                // 2026-06-15 — DEJAR isVideoWallpaper=true en modo Explore.
                // onTouchEvent() require `isInteractive && isVideoWallpaper` para
                // procesar el touch scrub. Si lo limpiamos aquí, el preview se
                // ve pero queda congelado en el primer frame (sin respuesta al
                // touch). La guarda de drawFrame() ahora distingue entre modo
                // video real y modo frame (ver fix abajo).
                synchronized(videoLock) { videoStarting = false }

                // (Scene flag cleanup ahora vive en applySceneFlags(null, null)
                // llamado al inicio de startVideoWallpaper — cubre TODOS los
                // paths video/frame, no solo este branch Explore.)

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

            // 2026-06-10 fix — HWUI RenderThread drain delay.
            // When the :wallpaper process respawns after a kill (canvas↔video
            // transition), the new Engine instance may have already enqueued a
            // first canvas frame via lockHardwareCanvas() before this code
            // runs. With SkiaOpenGL pipeline (API 26+, MID/LOW tier), that
            // frame is processed ASYNCHRONOUSLY on the system RenderThread.
            // If we call MediaPlayer.setSurface(surface) before the
            // RenderThread finishes that frame, the RenderThread crashes with
            // a SIGABRT at SkiaOpenGLPipeline::getFrame because the surface
            // it expected to draw into has been claimed by the MediaPlayer.
            // A short delay drains the in-flight frame.
            // See logcat from 2026-06-10 00:37:02: "F ixora:wallpaper
            //   runtime.cc: SkiaOpenGLPipeline::getFrame+48".
            handler.postDelayed({ continueVideoStart(path, myToken) }, 120)
        }

        /**
         * Helper: ¿este token sigue siendo el activo? Si no, otro startup
         * llegó después y ya invalido este. Caller debe limpiar lo que pueda.
         */
        private fun isTokenStale(token: Long): Boolean = token != currentStartupToken

        /**
         * Helper: reset videoStarting condicionalmente — solo si el token
         * dado sigue siendo el activo. Si otro startup ya tomó el control,
         * NO tocamos videoStarting (eso ya es responsabilidad de aquel).
         */
        private fun resetStartingIfMine(token: Long) {
            synchronized(videoLock) {
                if (token == currentStartupToken) {
                    videoStarting = false
                }
            }
        }

        private fun continueVideoStart(path: String, token: Long) {
            // Bail early si ya hay un startup más nuevo en flight — su propio
            // continueVideoStart manejará el setup, no queremos correr en paralelo.
            if (isTokenStale(token)) {
                Log.d(TAG, "continueVideoStart token=$token stale (current=$currentStartupToken), skip")
                return
            }

            // Auto Play: use MediaPlayer — wait for valid surface
            val surface = surfaceHolder?.surface
            if (surface == null || !surface.isValid) {
                // Surface not ready yet — retry shortly (reset guard so retry can enter)
                resetStartingIfMine(token)
                if (videoRetryCount < MAX_VIDEO_RETRIES) {
                    videoRetryCount++
                    Log.d(TAG, "Surface not ready, retry $videoRetryCount/$MAX_VIDEO_RETRIES")
                    handler.postDelayed({ startVideoWallpaper(path) }, 200)
                } else {
                    Log.e(TAG, "Surface never became ready after $MAX_VIDEO_RETRIES retries")
                    videoRetryCount = 0
                    // 2026-06-15 fix bonus — resetear isVideoWallpaper TAMBIÉN
                    // resetea videoStarting si es nuestro token. Antes solo
                    // limpiaba isVideoWallpaper, dejando la guarda permanentemente
                    // cerrada hasta el siguiente startup.
                    resetStartingIfMine(token)
                    isVideoWallpaper = false
                }
                return
            }
            videoRetryCount = 0

            val videoFile = File(path)
            if (!videoFile.exists()) {
                Log.e(TAG, "Video not found: $path")
                resetStartingIfMine(token)
                isVideoWallpaper = false
                return
            }

            var mp: MediaPlayer? = null
            try {
                // Re-check surface validity right before use (can become invalid between check and use)
                val currentSurface = surfaceHolder?.surface
                if (currentSurface == null || !currentSurface.isValid) {
                    Log.w(TAG, "Surface became invalid before MediaPlayer setup")
                    resetStartingIfMine(token)
                    isVideoWallpaper = false
                    return
                }
                // Re-check token: el ASYNC postDelayed pudo haber pasado tiempo
                // suficiente para que otro startVideoWallpaper haya entrado.
                // Si nuestro token ya es viejo, abortar antes de crear MediaPlayer.
                if (isTokenStale(token)) {
                    Log.d(TAG, "continueVideoStart token=$token went stale during surface check, skip")
                    return
                }
                val player = MediaPlayer()
                mp = player
                player.setDataSource(path)
                player.setSurface(currentSurface)
                player.setVolume(0f, 0f)
                player.isLooping = true

                player.setOnPreparedListener {
                    // 2026-06-15 — si otro startup invalido este token mientras
                    // preparábamos, descartar este player. Su lugar lo toma el
                    // MediaPlayer del startup más nuevo.
                    if (isTokenStale(token)) {
                        Log.d(TAG, "MediaPlayer READY but token=$token stale — releasing silently")
                        releaseMediaPlayerSafely(player)
                        return@setOnPreparedListener
                    }
                    Log.d(TAG, "MediaPlayer READY: $path (token=$token)")
                    synchronized(videoLock) {
                        mediaPlayer = player
                        videoStarting = false
                        currentWallpaperPath = path
                    }
                    try { player.start() } catch (e: Exception) { Log.e(TAG, "start failed: ${e.message}") }
                }

                player.setOnErrorListener { _, what, extra ->
                    Log.e(TAG, "MediaPlayer error: what=$what extra=$extra (token=$token)")
                    releaseMediaPlayerSafely(player)
                    synchronized(videoLock) {
                        if (mediaPlayer === player) mediaPlayer = null
                        // Solo reset videoStarting si seguimos siendo el activo.
                        if (token == currentStartupToken) {
                            videoStarting = false
                        }
                    }
                    // Solo desactivar isVideoWallpaper si era nuestro player el
                    // que estaba activo (no si otro lo reemplazó ya).
                    if (token == currentStartupToken) {
                        isVideoWallpaper = false
                        handler.post {
                            drawing = true
                            handler.post(drawRunnable)
                        }
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
                Log.d(TAG, "MediaPlayer preparing... (token=$token)")
            } catch (e: Exception) {
                Log.e(TAG, "MediaPlayer FAILED: ${e.javaClass.simpleName}: ${e.message}")
                e.printStackTrace()
                // Critical: release the local instance so it doesn't leak
                if (mp != null) releaseMediaPlayerSafely(mp)
                resetStartingIfMine(token)
                if (token == currentStartupToken) isVideoWallpaper = false
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

            // Interactive mode: DRAG-relative scrub.
            // 2026-06-15 — Cambiado de posición absoluta (event.x / surfaceWidth
            // → frame index) a delta-de-arrastre relativo. Con solo 24 frames y
            // 1080px de ancho, el mapeo absoluto daba 45px/frame — demasiado
            // sensible para un dedo (un swipe corto recorría todo el video). El
            // nuevo modelo: ACTION_DOWN ancla la posición y el frame actual,
            // cada ACTION_MOVE suma deltaX/scrubPixelsPerFrame al frame target.
            // Con 80px/frame, 24 frames requieren ~1920px de arrastre (~1.8x
            // ancho), sensación natural cercana a un slider iOS.
            if (isInteractive && isVideoWallpaper) {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        scrubDragStartX = event.x
                        if (isFrameMode && frameScrubRenderer.isReady) {
                            scrubDragStartIndex = frameScrubRenderer.currentFrameIndex
                        } else {
                            // ExoPlayer fallback: single absolute seek en DOWN
                            // (MediaPlayer.seekTo es caro para spamear en MOVE).
                            val player = mediaPlayer
                            if (player != null && player.duration > 0) {
                                val pct = (event.x / surfaceWidth.toFloat()).coerceIn(0f, 1f)
                                player.seekTo((pct * player.duration).toInt().coerceIn(0, player.duration - 1))
                            }
                        }
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (isFrameMode && frameScrubRenderer.isReady) {
                            val deltaX = event.x - scrubDragStartX
                            val deltaFrames = (deltaX / scrubPixelsPerFrame).toInt()
                            val targetFrame = scrubDragStartIndex + deltaFrames
                            frameScrubRenderer.seekToIndex(targetFrame)
                            handler.removeCallbacks(frameScrubUpdateRunnable)
                            handler.post(frameScrubUpdateRunnable)
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
            // 2026-06-10 — second line of defense against the canvas↔video
            // race that crashed the RenderThread (see continueVideoStart for
            // the full story). If somehow a stale drawRunnable fires after
            // we flipped to video mode, refuse to lock the Surface.
            // MediaPlayer owns it now; lockCanvas() here would push another
            // HWUI frame into the system RenderThread and re-trigger the
            // SkiaOpenGLPipeline::getFrame SIGABRT.
            //
            // 2026-06-15 — Excepción para Explore (frame scrub). En modo frames
            // NO hay MediaPlayer, dibujamos vía Canvas igual que canvas scenes.
            // isVideoWallpaper queda en true para que onTouchEvent procese el
            // touch scrub, pero isFrameMode=true habilita el render Canvas.
            if (isVideoWallpaper && !isFrameMode) return
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

                // Pre-load parallax layers before deciding bg vs black clear.
                if (isCanvasSceneMode) {
                    canvasSceneRenderer.ensureLoaded()
                }

                // Frame mode: draw extracted frame instead of wallpaper bitmap
                if (isFrameMode && frameScrubRenderer.isReady) {
                    frameScrubRenderer.draw(canvas)
                } else if (isCanvasSceneMode && canvasSceneRenderer.hasParallax
                    && canvasSceneRenderer.layersReady) {
                    // Parallax scenes draw their own image_layers — skip the bg
                    // bitmap to avoid double-drawing. Clear to black first so any
                    // edge pixels (if a layer doesn't fully cover) don't leak.
                    canvas.drawColor(android.graphics.Color.BLACK)
                } else {
                    // Fallback: layers not ready yet (or download failed) → show
                    // wallpaper_path flat image instead of a black screen.
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
                // 2026-06-20 — `showHudOverlays` (master switch, default
                // false) gate al systemHud y ornamentos. Sin esto el preset
                // SACRED/CLASICO dibujaba el HUD aunque los toggles
                // individuales estuvieran en false → wallpaper nunca podía
                // ser "imagen pura".
                if (!isLocked && showHudOverlays && currentPreset.showSystemHud) {
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

                // Pixora "P" 3D branding signature — drawn last so it
                // sits on top. Hidden on lock screen + gated por
                // showHudOverlays para que el wallpaper pueda ser
                // realmente "imagen pura" cuando user quiere.
                if (!isLocked && showHudOverlays) {
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
            // 2026-06-16 — Aggressive release de renderers PESADOS cuando el
            // preview Engine se destruye (user tap "Definir fondo de pantalla").
            // Sin esto, los ~30-50MB de bitmaps del preview se quedan
            // referenced hasta que el GC los cobre, y en devices low-RAM
            // (Samsung 4GB) eso es suficiente para que lmkd mate Pixora.
            //
            // SOLO release en isPreview porque el Engine applied SÍ va a
            // reusar la Surface después (ej. onVisibilityChanged false→true
            // al abrir/cerrar el launcher). Liberar aquí rompería el applied.
            if (isPreview) {
                Log.d(TAG, "onSurfaceDestroyed isPreview → aggressive release")
                frameScrubRenderer.release()
                aquariumRenderer.recycle()
                bubbleRenderer.reset()
                fireflyRenderer.reset()
                jellyfishRenderer.recycle()
                pixoraFriendsRenderer.release()
                canvasSceneRenderer.release()
                synchronized(bitmapLock) {
                    wallpaperBitmap?.recycle(); wallpaperBitmap = null
                    scaledBitmap?.recycle(); scaledBitmap = null
                    panoramicBitmap?.recycle(); panoramicBitmap = null
                }
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
        // Daily rotation: hard cap on cached files. When the auto_rotate
        // cache exceeds this, oldest already-seen files are deleted.
        // 25 × ~150 KB = ~4 MB upper bound. See maybeRotateDaily().
        const val DAILY_DISK_MAX = 25
    }
}
