package com.example.fx_flutter_editor

import android.graphics.BitmapFactory
import android.content.Context
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.roundToInt

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
            val projectWidth = (args?.get("projectWidth") as? Number)?.toInt()
            val projectHeight = (args?.get("projectHeight") as? Number)?.toInt()
            val baseClipId = args?.get("baseClipId") as? String
            val selectedClipId = args?.get("selectedClipId") as? String
            val sceneNodes = (args?.get("sceneNodes") as? List<*>)
                ?.mapNotNull { it as? Map<*, *> }
                ?.map { map ->
                    map.entries
                        .filter { it.key is String }
                        .associate { it.key as String to it.value }
                }
                ?: emptyList()

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
                projectWidth,
                projectHeight,
                baseClipId,
                selectedClipId,
                sceneNodes,
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fusion_video/export_session",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startExport" -> result.error(
                    "unsupported_platform",
                    "Export foundation is currently implemented on iOS first.",
                    null,
                )
                "pollExport" -> result.success(
                    mapOf(
                        "status" to "failed",
                        "progress" to 0.0,
                        "errorMessage" to "Export foundation is currently implemented on iOS first.",
                    )
                )
                "cancelExport" -> result.success(null)
                else -> result.notImplemented()
            }
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

            "audio" -> {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(path)
                    val durationMs =
                        retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                            ?.toDoubleOrNull() ?: 0.0
                    mapOf(
                        "durationSeconds" to (durationMs / 1000.0),
                    )
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
                it.projectWidth,
                it.projectHeight,
                it.baseClipId,
                it.selectedClipId,
                it.sceneNodes,
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
        projectWidth: Int?,
        projectHeight: Int?,
        baseClipId: String?,
        selectedClipId: String?,
        sceneNodes: List<Map<String, Any?>>,
        positionSeconds: Double,
        isPlaying: Boolean,
    ) {
        payloads[projectId] = FusionPreviewPayload(
            sourcePath = sourcePath,
            sourceKind = sourceKind,
            sourceStartSeconds = sourceStartSeconds,
            sourceEndSeconds = sourceEndSeconds,
            projectWidth = projectWidth,
            projectHeight = projectHeight,
            baseClipId = baseClipId,
            selectedClipId = selectedClipId,
            sceneNodes = sceneNodes,
            positionSeconds = positionSeconds,
            isPlaying = isPlaying,
        )
        views[projectId]?.forEach {
            it.update(
                sourcePath,
                sourceKind,
                sourceStartSeconds,
                sourceEndSeconds,
                projectWidth,
                projectHeight,
                baseClipId,
                selectedClipId,
                sceneNodes,
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
    val projectWidth: Int?,
    val projectHeight: Int?,
    val baseClipId: String?,
    val selectedClipId: String?,
    val sceneNodes: List<Map<String, Any?>>,
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
    private val overlayContainer = FrameLayout(context)
    private var surface: Surface? = null
    private var mediaPlayer: MediaPlayer? = null
    private var currentSourcePath: String? = null
    private var currentSourceKind: String? = null
    private var currentSourceStartSeconds: Double = 0.0
    private var currentSourceEndSeconds: Double? = null
    private var currentProjectWidth: Int = 0
    private var currentProjectHeight: Int = 0
    private var currentBaseClipId: String? = null
    private var currentSelectedClipId: String? = null
    private var currentSceneNodes: List<Map<String, Any?>> = emptyList()
    private var lastRenderedSceneKey: String = ""
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

        overlayContainer.apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            visibility = View.VISIBLE
            isClickable = false
            isFocusable = false
        }

        addView(imageView)
        addView(textureView)
        addView(overlayContainer)

        FusionPreviewRegistry.attach(projectId, this)
        update(null, null, null, null, null, null, null, null, emptyList(), 0.0, false)
    }

    fun update(
        sourcePath: String?,
        sourceKind: String?,
        sourceStartSeconds: Double?,
        sourceEndSeconds: Double?,
        projectWidth: Int?,
        projectHeight: Int?,
        baseClipId: String?,
        selectedClipId: String?,
        sceneNodes: List<Map<String, Any?>>,
        positionSeconds: Double,
        isPlaying: Boolean,
    ) {
        val sourceChanged = sourcePath != currentSourcePath || sourceKind != currentSourceKind
        currentSourcePath = sourcePath
        currentSourceKind = sourceKind
        currentSourceStartSeconds = kotlin.math.max(0.0, sourceStartSeconds ?: 0.0)
        currentSourceEndSeconds = sourceEndSeconds
        currentProjectWidth = projectWidth ?: 0
        currentProjectHeight = projectHeight ?: 0
        currentBaseClipId = baseClipId
        currentSelectedClipId = selectedClipId
        currentSceneNodes = sceneNodes
        currentPositionSeconds = positionSeconds
        isCurrentlyPlaying = isPlaying
        if (sourceChanged) {
            loadSource()
        }
        val nextSceneKey = sceneIdentityKey()
        if (nextSceneKey != lastRenderedSceneKey) {
            renderCompositionScene()
            lastRenderedSceneKey = nextSceneKey
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
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                    .build(),
            )
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

    private fun renderCompositionScene() {
        overlayContainer.removeAllViews()
        if (currentProjectWidth <= 0 || currentProjectHeight <= 0 || width <= 0 || height <= 0) {
            return
        }

        val widthScale = width.toFloat() / currentProjectWidth.toFloat()
        val heightScale = height.toFloat() / currentProjectHeight.toFloat()
        val sortedNodes = currentSceneNodes.sortedBy {
            (it["zIndex"] as? Number)?.toInt() ?: 0
        }

        for (node in sortedNodes) {
            val clipId = node["clipId"] as? String ?: continue
            if (clipId == currentBaseClipId) continue

            val nodeWidth = ((node["width"] as? Number)?.toDouble() ?: 0.0)
            val nodeHeight = ((node["height"] as? Number)?.toDouble() ?: 0.0)
            if (nodeWidth <= 0.0 || nodeHeight <= 0.0) continue

            val params = LayoutParams(
                (nodeWidth * widthScale).roundToInt().coerceAtLeast(1),
                (nodeHeight * heightScale).roundToInt().coerceAtLeast(1),
            )
            params.leftMargin =
                (((node["x"] as? Number)?.toDouble() ?: 0.0) * widthScale).roundToInt()
            params.topMargin =
                (((node["y"] as? Number)?.toDouble() ?: 0.0) * heightScale).roundToInt()

            val card = FrameLayout(context).apply {
                layoutParams = params
                rotation = ((node["rotationDegrees"] as? Number)?.toFloat() ?: 0f)
                alpha = ((node["opacity"] as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f)
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = 12f * resources.displayMetrics.density
                    setColor(Color.parseColor("#171717"))
                    setStroke(
                        if (clipId == currentSelectedClipId) {
                            (2f * resources.displayMetrics.density).roundToInt()
                        } else {
                            (1f * resources.displayMetrics.density).roundToInt()
                        },
                        if (clipId == currentSelectedClipId) {
                            Color.parseColor("#47E0D4")
                        } else {
                            Color.argb(36, 255, 255, 255)
                        },
                    )
                }
                clipToOutline = true
                clipChildren = true
                elevation = 6f * resources.displayMetrics.density
            }

            val kind = node["kind"] as? String ?: "video"
            val localPath = node["localPath"] as? String
            val content = if (kind == "image" && !localPath.isNullOrBlank()) {
                ImageView(context).apply {
                    layoutParams = LayoutParams(
                        LayoutParams.MATCH_PARENT,
                        LayoutParams.MATCH_PARENT,
                    )
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    setImageBitmap(BitmapFactory.decodeFile(localPath))
                }
            } else {
                buildPlaceholderView(kind)
            }

            card.addView(content)
            overlayContainer.addView(card)
        }
    }

    private fun buildPlaceholderView(kind: String): View {
        return FrameLayout(context).apply {
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            setBackgroundColor(Color.parseColor("#171717"))

            val icon = TextView(context).apply {
                text = placeholderGlyph(kind)
                setTextColor(Color.argb(220, 255, 255, 255))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                gravity = Gravity.CENTER
                typeface = Typeface.DEFAULT_BOLD
            }
            val label = TextView(context).apply {
                text = placeholderTitle(kind)
                setTextColor(Color.argb(220, 255, 255, 255))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                gravity = Gravity.CENTER
                typeface = Typeface.DEFAULT_BOLD
            }

            addView(
                icon,
                LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER).apply {
                    topMargin = (-10f * resources.displayMetrics.density).roundToInt()
                },
            )
            addView(
                label,
                LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER).apply {
                    topMargin = (22f * resources.displayMetrics.density).roundToInt()
                },
            )
        }
    }

    private fun placeholderGlyph(kind: String): String {
        return when (kind) {
            "image" -> "▣"
            "text" -> "T"
            "lipSync" -> "≋"
            else -> "▶"
        }
    }

    private fun placeholderTitle(kind: String): String {
        return when (kind) {
            "image" -> "Image"
            "text" -> "Text"
            "lipSync" -> "Lip Sync"
            else -> "Video"
        }
    }

    private fun applyTransport() {
        val player = mediaPlayer ?: return
        if (!isPrepared) return

        val targetMs = clampedPositionMs(currentPositionSeconds)
        val seekThresholdMs = if (isCurrentlyPlaying) 180 else 40
        if (kotlin.math.abs(player.currentPosition - targetMs) > seekThresholdMs) {
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

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        lastRenderedSceneKey = ""
        renderCompositionScene()
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = Unit

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        releasePlayer()
        surface?.release()
        surface = null
        return true
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

    private fun sceneIdentityKey(): String {
        val builder = StringBuilder()
        builder
            .append("pw:")
            .append(currentProjectWidth)
            .append("|ph:")
            .append(currentProjectHeight)
            .append("|base:")
            .append(currentBaseClipId ?: "")
            .append("|selected:")
            .append(currentSelectedClipId ?: "")
            .append("|count:")
            .append(currentSceneNodes.size)

        currentSceneNodes
            .sortedBy { it["clipId"] as? String ?: "" }
            .forEach { node ->
                builder
                    .append("||")
                    .append(node["clipId"] as? String ?: "")
                    .append('|')
                    .append(node["kind"] as? String ?: "")
                    .append('|')
                    .append(node["localPath"] as? String ?: "")
                    .append('|')
                    .append(node["displayLabel"] as? String ?: "")
                    .append('|')
                    .append((node["x"] as? Number)?.toDouble() ?: 0.0)
                    .append('|')
                    .append((node["y"] as? Number)?.toDouble() ?: 0.0)
                    .append('|')
                    .append((node["width"] as? Number)?.toDouble() ?: 0.0)
                    .append('|')
                    .append((node["height"] as? Number)?.toDouble() ?: 0.0)
                    .append('|')
                    .append((node["opacity"] as? Number)?.toDouble() ?: 1.0)
                    .append('|')
                    .append((node["rotationDegrees"] as? Number)?.toDouble() ?: 0.0)
                    .append('|')
                    .append((node["zIndex"] as? Number)?.toInt() ?: 0)
            }
        return builder.toString()
    }
}

private fun MediaPlayer.stopSafely() {
    try {
        stop()
    } catch (_: IllegalStateException) {
    }
}
