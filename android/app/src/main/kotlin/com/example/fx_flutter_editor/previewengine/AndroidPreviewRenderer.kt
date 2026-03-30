package com.example.fx_flutter_editor.previewengine

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Looper
import android.widget.ImageView

class AndroidPreviewRenderer {
    fun createView(context: Context): PreviewGlSurfaceView = PreviewGlSurfaceView(context)
}

class PreviewGlSurfaceView(
    context: Context,
) : ImageView(context) {
    private var activeBitmap: Bitmap? = null

    init {
        setBackgroundColor(Color.BLACK)
        scaleType = ImageView.ScaleType.FIT_CENTER
        adjustViewBounds = false
    }

    fun submitFrame(
        bitmap: Bitmap?,
        contentWidth: Int,
        contentHeight: Int,
        fitMode: PreviewContentFitMode = PreviewContentFitMode.CONTAIN,
    ) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            applyFrame(bitmap, fitMode)
        } else {
            post { applyFrame(bitmap, fitMode) }
        }
    }

    fun clearFrame() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            clearActiveFrame()
        } else {
            post(::clearActiveFrame)
        }
    }

    fun dispose() {
        clearFrame()
    }

    private fun applyFrame(
        bitmap: Bitmap?,
        fitMode: PreviewContentFitMode,
    ) {
        scaleType =
            when (fitMode) {
                PreviewContentFitMode.COVER -> ImageView.ScaleType.CENTER_CROP
                PreviewContentFitMode.CONTAIN -> ImageView.ScaleType.FIT_CENTER
            }
        if (bitmap == null) {
            clearActiveFrame()
            return
        }
        if (activeBitmap !== bitmap) {
            val previousBitmap = activeBitmap
            activeBitmap = bitmap
            setImageBitmap(bitmap)
            if (previousBitmap != null && previousBitmap !== bitmap && !previousBitmap.isRecycled) {
                previousBitmap.recycle()
            }
        } else {
            setImageBitmap(bitmap)
        }
    }

    private fun clearActiveFrame() {
        val previousBitmap = activeBitmap
        activeBitmap = null
        setImageDrawable(null)
        if (previousBitmap != null && !previousBitmap.isRecycled) {
            previousBitmap.recycle()
        }
    }
}
