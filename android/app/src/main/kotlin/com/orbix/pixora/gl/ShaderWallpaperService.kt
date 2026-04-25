package com.orbix.pixora.gl

import android.content.Context
import android.content.SharedPreferences
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.os.Handler
import android.os.Looper
import android.service.wallpaper.WallpaperService
import android.util.Log
import android.view.SurfaceHolder
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Dedicated OpenGL ES 2.0 WallpaperService for shader-based live wallpapers.
 * Never uses Canvas — 100% GL rendering. No Surface conflicts.
 *
 * Time wraps every 600 seconds to prevent float precision loss.
 */
class ShaderWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = ShaderEngine()

    inner class ShaderEngine : Engine() {
        private val TAG = "ShaderWP"
        private val TIME_WRAP = 600.0f
        private val FRAME_DELAY = 33L // ~30fps
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
        private var startTime = System.nanoTime()
        private var width = 0
        private var height = 0
        private var running = false
        private var glReady = false
        private var currentShader = ""

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
            registerPrefsListener()
        }

        override fun onSurfaceCreated(holder: SurfaceHolder?) {
            super.onSurfaceCreated(holder)
            Log.d(TAG, "Surface created")
        }

        override fun onSurfaceChanged(holder: SurfaceHolder?, format: Int, w: Int, h: Int) {
            super.onSurfaceChanged(holder, format, w, h)
            val orientationChanged = width != w || height != h
            width = w
            height = h
            Log.d(TAG, "Surface changed: ${w}x${h} (orientation=${if (w > h) "LANDSCAPE" else "PORTRAIT"})")

            if (!glReady) {
                initGL(holder!!)
                loadCurrentShader()
            } else {
                // Update viewport on rotation/resize
                EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
                GLES20.glViewport(0, 0, w, h)
                if (orientationChanged) {
                    Log.d(TAG, "Viewport updated: ${w}x${h}")
                }
            }
        }

        override fun onVisibilityChanged(visible: Boolean) {
            Log.d(TAG, "visibility=$visible glReady=$glReady")
            if (visible) {
                if (glReady) {
                    running = true
                    handler.post(renderRunnable)
                }
            } else {
                running = false
                handler.removeCallbacks(renderRunnable)
            }
        }

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
            super.onDestroy()
        }

        // ── Prefs listener for shader changes ──────────────────────
        private fun registerPrefsListener() {
            val prefs = applicationContext.getSharedPreferences("pixora_shader", Context.MODE_PRIVATE)
            prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                if (key == "shader_name") {
                    Log.d(TAG, "Shader changed, reloading")
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
            val name = prefs.getString("shader_name", "aurora_borealis") ?: "aurora_borealis"
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
                    Log.e(TAG, "eglChooseConfig failed: no valid configs")
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
                Log.d(TAG, "GL ready: ${width}x${height}")
            } catch (e: Exception) {
                Log.e(TAG, "initGL failed: ${e.message}")
            }
        }

        private fun releaseGL() {
            glReady = false
            if (program != 0) { GLES20.glDeleteProgram(program); program = 0 }
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
            Log.d(TAG, "GL released")
        }

        // ── Shader compilation ─────────────────────────────────────
        private fun loadShader(name: String) {
            if (!glReady) return
            try {
                EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

                // filesDir-first lookup: shaders are downloaded by ShaderDownloadService
                // and cached at filesDir/shaders/<name>.glsl. Asset fallback kept for
                // safety only — after v1.6.0 the APK no longer ships any .glsl.
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
                currentShader = name
                startTime = System.nanoTime() // Reset time on shader change

                Log.d(TAG, "Shader loaded: $name (uTime=$uTime, uRes=$uResolution)")

                // Start rendering if not already
                if (!running) {
                    running = true
                    handler.post(renderRunnable)
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadShader($name) failed: ${e.message}")
            }
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

                GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
                GLES20.glUseProgram(program)

                if (uTime >= 0) GLES20.glUniform1f(uTime, time)
                if (uResolution >= 0) GLES20.glUniform2f(uResolution, width.toFloat(), height.toFloat())

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
