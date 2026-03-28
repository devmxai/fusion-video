package com.example.fx_flutter_editor

import android.graphics.BitmapFactory
import android.content.Context
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.os.Bundle
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "fusion_video/preview_surface",
                FusionPreviewViewFactory(),
            )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fusion_video/preview_session",
        ).setMethodCallHandler { call, result ->
            if (call.method != "updatePreview") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val args = call.arguments as? Map<*, *>
            val projectId = (args?.get("projectId") as? Number)?.toInt()
            val positionSeconds = (args?.get("positionSeconds") as? Number)?.toDouble()
            val isPlaying = args?.get("isPlaying") as? Boolean
            val sourcePath = args?.get("sourcePath") as? String
            val sourceKind = args?.get("sourceKind") as? String
            val sourceStartSeconds = (args?.get("sourceStartSeconds") as? Number)?.toDouble()
            val sourceEndSeconds = (args?.get("sourceEndSeconds") as? Number)?.toDouble()

            if (projectId == null || positionSeconds == null || isPlaying == null) {
                result.error("invalid_args", "Missing preview session arguments", null)
                return@setMethodCallHandler
            }

            FusionPreviewRegistry.update(
                projectId,
                sourcePath,
                sourceKind,
                sourceStartSeconds,
                sourceEndSeconds,
                positionSeconds,
                isPlaying,
            )
            result.success(null)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fusion_video/media_probe",
        ).setMethodCallHandler { call, result ->
            if (call.method != "probeMedia") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val args = call.arguments as? Map<*, *>
            val path = args?.get("path") as? String
            val kind = args?.get("kind") as? String

            if (path == null || kind == null) {
                result.error("invalid_args", "Missing probe arguments", null)
                return@setMethodCallHandler
            }

            result.success(FusionMediaProbe.probe(path, kind))
        }
    }
}

private object FusionMediaProbe {
    fun probe(path: String, kind: String): Map<String, Any>? {
        return when (kind) {
            "video" -> {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(path)
                    val durationMs =
                        retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                            ?.toDoubleOrNull() ?: 0.0
                    val width =
                        retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                            ?.toIntOrNull()
                    val height =
                        retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                            ?.toIntOrNull()
                    buildMap<String, Any> {
                        put("durationSeconds", durationMs / 1000.0)
                        if (width != null) put("width", width)
                        if (height != null) put("height", height)
                    }
                } finally {
                    retriever.release()
                }
            }

            "image" -> {
                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeFile(path, options)
                buildMap<String, Any> {
                    if (options.outWidth > 0) put("width", options.outWidth)
                    if (options.outHeight > 0) put("height", options.outHeight)
                }
            }

            else -> null
        }
    }
}

private object FusionPreviewRegistry {
    private val views = mutableMapOf<Int, MutableList<FusionPreviewNativeView>>()
    private val payloads = mutableMapOf<Int, FusionPreviewPayload>()

    fun attach(projectId: Int, view: FusionPreviewNativeView) {
        val bucket = views.getOrPut(projectId) { mutableListOf() }
        bucket.add(view)
        payloads[projectId]?.let {
            view.update(
                it.sourcePath,
                it.sourceKind,
                it.sourceStartSeconds,
                it.sourceEndSeconds,
                it.positionSeconds,
                it.isPlaying,
            )
        }
    }

    fun detach(projectId: Int, view: FusionPreviewNativeView) {
        views[projectId]?.remove(view)
    }

    fun update(
        projectId: Int,
        sourcePath: String?,
        sourceKind: String?,
        sourceStartSeconds: Double?,
        sourceEndSeconds: Double?,
        positionSeconds: Double,
        isPlaying: Boolean,
    ) {
        payloads[projectId] = FusionPreviewPayload(
            sourcePath = sourcePath,
            sourceKind = sourceKind,
            sourceStartSeconds = sourceStartSeconds,
            sourceEndSeconds = sourceEndSeconds,
            positionSeconds = positionSeconds,
            isPlaying = isPlaying,
        )
        views[projectId]?.forEach {
            it.update(
                sourcePath,
                sourceKind,
                sourceStartSeconds,
                sourceEndSeconds,
                positionSeconds,
                isPlaying,
            )
        }
    }
}

private data class FusionPreviewPayload(
    val sourcePath: String?,
    val sourceKind: String?,
    val sourceStartSeconds: Double?,
    val sourceEndSeconds: Double?,
    val positionSeconds: Double,
    val isPlaying: Boolean,
)

private class FusionPreviewViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val projectId = ((args as? Map<*, *>)?.get("projectId") as? Number)?.toInt() ?: viewId
        return FusionPreviewPlatformView(context, projectId)
    }
}

private class FusionPreviewPlatformView(
    context: Context,
    projectId: Int,
) : PlatformView {
    private val nativeView = FusionPreviewNativeView(context, projectId)

    override fun getView(): View = nativeView

    override fun dispose() {
        nativeView.dispose()
    }
}

