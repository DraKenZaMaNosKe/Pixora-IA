package com.orbix.pixora.renderers

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import java.util.Calendar
import kotlin.math.sin

/**
 * Renders the Pixora Friends mascot (chibi boy + purple dragon) over the
 * Pixora Island background. The mascot has 4 animation states that cycle
 * automatically based on the time of day:
 *
 *   06–11h → idle  (waking up, blinking)
 *   11–17h → walk  (wandering the beach)
 *   17–20h → eat   (diamond snack)
 *   20–06h → sleep (curled up)
 *
 * Each state is a folder of sequential PNG frames under assets/pixora_island/:
 *   pixora_island/idle/frame_000.png … frame_NNN.png
 *   pixora_island/walk/frame_000.png …
 *   pixora_island/eat/frame_000.png …
 *   pixora_island/sleep/frame_000.png …
 *
 * Frames are expected to have alpha (chroma-keyed green screen).
 */
class PixoraFriendsRenderer(private val context: Context) {

    enum class State(val folder: String) {
        IDLE("pixora_island/idle"),
        WALK("pixora_island/walk"),
        EAT("pixora_island/eat"),
        SLEEP("pixora_island/sleep"),
    }

    var surfaceWidth = 0
    var surfaceHeight = 0

    /** Mascot horizontal position (center of the sprite, in px). */
    var mascotX = 0f

    /** Scale applied to the sprite. Tune per asset dimensions. */
    var scale = 1.0f

    /** Follow wallpaper x-offset passed from WallpaperService.onOffsetsChanged. */
    var offsetX = 0f

    /** Current state. Change via [setState] to reset the frame counter. */
    var currentState: State = State.IDLE
        private set

    /** Whether to auto-switch state based on local clock. */
    var autoStateByTime: Boolean = true

    private val spriteCache = mutableMapOf<State, List<Bitmap>>()
    private var frameIndex = 0
    private var frameTimer = 0

    // Walk motion: slow pacing back and forth across the lower-center of the screen.
    private var walkPhase = 0f

    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)

    // ── Public API ────────────────────────────────────────────────

    fun setState(state: State) {
        if (state == currentState) return
        currentState = state
        frameIndex = 0
        frameTimer = 0
    }

    /** Preload all four states into memory. Safe to call multiple times. */
    fun preloadAll() {
        for (s in State.values()) loadState(s)
    }

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return

        if (autoStateByTime) setState(stateForCurrentHour())

        val sprites = spriteCache[currentState] ?: run {
            loadState(currentState)
            spriteCache[currentState] ?: return
        }
        if (sprites.isEmpty()) return

        // Frame advance — render loop is ~60fps. Keeping framesPerTick low
        // makes playback closer to the source GIF (~24fps) so individual frame
        // transitions aren't visible. Sleep is slower on purpose but still fluid.
        val framesPerTick = when (currentState) {
            State.IDLE -> 2
            State.WALK -> 2
            State.EAT -> 2
            State.SLEEP -> 3
        }
        frameTimer++
        if (frameTimer >= framesPerTick) {
            frameTimer = 0
            frameIndex = (frameIndex + 1) % sprites.size
        }

        val sprite = sprites[frameIndex % sprites.size]
        if (sprite.isRecycled) return

        val w = sprite.width * scale
        val h = sprite.height * scale

        // Position: center horizontally, anchored to lower third (beach line).
        val anchorY = surfaceHeight * 0.72f
        val baseX = surfaceWidth * 0.5f

        val drawX = when (currentState) {
            State.WALK -> {
                // Slow horizontal pacing across the middle 50% of the screen.
                walkPhase += 0.008f
                val range = surfaceWidth * 0.25f
                baseX + sin(walkPhase.toDouble()).toFloat() * range - w / 2f
            }
            else -> baseX - w / 2f
        }
        val drawY = anchorY - h

        // Parallax with wallpaper offset so it feels anchored to the scene.
        val parallaxX = (offsetX - 0.5f) * surfaceWidth * 0.15f

        canvas.save()
        canvas.translate(drawX - parallaxX, drawY)
        canvas.scale(scale, scale)
        canvas.drawBitmap(sprite, 0f, 0f, paint)
        canvas.restore()
    }

    fun release() {
        for (frames in spriteCache.values) {
            for (b in frames) if (!b.isRecycled) b.recycle()
        }
        spriteCache.clear()
    }

    // ── Internal ──────────────────────────────────────────────────

    private fun loadState(state: State) {
        if (spriteCache.containsKey(state)) return
        val folder = state.folder
        try {
            val cacheDir = java.io.File(context.filesDir, "sprites/$folder")
            val fromFiles = cacheDir.isDirectory
            val fileList = if (fromFiles) {
                cacheDir.listFiles()
                    ?.filter { it.name.endsWith(".png") }
                    ?.sorted()
                    ?.map { it.name }
                    ?: emptyList()
            } else {
                context.assets.list(folder)
                    ?.filter { it.endsWith(".png") }
                    ?.sorted()
                    ?: emptyList()
            }
            if (fileList.isEmpty()) {
                android.util.Log.w("PixoraFriends", "No frames for state $state at $folder")
                spriteCache[state] = emptyList()
                return
            }
            val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
            val bitmaps = fileList.mapNotNull { name ->
                if (fromFiles) {
                    BitmapFactory.decodeFile("${cacheDir.absolutePath}/$name", opts)
                } else {
                    context.assets.open("$folder/$name").use {
                        BitmapFactory.decodeStream(it, null, opts)
                    }
                }
            }
            spriteCache[state] = bitmaps
            android.util.Log.d(
                "PixoraFriends",
                "Loaded ${bitmaps.size} frames for $state from " +
                    if (fromFiles) "files" else "assets"
            )
        } catch (e: Exception) {
            android.util.Log.e("PixoraFriends", "Failed to load $state: $e")
            spriteCache[state] = emptyList()
        }
    }

    /**
     * Pick a state so the scene feels alive across the day. WALK is currently
     * excluded from the rotation while it's being polished — the sprites stay
     * bundled so we can re-enable it without re-uploading anything.
     *
     * Cycle: IDLE → EAT → SLEEP, 75s per slot (3m45s full cycle). Night hours
     * (22-06) get an extra SLEEP slot so the mascot dozes more often then.
     */
    private fun stateForCurrentHour(): State {
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        val isNight = hour >= 22 || hour < 6

        val seconds = System.currentTimeMillis() / 1000L
        val slot = ((seconds / 75L) % if (isNight) 4 else 3).toInt()
        return when (slot) {
            0 -> State.IDLE
            1 -> State.EAT
            2 -> State.SLEEP
            3 -> State.SLEEP  // extra night slot
            else -> State.SLEEP
        }
    }
}
