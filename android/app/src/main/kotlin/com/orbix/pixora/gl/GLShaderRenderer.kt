package com.orbix.pixora.gl

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.opengl.GLUtils
import android.util.Log
import android.view.SurfaceHolder
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * OpenGL ES 2.0 shader renderer for real-time wallpapers.
 * Renders fullscreen fragment shaders with time-safe uniforms.
 *
 * Time wraps every 600 seconds (10 minutes) to prevent float precision loss.
 * All shaders should use periodic functions (sin, cos, fract) that handle this naturally.
 */
class GLShaderRenderer(private val context: Context) {

    companion object {
        private const val TAG = "GLShaderRenderer"
        private const val TIME_WRAP = 600.0f // Wrap time every 10 minutes

        // Fullscreen quad vertices (2 triangles)
        private val QUAD_VERTICES = floatArrayOf(
            -1f, -1f,
             1f, -1f,
            -1f,  1f,
             1f,  1f,
        )

        // Simple vertex shader — just passes position
        private const val VERTEX_SHADER = """
            attribute vec2 aPosition;
            void main() {
                gl_Position = vec4(aPosition, 0.0, 1.0);
            }
        """
    }

    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var program = 0
    private var vertexBuffer: FloatBuffer? = null

    // Uniforms
    private var uTime = -1
    private var uResolution = -1
    private var uTex = -1            // optional sampler2D for shaders that sample a background

    // Optional background texture (TEXTURE0)
    private var bgTextureId = 0

    // State
    private var startTime = System.nanoTime()
    private var width = 0
    private var height = 0
    private var frameCount = 0L
    var isInitialized = false
        private set

    /**
     * Initialize EGL context on the given SurfaceHolder.
     * IMPORTANT: Canvas must NOT have been used on this Surface before calling init.
     * If Canvas was used, call release() first and recreate with a fresh Surface.
     */
    fun init(holder: SurfaceHolder, surfaceWidth: Int, surfaceHeight: Int): Boolean {
        // Release any previous GL state
        release()
        width = surfaceWidth
        height = surfaceHeight

        try {
            // 1. Get display
            eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (eglDisplay == EGL14.EGL_NO_DISPLAY) {
                Log.e(TAG, "eglGetDisplay failed")
                return false
            }

            val version = IntArray(2)
            EGL14.eglInitialize(eglDisplay, version, 0, version, 1)

            // 2. Choose config
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

            if (numConfigs[0] == 0) {
                Log.e(TAG, "No EGL configs found")
                return false
            }

            // 3. Create context (ES 2.0)
            val contextAttribs = intArrayOf(
                EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
                EGL14.EGL_NONE
            )
            eglContext = EGL14.eglCreateContext(
                eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, contextAttribs, 0
            )

            // 4. Create window surface
            val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
            eglSurface = EGL14.eglCreateWindowSurface(
                eglDisplay, configs[0], holder.surface, surfaceAttribs, 0
            )

            // 5. Make current
            EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

            // 6. Setup vertex buffer
            vertexBuffer = ByteBuffer.allocateDirect(QUAD_VERTICES.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .put(QUAD_VERTICES)
            vertexBuffer?.position(0)

            GLES20.glViewport(0, 0, width, height)

            isInitialized = true
            Log.d(TAG, "GL initialized: ${width}x${height}, ES ${version[0]}.${version[1]}")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "GL init failed: ${e.message}")
            return false
        }
    }

    /**
     * Load and compile a fragment shader.
     */
    fun loadShader(fragmentShaderSource: String): Boolean {
        try {
            // Make sure context is current
            EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

            // Compile vertex shader
            val vertShader = compileShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
            if (vertShader == 0) return false

            // Compile fragment shader
            val fragShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentShaderSource)
            if (fragShader == 0) return false

            // Link program
            if (program != 0) GLES20.glDeleteProgram(program)
            program = GLES20.glCreateProgram()
            GLES20.glAttachShader(program, vertShader)
            GLES20.glAttachShader(program, fragShader)
            GLES20.glLinkProgram(program)

            val linkStatus = IntArray(1)
            GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linkStatus, 0)
            if (linkStatus[0] == 0) {
                Log.e(TAG, "Link failed: ${GLES20.glGetProgramInfoLog(program)}")
                GLES20.glDeleteProgram(program)
                program = 0
                return false
            }

            // Cleanup individual shaders
            GLES20.glDeleteShader(vertShader)
            GLES20.glDeleteShader(fragShader)

            // Get uniform locations
            uTime = GLES20.glGetUniformLocation(program, "uTime")
            uResolution = GLES20.glGetUniformLocation(program, "uResolution")
            uTex = GLES20.glGetUniformLocation(program, "uTex")