private class FusionPreviewNativeView(
    context: Context,
    private val projectId: Int,
) : FrameLayout(context), TextureView.SurfaceTextureListener {
    private val textureView = TextureView(context)
    private val imageView = ImageView(context)
    private var surface: Surface? = null
    private var mediaPlayer: MediaPlayer? = null
    private var currentSourcePath: String? = null
    private var currentSourceKind: String? = null
    private var currentSourceStartSeconds: Double = 0.0
    private var currentSourceEndSeconds: Double? = null
    private var currentPositionSeconds: Double = 0.0
    private var isCurrentlyPlaying: Boolean = false
    private var isPrepared: Boolean = false
    private val boundaryRunnable = object : Runnable {
        override fun run() {
            val player = mediaPlayer ?: return
            val endSeconds = currentSourceEndSeconds ?: return
            val endMs = (endSeconds * 1000.0).toInt().coerceAtLeast(0)
            if (player.currentPosition >= endMs - 15) {
                player.pause()
                player.seekTo(endMs)
                removeCallbacks(this)
                return
            }
            if (isCurrentlyPlaying) {
                postDelayed(this, 33)
            }
        }
    }

    init {
        setBackgroundColor(Color.BLACK)

        imageView.apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            scaleType = ImageView.ScaleType.CENTER_CROP
            visibility = View.GONE
        }

        textureView.apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            surfaceTextureListener = this@FusionPreviewNativeView
            visibility = View.GONE
        }

        addView(imageView)
        addView(textureView)

        FusionPreviewRegistry.attach(projectId, this)
        update(null, null, null, null, 0.0, false)
    }

    fun update(
        sourcePath: String?,
        sourceKind: String?,
        sourceStartSeconds: Double?,
        sourceEndSeconds: Double?,
        positionSeconds: Double,
        isPlaying: Boolean,
    ) {
        val sourceChanged = sourcePath != currentSourcePath || sourceKind != currentSourceKind
        currentSourcePath = sourcePath
        currentSourceKind = sourceKind
        currentSourceStartSeconds = kotlin.math.max(0.0, sourceStartSeconds ?: 0.0)
        currentSourceEndSeconds = sourceEndSeconds
        currentPositionSeconds = positionSeconds
        isCurrentlyPlaying = isPlaying
        if (sourceChanged) {
            loadSource()
        }
        applyTransport()
    }

    fun dispose() {
        releasePlayer()
        removeCallbacks(boundaryRunnable)
        surface?.release()
        surface = null
        FusionPreviewRegistry.detach(projectId, this)
    }

    private fun loadSource() {
        when (currentSourceKind) {
            "video" -> {
                imageView.setImageDrawable(null)
                imageView.visibility = View.GONE
                textureView.visibility = View.VISIBLE
                if (surface == null) {
                    return
                }
                prepareVideoPlayer()
            }

            "image" -> {
                releasePlayer()
                textureView.visibility = View.GONE
                imageView.visibility = View.VISIBLE
                imageView.setImageBitmap(
                    currentSourcePath?.let { BitmapFactory.decodeFile(it) },
                )
            }

            else -> {
                releasePlayer()
                textureView.visibility = View.GONE
                imageView.setImageDrawable(null)
                imageView.visibility = View.GONE
            }
        }
    }

    private fun prepareVideoPlayer() {
        val path = currentSourcePath ?: run {
            releasePlayer()
            return
        }
        val previewSurface = surface ?: return
        releasePlayer()
        isPrepared = false
        mediaPlayer = MediaPlayer().apply {
            setDataSource(path)
            setSurface(previewSurface)
            isLooping = false
            setOnPreparedListener {
                isPrepared = true
                applyTransport()
            }
            prepareAsync()
        }
    }

    private fun applyTransport() {
        val player = mediaPlayer ?: return
        if (!isPrepared) return

        val targetMs = clampedPositionMs(currentPositionSeconds)
        if (kotlin.math.abs(player.currentPosition - targetMs) > 40) {
            player.seekTo(targetMs)
        }

        if (isCurrentlyPlaying) {
            val endMs = currentSourceEndSeconds
                ?.let { (it * 1000.0).toInt().coerceAtLeast(0) }
            if (endMs != null && player.currentPosition >= endMs - 15) {
                player.pause()
                player.seekTo(endMs)
                removeCallbacks(boundaryRunnable)
                return
            }
            if (!player.isPlaying) {
                player.start()
            }
            removeCallbacks(boundaryRunnable)
            post(boundaryRunnable)
        } else if (player.isPlaying) {
            player.pause()
            removeCallbacks(boundaryRunnable)
        } else {
            removeCallbacks(boundaryRunnable)
        }
    }

    private fun releasePlayer() {
        mediaPlayer?.setOnPreparedListener(null)
        mediaPlayer?.stopSafely()
        mediaPlayer?.release()
        mediaPlayer = null
        isPrepared = false
        removeCallbacks(boundaryRunnable)
    }

    private fun clampedPositionMs(seconds: Double): Int {
        val lowerBound = (currentSourceStartSeconds * 1000.0).toInt().coerceAtLeast(0)
        val upperBound = currentSourceEndSeconds
            ?.let { (it * 1000.0).toInt().coerceAtLeast(lowerBound) }
        val target = (seconds * 1000.0).toInt().coerceAtLeast(0)
        return when {
            upperBound != null -> target.coerceIn(lowerBound, upperBound)
            else -> target.coerceAtLeast(lowerBound)
        }
    }

    override fun onSurfaceTextureAvailable(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        surface = Surface(surfaceTexture)
        if (currentSourceKind == "video") {
            prepareVideoPlayer()
        }
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = Unit

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        releasePlayer()
        surface?.release()
        surface = null
        return true
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
}

private fun MediaPlayer.stopSafely() {
    try {
        stop()
    } catch (_: IllegalStateException) {
    }
}
