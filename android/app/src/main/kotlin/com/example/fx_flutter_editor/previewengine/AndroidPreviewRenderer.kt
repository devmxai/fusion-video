package com.example.fx_flutter_editor.previewengine

import android.content.Context
import android.graphics.Bitmap
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.GLSurfaceView
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.min

class AndroidPreviewRenderer {
    fun createView(context: Context): PreviewGlSurfaceView = PreviewGlSurfaceView(context)
}

class PreviewGlSurfaceView(
    context: Context,
) : GLSurfaceView(context) {
    private val bitmapRenderer = BitmapSurfaceRenderer()

    init {
        setEGLContextClientVersion(2)
        preserveEGLContextOnPause = true
        setRenderer(bitmapRenderer)
        renderMode = RENDERMODE_WHEN_DIRTY
    }

    fun submitFrame(
        bitmap: Bitmap?,
        contentWidth: Int,
        contentHeight: Int,
    ) {
        bitmapRenderer.submitFrame(bitmap, contentWidth, contentHeight)
        requestRender()
    }

    fun clearFrame() {
        bitmapRenderer.clearFrame()
        requestRender()
    }

    fun dispose() {
        queueEvent {
            bitmapRenderer.release()
        }
        onPause()
    }
}

private data class PendingBitmapFrame(
    val bitmap: Bitmap?,
    val contentWidth: Int,
    val contentHeight: Int,
)

private class BitmapSurfaceRenderer : GLSurfaceView.Renderer {
    private val positionBuffer =
        ByteBuffer.allocateDirect(8 * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
    private val textureBuffer =
        ByteBuffer.allocateDirect(8 * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply {
                put(
                    floatArrayOf(
                        0f,
                        1f,
                        1f,
                        1f,
                        0f,
                        0f,
                        1f,
                        0f,
                    ),
                )
                position(0)
            }

    private val frameLock = Any()
    private var pendingFrame: PendingBitmapFrame? = null
    private var activeContentWidth: Int = 0
    private var activeContentHeight: Int = 0
    private var needsTextureUpload: Boolean = false
    private var viewportWidth: Int = 0
    private var viewportHeight: Int = 0
    private var programHandle: Int = 0
    private var textureHandle: Int = 0
    private var positionHandle: Int = 0
    private var texCoordHandle: Int = 0
    private var samplerHandle: Int = 0
    private var textureId: Int = 0

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        programHandle = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionHandle = GLES20.glGetAttribLocation(programHandle, "aPosition")
        texCoordHandle = GLES20.glGetAttribLocation(programHandle, "aTexCoord")
        samplerHandle = GLES20.glGetUniformLocation(programHandle, "uTexture")
        textureId = createTexture()
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        viewportWidth = width
        viewportHeight = height
        GLES20.glViewport(0, 0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        var nextFrame: PendingBitmapFrame? = null
        synchronized(frameLock) {
            if (pendingFrame != null) {
                nextFrame = pendingFrame
                pendingFrame = null
            }
        }

        if (nextFrame != null) {
            val bitmap = nextFrame?.bitmap
            activeContentWidth = nextFrame?.contentWidth ?: bitmap?.width ?: 0
            activeContentHeight = nextFrame?.contentHeight ?: bitmap?.height ?: 0
            needsTextureUpload = bitmap != null
            if (bitmap == null) {
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
                val emptyPixel = ByteBuffer.allocateDirect(4)
                GLES20.glTexImage2D(
                    GLES20.GL_TEXTURE_2D,
                    0,
                    GLES20.GL_RGBA,
                    1,
                    1,
                    0,
                    GLES20.GL_RGBA,
                    GLES20.GL_UNSIGNED_BYTE,
                    emptyPixel,
                )
            } else {
                uploadBitmap(bitmap)
            }
        }

        if (textureId == 0 || activeContentWidth <= 0 || activeContentHeight <= 0) {
            return
        }

        updateVertexBuffer()
        positionBuffer.position(0)
        textureBuffer.position(0)

        GLES20.glUseProgram(programHandle)
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glEnableVertexAttribArray(texCoordHandle)
        GLES20.glVertexAttribPointer(positionHandle, 2, GLES20.GL_FLOAT, false, 0, positionBuffer)
        GLES20.glVertexAttribPointer(texCoordHandle, 2, GLES20.GL_FLOAT, false, 0, textureBuffer)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glUniform1i(samplerHandle, 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(positionHandle)
        GLES20.glDisableVertexAttribArray(texCoordHandle)
    }

    fun submitFrame(bitmap: Bitmap?, contentWidth: Int, contentHeight: Int) {
        synchronized(frameLock) {
            pendingFrame = PendingBitmapFrame(bitmap = bitmap, contentWidth = contentWidth, contentHeight = contentHeight)
        }
    }

    fun clearFrame() {
        submitFrame(bitmap = null, contentWidth = 0, contentHeight = 0)
    }

    fun release() {
        if (textureId != 0) {
            GLES20.glDeleteTextures(1, intArrayOf(textureId), 0)
            textureId = 0
        }
        if (programHandle != 0) {
            GLES20.glDeleteProgram(programHandle)
            programHandle = 0
        }
    }

    private fun uploadBitmap(bitmap: Bitmap) {
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        needsTextureUpload = false
    }

    private fun updateVertexBuffer() {
        if (viewportWidth <= 0 || viewportHeight <= 0 || activeContentWidth <= 0 || activeContentHeight <= 0) {
            positionBuffer.clear()
            positionBuffer.put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
            positionBuffer.position(0)
            return
        }
        val contentAspect = activeContentWidth.toFloat() / activeContentHeight.toFloat()
        val viewportAspect = viewportWidth.toFloat() / viewportHeight.toFloat()
        val scaleX: Float
        val scaleY: Float
        if (contentAspect > viewportAspect) {
            scaleX = 1f
            scaleY = viewportAspect / contentAspect
        } else {
            scaleX = min(1f, contentAspect / viewportAspect)
            scaleY = 1f
        }
        positionBuffer.clear()
        positionBuffer.put(
            floatArrayOf(
                -scaleX,
                -scaleY,
                scaleX,
                -scaleY,
                -scaleX,
                scaleY,
                scaleX,
                scaleY,
            ),
        )
        positionBuffer.position(0)
    }

    private fun createTexture(): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textures[0])
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        return textures[0]
    }

    private fun createProgram(vertexShaderSource: String, fragmentShaderSource: String): Int {
        val vertexShader = compileShader(GLES20.GL_VERTEX_SHADER, vertexShaderSource)
        val fragmentShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentShaderSource)
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)
        return program
    }

    private fun compileShader(type: Int, shaderSource: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, shaderSource)
        GLES20.glCompileShader(shader)
        return shader
    }

    companion object {
        private const val VERTEX_SHADER =
            """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            void main() {
              gl_Position = aPosition;
              vTexCoord = aTexCoord;
            }
            """

        private const val FRAGMENT_SHADER =
            """
            precision mediump float;
            varying vec2 vTexCoord;
            uniform sampler2D uTexture;
            void main() {
              gl_FragColor = texture2D(uTexture, vTexCoord);
            }
            """
    }
}