            Log.d(TAG, "Shader compiled OK (uTime=$uTime, uRes=$uResolution, uTex=$uTex)")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "loadShader failed: ${e.message}")
            return false
        }
    }

    /**
     * Load shader from filesDir/<assetPath> first (downloaded by
     * ShaderDownloadService), falling back to bundled APK assets only as
     * a safety net — post-v1.6.0 there are no shaders bundled.
     */
    fun loadShaderFromAsset(assetPath: String): Boolean {
        return try {
            val cached = java.io.File(context.filesDir, assetPath)
            val source = if (cached.isFile) {
                cached.readText()
            } else {
                context.assets.open(assetPath).bufferedReader().use { it.readText() }
            }
            loadShader(source)
        } catch (e: Exception) {
            Log.e(TAG, "loadShaderFromAsset($assetPath) failed: ${e.message}")
            false
        }
    }

    /**
     * Load a background texture from a Bitmap. Call AFTER init() and AFTER loadShader().
     * Bound to TEXTURE0 and exposed to the shader as `uniform sampler2D uTex;`.
     * Shaders that don't declare uTex are unaffected.
     */
    fun setBackgroundTexture(bitmap: Bitmap): Boolean {
        if (!isInitialized) return false
        try {
            EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
            // Drop previous texture if present
            if (bgTextureId != 0) {
                val ids = intArrayOf(bgTextureId)
                GLES20.glDeleteTextures(1, ids, 0)
                bgTextureId = 0
            }
            val ids = IntArray(1)
            GLES20.glGenTextures(1, ids, 0)
            bgTextureId = ids[0]
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, bgTextureId)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
            Log.d(TAG, "BG texture uploaded: ${bitmap.width}x${bitmap.height} -> tex=$bgTextureId")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "setBackgroundTexture failed: ${e.message}")
            return false
        }
    }

    /**
     * Convenience: load a background texture from an asset path.
     * Decodes the bitmap, uploads to GL, then recycles the bitmap.
     */
    fun setBackgroundTextureFromAsset(assetPath: String): Boolean {
        return try {
            val bmp = context.assets.open(assetPath).use { input ->
                BitmapFactory.decodeStream(input)
            } ?: return false
            val ok = setBackgroundTexture(bmp)
            bmp.recycle()
            ok
        } catch (e: Exception) {
            Log.e(TAG, "setBackgroundTextureFromAsset($assetPath) failed: ${e.message}")
            false
        }
    }

    /**
     * Render one frame. Call this from your render loop.
     */
    fun drawFrame() {
        if (!isInitialized || program == 0) return

        try {
            EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

            // Time: wraps every TIME_WRAP seconds to prevent float precision loss
            val elapsed = (System.nanoTime() - startTime) / 1_000_000_000.0f
            val time = elapsed % TIME_WRAP

            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
            GLES20.glUseProgram(program)

            // Set uniforms
            if (uTime >= 0) GLES20.glUniform1f(uTime, time)
            if (uResolution >= 0) GLES20.glUniform2f(uResolution, width.toFloat(), height.toFloat())

            // Bind background texture to TEXTURE0 if shader requests uTex
            if (uTex >= 0 && bgTextureId != 0) {
                GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, bgTextureId)
                GLES20.glUniform1i(uTex, 0)
            }

            // Draw fullscreen quad
            val posAttrib = GLES20.glGetAttribLocation(program, "aPosition")
            GLES20.glEnableVertexAttribArray(posAttrib)
            GLES20.glVertexAttribPointer(posAttrib, 2, GLES20.GL_FLOAT, false, 0, vertexBuffer)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GLES20.glDisableVertexAttribArray(posAttrib)

            frameCount++
            if (frameCount % 90 == 0L) Log.d(TAG, "frame #$frameCount time=${time}")
            val swapOk = EGL14.eglSwapBuffers(eglDisplay, eglSurface)
            val glErr = GLES20.glGetError()
            if (!swapOk || glErr != GLES20.GL_NO_ERROR) {
                Log.e(TAG, "drawFrame: swapOk=$swapOk glError=$glErr eglError=${EGL14.eglGetError()}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "drawFrame error: ${e.message}")
        }
    }

    /**
     * Update surface dimensions (e.g., on rotation).
     */
    fun onSurfaceChanged(newWidth: Int, newHeight: Int) {
        width = newWidth
        height = newHeight
        if (isInitialized) {
            EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
            GLES20.glViewport(0, 0, width, height)
        }
    }

    /**
     * Release all GL resources.
     */
    fun release() {
        if (bgTextureId != 0) {
            try {
                EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
                val ids = intArrayOf(bgTextureId)
                GLES20.glDeleteTextures(1, ids, 0)
            } catch (_: Exception) {}
            bgTextureId = 0
        }
        if (program != 0) {
            GLES20.glDeleteProgram(program)
            program = 0
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
        vertexBuffer = null
        isInitialized = false
        Log.d(TAG, "GL released")
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)

        val compiled = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
        if (compiled[0] == 0) {
            val typeName = if (type == GLES20.GL_VERTEX_SHADER) "vertex" else "fragment"
            Log.e(TAG, "$typeName shader compile error: ${GLES20.glGetShaderInfoLog(shader)}")
            GLES20.glDeleteShader(shader)
            return 0
        }
        return shader
    }
}
