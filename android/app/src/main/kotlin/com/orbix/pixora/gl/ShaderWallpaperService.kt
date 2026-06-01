package com.orbix.pixora.gl

import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.opengl.GLUtils
import android.os.Handler
import android.os.Looper
import android.service.wallpaper.WallpaperService
import android.util.Log
import android.view.MotionEvent
import android.view.SurfaceHolder
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Dedicated OpenGL ES 2.0 WallpaperService for shader-based live wallpapers.
 * Never uses Canvas — 100% GL rendering. No Surface conflicts.
 *
 * Time wraps every 60 seconds — keeps sin/cos arguments small enough that even
 * mediump GPUs render without banding. All shaders MUST also wrap their own
 * sin/cos args with mod(x, 6.2831853) for the same reason.
 */
class ShaderWallpaperService : WallpaperService() {

    private val activeEngines = mutableListOf<ShaderEngine>()

    override fun onCreateEngine(): Engine {
        val e = ShaderEngine()
        activeEngines.add(e)
        return e
    }

    /** Forward Android's memory-pressure signal to every active engine so they
     *  can drop their largest GPU allocation (skin texture). The texture will
     *  re-upload on next loadShader — cheap recovery, big win under pressure. */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        for (e in activeEngines.toList()) e.trimMemory(level)
    }

    inner class ShaderEngine : Engine() {
        private val TAG = "ShaderWP"
        private val TIME_WRAP = 60.0f
        private val FRAME_DELAY = 50L // ~20fps — good citizen on slow devices / heavy compositor load
        private val QUAD = floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)
        private val VERT_SRC = "attribute vec2 aPosition; void main() { gl_Position = vec4(aPosition, 0.0, 1.0); }"

        private val handler = Handler(Looper.getMainLooper())
        private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
        private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
        private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
        private var program = 0
        private var vertBuf: FloatBuffer? = null
        private var uTime = -1
        private var uResolution = -1
        private var uMouse = -1
        private var uPressed = -1
        private var uClockSec = -1
        private var uSkin = -1
        private var uHasSkin = -1
        // Optional companion texture (<name>.png alongside <name>.glsl). When
        // present, exposed to shader as sampler2D uSkin + uHasSkin=1. Lets
        // shaders composite a static photo (e.g. lava lamp body) with shader-
        // rendered animation (the blobs inside the tube).
        private var skinTextureId = 0
        private var skinLoadedFor = ""
        private var startTime = System.nanoTime()
        private var width = 0
        private var height = 0
        private var running = false
        private var glReady = false
        private var currentShader = ""

        // Touch state — mouseX/Y in [0..1] normalized, pressedTarget toggled by
        // events, pressed smoothed toward target each frame so finger lift fades
        // out instead of snapping.
        private var mouseX = 0.5f
        private var mouseY = 0.5f
        private var pressed = 0.0f
        private var pressedTarget = 0.0f

        private var prefsListener: SharedPreferences.OnSharedPreferenceChangeListener? = null

        private val renderRunnable = object : Runnable {
            override fun run() {
                if (running && glReady) {
                    drawFrame()
                    handler.postDelayed(this, FRAME_DELAY)
                }
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder?) {
            super.onCreate(surfaceHolder)
            Log.d(TAG, "Engine created")
            // Most launchers consume taps on app icons but pass through empty-area
            // touches to the wallpaper. Touch always works in the wallpaper preview.
            setTouchEventsEnabled(true)
            registerPrefsListener()
        }

        override fun onSurfaceCreated(holder: SurfaceHolder?) {
            super.onSurfaceCreated(holder)
        }

        override fun onSurfaceChanged(holder: SurfaceHolder?, format: Int, w: Int, h: Int) {
            super.onSurfaceChanged(holder, format, w, h)
            width = w
            height = h
            Log.d(TAG, "Surface ${w}x${h} ${if (w > h) "LANDSCAPE" else "PORTRAIT"}")

            // Always tear down + re-init on surface change. Samsung One UI
            // doesn't reliably fire onSurfaceDestroyed when transitioning from
            // picker preview to applied wallpaper — the GL state ends up
            // pointing at the dead picker surface and textures (sampler2D)
            // return black when sampled, even though the program/uniforms
            // pass through. Re-init is ~200 ms and only happens on real
            // surface changes (rotation, picker→applied), so the cost is
            // negligible and the correctness payoff is huge.
            if (glReady) releaseGL()
            initGL(holder!!)
            loadCurrentShader()
        }

        override fun onVisibilityChanged(visible: Boolean) {
            if (visible) {
                handler.removeCallbacks(zombieReleaseRunnable)
                if (!glReady) {
                    // GL was released by zombie cleanup or trimMemory. Re-init
                    // now that we're visible again so we can actually render.
                    surfaceHolder?.let {
                        try { initGL(it); loadCurrentShader() }
                        catch (e: Exception) { Log.w(TAG, "re-init on visible: ${e.message}") }
                    }
                }
                if (glReady) {
                    running = true
                    handler.post(renderRunnable)
                }
            } else {
                running = false
                handler.removeCallbacks(renderRunnable)
                // If we're a preview engine and the APPLIED wallpaper is already
                // active in this process, we're a zombie — the user applied a
                // shader and went home, leaving the picker in recents. Release
                // our GPU resources after a short grace period (in case the user
                // briefly toggles back). Saves ~10-20 MB GPU + halves CPU.
                if (isPreview && hasAppliedEngine()) {
                    handler.postDelayed(zombieReleaseRunnable, 2000)
                }
            }
        }

        private val zombieReleaseRunnable = Runnable {
            Log.d(TAG, "zombie preview engine — releasing GL to free GPU")
            releaseGL()
        }

        private fun hasAppliedEngine(): Boolean =
            activeEngines.any { it !== this && !it.isPreview }

        override fun onSurfaceDestroyed(holder: SurfaceHolder?) {
            running = false
            handler.removeCallbacks(renderRunnable)
            releaseGL()
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            running = false
            handler.removeCallbacks(renderRunnable)
            releaseGL()
            unregisterPrefsListener()
            activeEngines.remove(this)
            super.onDestroy()
        }

        // ── Touch ──────────────────────────────────────────────────
        override fun onTouchEvent(event: MotionEvent) {
            super.onTouchEvent(event)
            if (width <= 0 || height <= 0) return
            // Normalize to [0..1]. Y is flipped because Android Y=0 is top while
            // shaders use gl_FragCoord with Y=0 at bottom.
            mouseX = (event.x / width.toFloat()).coerceIn(0f, 1f)
            mouseY = (1f - event.y / height.toFloat()).coerceIn(0f, 1f)
            when (event.action) {
                MotionEvent.ACTION_DOWN,
                MotionEvent.ACTION_MOVE -> pressedTarget = 1.0f
                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_CANCEL -> pressedTarget = 0.0f
            }
        }

        // ── Prefs listener for shader changes ──────────────────────
        private fun registerPrefsListener() {
            val prefs = applicationContext.getSharedPreferences("pixora_shader", Context.MODE_PRIVATE)
            prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                if (key == "shader_name") {
                    handler.post { loadCurrentShader() }
                }
            }
            prefs.registerOnSharedPreferenceChangeListener(prefsListener)
        }

        private fun unregisterPrefsListener() {
            prefsListener?.let {
                applicationContext.getSharedPreferences("pixora_shader", Context.MODE_PRIVATE)
                    .unregisterOnSharedPreferenceChangeListener(it)
            }
            prefsListener = null
        }

        private fun loadCurrentShader() {
            val prefs = applicationContext.getSharedPreferences("pixora_shader", Context.MODE_PRIVATE)
            val name = prefs.getString("shader_name", "universe") ?: "universe"
            if (name != currentShader || program == 0) {
                loadShader(name)
            }
        }

        // ── EGL Setup ──────────────────────────────────────────────
        private fun initGL(holder: SurfaceHolder) {
            try {
                eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
                val version = IntArray(2)
                EGL14.eglInitialize(eglDisplay, version, 0, version, 1)

                val configAttribs = intArrayOf(
                    EGL14.EGL_RED_SIZE, 8,
                    EGL14.EGL_GREEN_SIZE, 8,
                    EGL14.EGL_BLUE_SIZE, 8,
                    EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                    EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
                    EGL14.EGL_NONE
                )
                val configs = arrayOfNulls<EGLConfig>(1)
                val numConfigs = IntArray(1)
                EGL14.eglChooseConfig(eglDisplay, configAttribs, 0, configs, 0, 1, numConfigs, 0)

                if (numConfigs[0] == 0 || configs[0] == null) {
                    Log.e(TAG, "eglChooseConfig failed")
                    return
                }
                val eglConfig = configs[0]!!

                val contextAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
                eglContext = EGL14.eglCreateContext(eglDisplay, eglConfig, EGL14.EGL_NO_CONTEXT, contextAttribs, 0)

                val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
                eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, eglConfig, holder.surface, surfaceAttribs, 0)

                EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

                vertBuf = ByteBuffer.allocateDirect(QUAD.size * 4)
                    .order(ByteOrder.nativeOrder()).asFloatBuffer().put(QUAD)
                vertBuf?.position(0)

                GLES20.glViewport(0, 0, width, height)
                glReady = true
                Log.d(TAG, "GL ready ${width}x${height}")
            } catch (e: Exception) {
                Log.e(TAG, "initGL failed: ${e.message}")
            }
        }

        /** Full teardown of GL state. Order matters: program/texture (GL objects
         *  need a current context), then unbind context, then destroy surface +
         *  context + display. Each EGL call is null-safe so partial init failures
         *  still clean up correctly. */
        private fun releaseGL() {
            glReady = false
            // Make context current so glDelete* succeed (no-op if already current).
            if (eglDisplay != EGL14.EGL_NO_DISPLAY && eglContext != EGL14.EGL_NO_CONTEXT
                && eglSurface != EGL14.EGL_NO_SURFACE) {
                try { EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext) } catch (_: Exception) {}
            }
            if (program != 0) { GLES20.glDeleteProgram(program); program = 0 }
            if (skinTextureId != 0) {
                GLES20.glDeleteTextures(1, intArrayOf(skinTextureId), 0)
                skinTextureId = 0
                skinLoadedFor = ""
            }
            // Unbind context BEFORE destroying it — prevents driver-side leaks
            // on Samsung/Mali where the GPU keeps the context buffer alive if
            // it's still marked current at destroy time.
            if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
                try {
                    EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE,
                        EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                } catch (_: Exception) {}
            }
            if (eglSurface != EGL14.EGL_NO_SURFACE) {
                EGL14.eglDestroySurface(eglDisplay, eglSurface)
                eglSurface = EGL14.EGL_NO_SURFACE
            }
            if (eglContext != EGL14.EGL_NO_CONTEXT) {
                EGL14.eglDestroyContext(eglDisplay, eglContext)
                eglContext = EGL14.EGL_NO_CONTEXT
            }
            if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglTerminate(eglDisplay)
                eglDisplay = EGL14.EGL_NO_DISPLAY
            }
            vertBuf = null
        }

        /** Called by the parent service's onTrimMemory. Drops the skin texture
         *  (largest GPU allocation) under memory pressure — it'll re-upload on
         *  next loadShader. Cheap visual hiccup, big memory win when SystemUI/SF
         *  are pressured during transitions. */
        fun trimMemory(level: Int) {
            if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW
                && skinTextureId != 0) {
                try {
                    if (eglDisplay != EGL14.EGL_NO_DISPLAY && eglContext != EGL14.EGL_NO_CONTEXT
                        && eglSurface != EGL14.EGL_NO_SURFACE) {
                        EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
                    }
                    GLES20.glDeleteTextures(1, intArrayOf(skinTextureId), 0)
                    skinTextureId = 0
                    skinLoadedFor = ""
                    Log.d(TAG, "trimMemory($level): released skin texture")
                } catch (e: Exception) {
                    Log.w(TAG, "trimMemory release failed: ${e.message}")
                }
            }
        }

        // ── Shader compilation ─────────────────────────────────────
        private fun loadShader(name: String) {
            if (!glReady) return
            try {
                EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

                // filesDir-first lookup: shaders are downloaded by ShaderDownloadService
                // and cached at filesDir/shaders/<name>.glsl. Asset fallback kept for
                // safety only — APK does not ship any .glsl since v1.6.0.
                val cached = java.io.File(applicationContext.filesDir, "shaders/$name.glsl")
                val source = if (cached.isFile) {
                    cached.readText()
                } else {
                    applicationContext.assets.open("shaders/$name.glsl").bufferedReader().readText()
                }

                val vert = compile(GLES20.GL_VERTEX_SHADER, VERT_SRC)
                val frag = compile(GLES20.GL_FRAGMENT_SHADER, source)
                if (vert == 0 || frag == 0) return

                if (program != 0) GLES20.glDeleteProgram(program)
                program = GLES20.glCreateProgram()
                GLES20.glAttachShader(program, vert)
                GLES20.glAttachShader(program, frag)
                GLES20.glLinkProgram(program)

                val status = IntArray(1)
                GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, status, 0)
                if (status[0] == 0) {
                    Log.e(TAG, "Link error: ${GLES20.glGetProgramInfoLog(program)}")
                    GLES20.glDeleteProgram(program); program = 0; return
                }

                GLES20.glDeleteShader(vert)
                GLES20.glDeleteShader(frag)

                uTime = GLES20.glGetUniformLocation(program, "uTime")
                uResolution = GLES20.glGetUniformLocation(program, "uResolution")
                uMouse = GLES20.glGetUniformLocation(program, "uMouse")
                uPressed = GLES20.glGetUniformLocation(program, "uPressed")
                uClockSec = GLES20.glGetUniformLocation(program, "uClockSec")
                uSkin = GLES20.glGetUniformLocation(program, "uSkin")
                uHasSkin = GLES20.glGetUniformLocation(program, "uHasSkin")
                currentShader = name
                startTime = System.nanoTime()

                // Optional companion texture: <name>.png alongside <name>.glsl.
                // Load fresh on shader change so each shader can have its own
                // skin (or none). loadSkinTexture handles delete-old-then-create.
                val skinFile = File(applicationContext.filesDir, "shaders/$name.png")
                if (skinFile.isFile) {
                    loadSkinTexture(skinFile)
                    skinLoadedFor = name
                } else if (skinTextureId != 0) {
                    // Previous shader had a skin, this one doesn't — clean up.
                    GLES20.glDeleteTextures(1, intArrayOf(skinTextureId), 0)
                    skinTextureId = 0
                    skinLoadedFor = ""
                }

                Log.d(TAG, "Shader loaded: $name (skin=${skinTextureId != 0})")

                if (!running) {
                    running = true
                    handler.post(renderRunnable)
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadShader($name): ${e.message}")
            }
        }

        /** Decode <name>.png from cache and upload as GL texture bound to TEXTURE0.
         *  Auto-downsamples textures wider than 720px to keep GPU memory low
         *  (1080x2340 = ~10MB → 720x1560 = ~4.5MB). Linear filtering hides the
         *  lower resolution at full screen — perceptually identical for lamp bodies.
         */
        private fun loadSkinTexture(file: File) {
            // First pass: bounds-only decode to read dimensions without allocating.
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, bounds)
            var sample = 1
            val maxDim = maxOf(bounds.outWidth, bounds.outHeight)
            while (maxDim / sample > 1560) sample *= 2
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            val bmp = BitmapFactory.decodeFile(file.absolutePath, opts)
            if (bmp == null) {
                Log.w(TAG, "skin decode failed: ${file.absolutePath}")
                return
            }
            // Drop old texture if any
            if (skinTextureId != 0) {
                GLES20.glDeleteTextures(1, intArrayOf(skinTextureId), 0)
                skinTextureId = 0
            }
            val ids = IntArray(1)
            GLES20.glGenTextures(1, ids, 0)
            skinTextureId = ids[0]
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, skinTextureId)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp, 0)
            Log.d(TAG, "skin uploaded: ${bmp.width}x${bmp.height} (sample=$sample) -> tex=$skinTextureId")
            bmp.recycle()
            // Hint to JVM: bitmap was big (decoded RGBA buffer ~4-10 MB). GC now
            // so the native buffer is freed before next allocation rather than
            // waiting for natural collection cycle.
            System.gc()
        }

        private fun compile(type: Int, src: String): Int {
            val s = GLES20.glCreateShader(type)
            GLES20.glShaderSource(s, src)
            GLES20.glCompileShader(s)
            val ok = IntArray(1)
            GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, ok, 0)
            if (ok[0] == 0) {
                Log.e(TAG, "Compile error: ${GLES20.glGetShaderInfoLog(s)}")
                GLES20.glDeleteShader(s); return 0
            }
            return s
        }

        // ── Render frame ───────────────────────────────────────────
        private fun drawFrame() {
            if (!glReady || program == 0) return
            try {
                EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

                val time = ((System.nanoTime() - startTime) / 1_000_000_000.0f) % TIME_WRAP
                // Smooth pressed toward target so finger lift fades out (~250ms).
                pressed += (pressedTarget - pressed) * 0.12f

                GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
                GLES20.glUseProgram(program)

                if (uTime >= 0) GLES20.glUniform1f(uTime, time)
                if (uResolution >= 0) GLES20.glUniform2f(uResolution, width.toFloat(), height.toFloat())
                if (uMouse >= 0) GLES20.glUniform2f(uMouse, mouseX, mouseY)
                if (uPressed >= 0) GLES20.glUniform1f(uPressed, pressed)
                // Bind companion skin texture (if loaded) to TEXTURE0 and tell
                // the shader via uHasSkin. Shaders that don't declare uSkin /
                // uHasSkin are unaffected (uniform locations stay -1).
                if (skinTextureId != 0 && uSkin >= 0) {
                    GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
                    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, skinTextureId)
                    GLES20.glUniform1i(uSkin, 0)
                }
                if (uHasSkin >= 0) GLES20.glUniform1f(uHasSkin, if (skinTextureId != 0) 1.0f else 0.0f)
                if (uClockSec >= 0) {
                    // Seconds since midnight in local time (fractional for smooth motion).
                    val cal = java.util.Calendar.getInstance()
                    val secOfDay = cal.get(java.util.Calendar.HOUR_OF_DAY) * 3600 +
                                   cal.get(java.util.Calendar.MINUTE) * 60 +
                                   cal.get(java.util.Calendar.SECOND) +
                                   cal.get(java.util.Calendar.MILLISECOND) / 1000.0f
                    GLES20.glUniform1f(uClockSec, secOfDay)
                }

                val pos = GLES20.glGetAttribLocation(program, "aPosition")
                GLES20.glEnableVertexAttribArray(pos)
                GLES20.glVertexAttribPointer(pos, 2, GLES20.GL_FLOAT, false, 0, vertBuf)
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                GLES20.glDisableVertexAttribArray(pos)

                EGL14.eglSwapBuffers(eglDisplay, eglSurface)
            } catch (e: Exception) {
                Log.e(TAG, "drawFrame: ${e.message}")
            }
        }
    }
}
