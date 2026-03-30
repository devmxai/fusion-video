package com.example.fx_flutter_editor

import android.graphics.BitmapFactory
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.example.fx_flutter_editor.previewengine.AndroidMediaIo
import com.example.fx_flutter_editor.previewengine.AndroidTimelineThumbnailRepository
import com.example.fx_flutter_editor.previewengine.FusionAndroidPreviewEngine
import com.example.fx_flutter_editor.previewengine.PreviewTransportCommandEnvelope
import com.example.fx_flutter_editor.previewengine.ResolvedPreviewConfiguration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val mediaThumbnailExecutor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mediaIo = AndroidMediaIo()
    private val timelineThumbnailRepository = AndroidTimelineThumbnailRepository(mediaIo)
    private val previewEngine = FusionAndroidPreviewEngine(mediaIo = mediaIo)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "fusion_video/preview_surface",
                FusionPreviewViewFactory(),
            )
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "fusion_video/preview_surface_engine",
                FusionEnginePreviewViewFactory(previewEngine),
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
            val transportRevision = (args?.get("transportRevision") as? Number)?.toInt() ?: 0
            val sourceId = args?.get("sourceId") as? String
            val sourcePath = args?.get("sourcePath") as? String
            val sourceKind = args?.get("sourceKind") as? String
            val upcomingSourceId = args?.get("upcomingSourceId") as? String
            val upcomingSourcePath = args?.get("upcomingSourcePath") as? String
            val upcomingSourceKind = args?.get("upcomingSourceKind") as? String
            val clipStartSeconds = (args?.get("clipStartSeconds") as? Number)?.toDouble()
            val clipEndSeconds = (args?.get("clipEndSeconds") as? Number)?.toDouble()
            val sourceStartSeconds = (args?.get("sourceStartSeconds") as? Number)?.toDouble()
            val sourceEndSeconds = (args?.get("sourceEndSeconds") as? Number)?.toDouble()
            val upcomingSourceStartSeconds =
                (args?.get("upcomingSourceStartSeconds") as? Number)?.toDouble()
            val upcomingSourceEndSeconds =
                (args?.get("upcomingSourceEndSeconds") as? Number)?.toDouble()
            val projectWidth = (args?.get("projectWidth") as? Number)?.toInt()
            val projectHeight = (args?.get("projectHeight") as? Number)?.toInt()
            val baseClipId = args?.get("baseClipId") as? String
            val baseClipIds =
                (args?.get("baseClipIds") as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
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

            FusionPreviewRegistry.updateLegacyPreview(
                projectId,
                transportRevision,
                sourceId,
                sourcePath,
                sourceKind,
                upcomingSourceId,
                upcomingSourcePath,
                upcomingSourceKind,
                clipStartSeconds,
                clipEndSeconds,
                sourceStartSeconds,
                sourceEndSeconds,
                upcomingSourceStartSeconds,
                upcomingSourceEndSeconds,
                projectWidth,
                projectHeight,
                baseClipId,
                baseClipIds,
                selectedClipId,
                sceneNodes,
                positionSeconds,
                isPlaying,
            )
            result.success(null)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fusion_video/preview_engine",
        ).setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *>
            when (call.method) {
                "isEnginePreviewAvailable" -> result.success(previewEngine.isScaffoldReady)
                "configurePreviewEngine" -> {
                    val projectId = (args?.get("projectId") as? Number)?.toInt()
                    val positionSeconds = (args?.get("positionSeconds") as? Number)?.toDouble()
                    val isPlaying = args?.get("isPlaying") as? Boolean
                    if (projectId == null || positionSeconds == null || isPlaying == null) {
                        result.error("invalid_args", "Missing preview engine arguments", null)
                        return@setMethodCallHandler
                    }
                    FusionPreviewRegistry.cachePayload(
                        projectId,
                        (args["transportRevision"] as? Number)?.toInt() ?: 0,
                        args["sourceId"] as? String,
                        args["sourcePath"] as? String,
                        args["sourceKind"] as? String,
                        args["upcomingSourceId"] as? String,
                        args["upcomingSourcePath"] as? String,
                        args["upcomingSourceKind"] as? String,
                        (args["clipStartSeconds"] as? Number)?.toDouble(),
                        (args["clipEndSeconds"] as? Number)?.toDouble(),
                        (args["sourceStartSeconds"] as? Number)?.toDouble(),
                        (args["sourceEndSeconds"] as? Number)?.toDouble(),
                        (args["upcomingSourceStartSeconds"] as? Number)?.toDouble(),
                        (args["upcomingSourceEndSeconds"] as? Number)?.toDouble(),
                        (args["projectWidth"] as? Number)?.toInt(),
                        (args["projectHeight"] as? Number)?.toInt(),
                        args["baseClipId"] as? String,
                        (args["baseClipIds"] as? List<*>)?.mapNotNull { it as? String }
                            ?: emptyList(),
                        args["selectedClipId"] as? String,
                        (args["sceneNodes"] as? List<*>)
                            ?.mapNotNull { it as? Map<*, *> }
                            ?.map { map ->
                                map.entries
                                    .filter { it.key is String }
                                    .associate { it.key as String to it.value }
                            }
                            ?: emptyList(),
                        positionSeconds,
                        isPlaying,
                    )
                    previewEngine.configure(
                        ResolvedPreviewConfiguration(
                            projectId = projectId,
                            positionSeconds = positionSeconds,
                            isPlaying = isPlaying,
                            transportRevision = (args["transportRevision"] as? Number)?.toInt() ?: 0,
                            sourceId = args["sourceId"] as? String,
                            sourcePath = args["sourcePath"] as? String,
                            sourceKind = args["sourceKind"] as? String,
                            upcomingSourceId = args["upcomingSourceId"] as? String,
                            upcomingSourcePath = args["upcomingSourcePath"] as? String,
                            upcomingSourceKind = args["upcomingSourceKind"] as? String,
                            clipStartSeconds = (args["clipStartSeconds"] as? Number)?.toDouble(),
                            clipEndSeconds = (args["clipEndSeconds"] as? Number)?.toDouble(),
                            sourceStartSeconds = (args["sourceStartSeconds"] as? Number)?.toDouble(),
                            sourceEndSeconds = (args["sourceEndSeconds"] as? Number)?.toDouble(),
                            upcomingSourceStartSeconds =
                                (args["upcomingSourceStartSeconds"] as? Number)?.toDouble(),
                            upcomingSourceEndSeconds =
                                (args["upcomingSourceEndSeconds"] as? Number)?.toDouble(),
                            projectWidth = (args["projectWidth"] as? Number)?.toInt(),
                            projectHeight = (args["projectHeight"] as? Number)?.toInt(),
                            baseClipId = args["baseClipId"] as? String,
                            baseClipIds =
                                (args["baseClipIds"] as? List<*>)?.mapNotNull { it as? String }
                                    ?: emptyList(),
                            selectedClipId = args["selectedClipId"] as? String,
                            continuityKind = args["continuityKind"] as? String,
                            sceneNodes =
                                (args["sceneNodes"] as? List<*>)
                                    ?.mapNotNull { it as? Map<*, *> }
                                    ?.map { map ->
                                        map.entries
                                            .filter { it.key is String }
                                            .associate { it.key as String to it.value }
                                    }
                                    ?: emptyList(),
                            audioNodes =
                                (args["audioNodes"] as? List<*>)
                                    ?.mapNotNull { it as? Map<*, *> }
                                    ?.map { map ->
                                        map.entries
                                            .filter { it.key is String }
                                            .associate { it.key as String to it.value }
                                    }
                                    ?: emptyList(),
                        )
                    )
                    result.success(null)
                }
                "dispatchPreviewCommand" -> {
                    val projectId = (args?.get("projectId") as? Number)?.toInt()
                    val transportRevision =
                        (args?.get("transportRevision") as? Number)?.toInt() ?: 0
                    val kind = args?.get("kind") as? String
                    if (projectId == null || kind == null) {
                        result.error("invalid_args", "Missing preview command arguments", null)
                        return@setMethodCallHandler
                    }
                    previewEngine.dispatch(
                        PreviewTransportCommandEnvelope(
                            projectId = projectId,
                            transportRevision = transportRevision,
                            kind = kind,
                            positionSeconds = (args["positionSeconds"] as? Number)?.toDouble(),
                            isPlaying = args["isPlaying"] as? Boolean,
                        )
                    )
                    FusionPreviewRegistry.dispatchCommand(
                        projectId = projectId,
                        transportRevision = transportRevision,
                        commandKind = kind,
                        positionSeconds = (args["positionSeconds"] as? Number)?.toDouble(),
                        isPlaying = args["isPlaying"] as? Boolean,
                        updateLegacyViews = false,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fusion_video/preview_events",
        ).setStreamHandler(FusionPreviewEventsStreamHandler)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fusion_video/media_probe",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "probeMedia" -> {
                    val args = call.arguments as? Map<*, *>
                    val path = args?.get("path") as? String
                    val kind = args?.get("kind") as? String

                    if (path == null || kind == null) {
                        result.error("invalid_args", "Missing probe arguments", null)
                        return@setMethodCallHandler
                    }

                    result.success(FusionMediaProbe.probe(path, kind))
                }

                "generateVideoThumbnails" -> {
                    val args = call.arguments as? Map<*, *>
                    val path = args?.get("path") as? String
                    val timestampsSeconds =
                        (args?.get("timestampsSeconds") as? List<*>)?.mapNotNull {
                            (it as? Number)?.toDouble()
                        }
                    val targetWidth = (args?.get("targetWidth") as? Number)?.toInt() ?: 80
                    val targetHeight = (args?.get("targetHeight") as? Number)?.toInt() ?: 48

                    if (path == null || timestampsSeconds == null) {
                        result.error("invalid_args", "Missing thumbnail arguments", null)
                        return@setMethodCallHandler
                    }

                    mediaThumbnailExecutor.execute {
                        try {
                            val thumbnails =
                                timelineThumbnailRepository.loadVideoThumbnails(
                                    path = path,
                                    timestampsSeconds = timestampsSeconds,
                                    targetWidth = targetWidth,
                                    targetHeight = targetHeight,
                                )
                            mainHandler.post {
                                result.success(thumbnails)
                            }
                        } catch (error: Throwable) {
                            mainHandler.post {
                                result.error(
                                    "thumbnail_failed",
                                    error.message ?: "Failed to generate thumbnails",
                                    null,
                                )
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
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

    override fun onDestroy() {
        mediaThumbnailExecutor.shutdown()
        super.onDestroy()
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
                    val rotationDegrees =
                        retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                            ?.toIntOrNull() ?: 0
                    val isQuarterTurn = rotationDegrees % 180 != 0
                    buildMap<String, Any> {
                        put("durationSeconds", durationMs / 1000.0)
                        if (width != null) put("width", if (isQuarterTurn) height ?: width else width)
                        if (height != null) put("height", if (isQuarterTurn) width ?: height else height)
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

object FusionPreviewRegistry {
    private val legacyViews = mutableMapOf<Int, MutableList<FusionPreviewNativeView>>()
    private val payloads = mutableMapOf<Int, FusionPreviewPayload>()
    private val runtimeStates = mutableMapOf<Int, FusionPreviewRuntimeState>()
    private var eventSink: EventChannel.EventSink? = null

    fun attachLegacyView(projectId: Int, view: FusionPreviewNativeView) {
        val bucket = legacyViews.getOrPut(projectId) { mutableListOf() }
        bucket.add(view)
        payloads[projectId]?.let {
            view.update(
                it.transportRevision,
                it.sourceId,
                it.sourcePath,
                it.sourceKind,
                it.upcomingSourceId,
                it.upcomingSourcePath,
                it.upcomingSourceKind,
                it.clipStartSeconds,
                it.clipEndSeconds,
                it.sourceStartSeconds,
                it.sourceEndSeconds,
                it.upcomingSourceStartSeconds,
                it.upcomingSourceEndSeconds,
                it.projectWidth,
                it.projectHeight,
                it.baseClipId,
                it.baseClipIds,
                it.selectedClipId,
                it.sceneNodes,
                it.positionSeconds,
                it.isPlaying,
            )
        }
    }

    fun detachLegacyView(projectId: Int, view: FusionPreviewNativeView) {
        legacyViews[projectId]?.remove(view)
        if (legacyViews[projectId].isNullOrEmpty()) {
            legacyViews.remove(projectId)
            runtimeStates.remove(projectId)
        }
    }

    fun cachePayload(
        projectId: Int,
        transportRevision: Int,
        sourceId: String?,
        sourcePath: String?,
        sourceKind: String?,
        upcomingSourceId: String?,
        upcomingSourcePath: String?,
        upcomingSourceKind: String?,
        clipStartSeconds: Double?,
        clipEndSeconds: Double?,
        sourceStartSeconds: Double?,
        sourceEndSeconds: Double?,
        upcomingSourceStartSeconds: Double?,
        upcomingSourceEndSeconds: Double?,
        projectWidth: Int?,
        projectHeight: Int?,
        baseClipId: String?,
        baseClipIds: List<String>,
        selectedClipId: String?,
        sceneNodes: List<Map<String, Any?>>,
        positionSeconds: Double,
        isPlaying: Boolean,
    ) {
        val payload =
            FusionPreviewPayload(
            transportRevision = transportRevision,
            sourceId = sourceId,
            sourcePath = sourcePath,
            sourceKind = sourceKind,
            upcomingSourceId = upcomingSourceId,
            upcomingSourcePath = upcomingSourcePath,
            upcomingSourceKind = upcomingSourceKind,
            clipStartSeconds = clipStartSeconds,
            clipEndSeconds = clipEndSeconds,
            sourceStartSeconds = sourceStartSeconds,
            sourceEndSeconds = sourceEndSeconds,
            upcomingSourceStartSeconds = upcomingSourceStartSeconds,
            upcomingSourceEndSeconds = upcomingSourceEndSeconds,
            projectWidth = projectWidth,
            projectHeight = projectHeight,
            baseClipId = baseClipId,
            baseClipIds = baseClipIds,
            selectedClipId = selectedClipId,
            sceneNodes = sceneNodes,
            positionSeconds = positionSeconds,
            isPlaying = isPlaying,
        )
        payloads[projectId] = payload
        emitRuntimeEvent(projectId, payload)
    }

    fun updateLegacyPreview(
        projectId: Int,
        transportRevision: Int,
        sourceId: String?,
        sourcePath: String?,
        sourceKind: String?,
        upcomingSourceId: String?,
        upcomingSourcePath: String?,
        upcomingSourceKind: String?,
        clipStartSeconds: Double?,
        clipEndSeconds: Double?,
        sourceStartSeconds: Double?,
        sourceEndSeconds: Double?,
        upcomingSourceStartSeconds: Double?,
        upcomingSourceEndSeconds: Double?,
        projectWidth: Int?,
        projectHeight: Int?,
        baseClipId: String?,
        baseClipIds: List<String>,
        selectedClipId: String?,
        sceneNodes: List<Map<String, Any?>>,
        positionSeconds: Double,
        isPlaying: Boolean,
    ) {
        cachePayload(
            projectId = projectId,
            transportRevision = transportRevision,
            sourceId = sourceId,
            sourcePath = sourcePath,
            sourceKind = sourceKind,
            upcomingSourceId = upcomingSourceId,
            upcomingSourcePath = upcomingSourcePath,
            upcomingSourceKind = upcomingSourceKind,
            clipStartSeconds = clipStartSeconds,
            clipEndSeconds = clipEndSeconds,
            sourceStartSeconds = sourceStartSeconds,
            sourceEndSeconds = sourceEndSeconds,
            upcomingSourceStartSeconds = upcomingSourceStartSeconds,
            upcomingSourceEndSeconds = upcomingSourceEndSeconds,
            projectWidth = projectWidth,
            projectHeight = projectHeight,
            baseClipId = baseClipId,
            baseClipIds = baseClipIds,
            selectedClipId = selectedClipId,
            sceneNodes = sceneNodes,
            positionSeconds = positionSeconds,
            isPlaying = isPlaying,
        )
        legacyViews[projectId]?.forEach {
            it.update(
                transportRevision,
                sourceId,
                sourcePath,
                sourceKind,
                upcomingSourceId,
                upcomingSourcePath,
                upcomingSourceKind,
                clipStartSeconds,
                clipEndSeconds,
                sourceStartSeconds,
                sourceEndSeconds,
                upcomingSourceStartSeconds,
                upcomingSourceEndSeconds,
                projectWidth,
                projectHeight,
                baseClipId,
                baseClipIds,
                selectedClipId,
                sceneNodes,
                positionSeconds,
                isPlaying,
            )
        }
    }

    fun dispatchCommand(
        projectId: Int,
        transportRevision: Int,
        commandKind: String,
        positionSeconds: Double?,
        isPlaying: Boolean?,
        updateLegacyViews: Boolean = true,
    ) {
        val current = payloads[projectId] ?: FusionPreviewPayload(
            transportRevision = transportRevision,
            sourceId = null,
            sourcePath = null,
            sourceKind = null,
            upcomingSourceId = null,
            upcomingSourcePath = null,
            upcomingSourceKind = null,
            clipStartSeconds = null,
            clipEndSeconds = null,
            sourceStartSeconds = null,
            sourceEndSeconds = null,
            upcomingSourceStartSeconds = null,
            upcomingSourceEndSeconds = null,
            projectWidth = null,
            projectHeight = null,
            baseClipId = null,
            baseClipIds = emptyList(),
            selectedClipId = null,
            sceneNodes = emptyList(),
            positionSeconds = positionSeconds ?: 0.0,
            isPlaying = false,
        )
        val nextIsPlaying = isPlaying ?: when (commandKind) {
            "play" -> true
            "pause" -> false
            else -> current.isPlaying
        }
        if (updateLegacyViews) {
            updateLegacyPreview(
                projectId = projectId,
                transportRevision = transportRevision,
                sourceId = current.sourceId,
                sourcePath = current.sourcePath,
                sourceKind = current.sourceKind,
                upcomingSourceId = current.upcomingSourceId,
                upcomingSourcePath = current.upcomingSourcePath,
                upcomingSourceKind = current.upcomingSourceKind,
                clipStartSeconds = current.clipStartSeconds,
                clipEndSeconds = current.clipEndSeconds,
                sourceStartSeconds = current.sourceStartSeconds,
                sourceEndSeconds = current.sourceEndSeconds,
                upcomingSourceStartSeconds = current.upcomingSourceStartSeconds,
                upcomingSourceEndSeconds = current.upcomingSourceEndSeconds,
                projectWidth = current.projectWidth,
                projectHeight = current.projectHeight,
                baseClipId = current.baseClipId,
                baseClipIds = current.baseClipIds,
                selectedClipId = current.selectedClipId,
                sceneNodes = current.sceneNodes,
                positionSeconds = positionSeconds ?: current.positionSeconds,
                isPlaying = nextIsPlaying,
            )
        } else {
            cachePayload(
                projectId = projectId,
                transportRevision = transportRevision,
                sourceId = current.sourceId,
                sourcePath = current.sourcePath,
                sourceKind = current.sourceKind,
                upcomingSourceId = current.upcomingSourceId,
                upcomingSourcePath = current.upcomingSourcePath,
                upcomingSourceKind = current.upcomingSourceKind,
                clipStartSeconds = current.clipStartSeconds,
                clipEndSeconds = current.clipEndSeconds,
                sourceStartSeconds = current.sourceStartSeconds,
                sourceEndSeconds = current.sourceEndSeconds,
                upcomingSourceStartSeconds = current.upcomingSourceStartSeconds,
                upcomingSourceEndSeconds = current.upcomingSourceEndSeconds,
                projectWidth = current.projectWidth,
                projectHeight = current.projectHeight,
                baseClipId = current.baseClipId,
                baseClipIds = current.baseClipIds,
                selectedClipId = current.selectedClipId,
                sceneNodes = current.sceneNodes,
                positionSeconds = positionSeconds ?: current.positionSeconds,
                isPlaying = nextIsPlaying,
            )
        }
    }

    fun addEventSink(sink: EventChannel.EventSink) {
        eventSink = sink
        payloads.forEach { (projectId, payload) ->
            emitRuntimeEvent(projectId, payload, sink)
        }
    }

    fun removeEventSink(sink: EventChannel.EventSink) {
        if (eventSink == sink) {
            eventSink = null
        }
    }

    fun reportRuntimeState(projectId: Int, state: FusionPreviewRuntimeState) {
        runtimeStates[projectId] = state
        payloads[projectId]?.let { emitRuntimeEvent(projectId, it) }
    }

    private fun emitRuntimeEvent(
        projectId: Int,
        payload: FusionPreviewPayload,
        sink: EventChannel.EventSink? = null,
    ) {
        val runtimeState = runtimeStates[projectId]
        val event = mapOf(
            "projectId" to projectId,
            "positionSeconds" to (runtimeState?.positionSeconds ?: payload.positionSeconds),
            "isPlaying" to (runtimeState?.isPlaying ?: payload.isPlaying),
            "transportRevision" to (runtimeState?.transportRevision ?: payload.transportRevision),
            "isBuffering" to (runtimeState?.isBuffering ?: false),
            "frameReady" to (
                runtimeState?.frameReady
                    ?: (payload.sourceId != null || payload.sourcePath != null)
                ),
            "frameDropCount" to (runtimeState?.frameDropCount ?: 0),
            "audioDropCount" to (runtimeState?.audioDropCount ?: 0),
            "bufferUnderrunCount" to (runtimeState?.bufferUnderrunCount ?: 0),
            "previewLatencyMillis" to (runtimeState?.previewLatencyMillis ?: 0.0),
            "seekLatencyMillis" to (runtimeState?.seekLatencyMillis ?: 0.0),
        )
        if (sink != null) {
            sink.success(event)
            return
        }
        eventSink?.success(event)
    }
}

private object FusionPreviewEventsStreamHandler : EventChannel.StreamHandler {
    private var currentSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events != null) {
            currentSink = events
            FusionPreviewRegistry.addEventSink(events)
        }
    }

    override fun onCancel(arguments: Any?) {
        currentSink?.let(FusionPreviewRegistry::removeEventSink)
        currentSink = null
    }
}

private data class FusionPreviewPayload(
    val transportRevision: Int,
    val sourceId: String?,
    val sourcePath: String?,
    val sourceKind: String?,
    val upcomingSourceId: String?,
    val upcomingSourcePath: String?,
    val upcomingSourceKind: String?,
    val clipStartSeconds: Double?,
    val clipEndSeconds: Double?,
    val sourceStartSeconds: Double?,
    val sourceEndSeconds: Double?,
    val upcomingSourceStartSeconds: Double?,
    val upcomingSourceEndSeconds: Double?,
    val projectWidth: Int?,
    val projectHeight: Int?,
    val baseClipId: String?,
    val baseClipIds: List<String>,
    val selectedClipId: String?,
    val sceneNodes: List<Map<String, Any?>>,
    val positionSeconds: Double,
    val isPlaying: Boolean,
)

data class FusionPreviewRuntimeState(
    val positionSeconds: Double,
    val isPlaying: Boolean,
    val transportRevision: Int,
    val isBuffering: Boolean,
    val frameReady: Boolean,
    val frameDropCount: Int,
    val audioDropCount: Int,
    val bufferUnderrunCount: Int,
    val previewLatencyMillis: Double,
    val seekLatencyMillis: Double,
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

class FusionPreviewNativeView(
    context: Context,
    private val projectId: Int,
) : FrameLayout(context), TextureView.SurfaceTextureListener {
    private val textureView = TextureView(context)
    private val imageView = ImageView(context)
    private val overlayContainer = FrameLayout(context)
    private var surface: Surface? = null
    private var mediaPlayer: MediaPlayer? = null
    private var currentSourceId: String? = null
    private var currentSourcePath: String? = null
    private var currentSourceKind: String? = null
    private var upcomingSourceId: String? = null
    private var upcomingSourcePath: String? = null
    private var upcomingSourceKind: String? = null
    private var currentClipStartSeconds: Double = 0.0
    private var currentClipEndSeconds: Double? = null
    private var currentSourceStartSeconds: Double = 0.0
    private var currentSourceEndSeconds: Double? = null
    private var upcomingSourceStartSeconds: Double = 0.0
    private var upcomingSourceEndSeconds: Double? = null
    private var currentProjectWidth: Int = 0
    private var currentProjectHeight: Int = 0
    private var currentBaseClipId: String? = null
    private var currentBaseClipIds: Set<String> = emptySet()
    private var currentSelectedClipId: String? = null
    private var currentSceneNodes: List<Map<String, Any?>> = emptyList()
    private var lastRenderedSceneKey: String = ""
    private var currentPositionSeconds: Double = 0.0
    private var isCurrentlyPlaying: Boolean = false
    private var isPrepared: Boolean = false
    private var preloadedMediaPlayer: MediaPlayer? = null
    private var preloadedImageBitmap: Bitmap? = null
    private var preloadedSourceId: String? = null
    private var preloadedSourcePath: String? = null
    private var preloadedSourceKind: String? = null
    private var preloadedSourceStartSeconds: Double = 0.0
    private var preloadedSourceEndSeconds: Double? = null
    private var isPreloadedPrepared: Boolean = false
    private var lastAppliedTransportRevision: Int = -1
    private var pendingSeekTargetMs: Int? = null
    private var pendingPlayAfterSeek: Boolean = false
    private var pendingSeekRetryCount: Int = 0
    private var pendingSeekStartedRealtimeMs: Long? = null
    private var lastTransportMutationRealtimeMs: Long = 0L
    private var lastRuntimeEmitRealtimeMs: Long = 0L
    private var lastFrameRealtimeMs: Long = 0L
    private var runtimeIsBuffering: Boolean = false
    private var runtimeFrameReady: Boolean = false
    private var runtimeFrameDropCount: Int = 0
    private var runtimeAudioDropCount: Int = 0
    private var runtimeBufferUnderrunCount: Int = 0
    private var runtimePreviewLatencyMillis: Double = 0.0
    private var runtimeSeekLatencyMillis: Double = 0.0
    private var awaitingPreviewFrame: Boolean = false
    private val boundaryRunnable = object : Runnable {
        override fun run() {
            removeCallbacks(this)
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

        FusionPreviewRegistry.attachLegacyView(projectId, this)
        update(
            0,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            emptyList(),
            null,
            emptyList(),
            0.0,
            false,
        )
    }

    fun update(
        transportRevision: Int,
        sourceId: String?,
        sourcePath: String?,
        sourceKind: String?,
        upcomingSourceId: String?,
        upcomingSourcePath: String?,
        upcomingSourceKind: String?,
        clipStartSeconds: Double?,
        clipEndSeconds: Double?,
        sourceStartSeconds: Double?,
        sourceEndSeconds: Double?,
        upcomingSourceStartSeconds: Double?,
        upcomingSourceEndSeconds: Double?,
        projectWidth: Int?,
        projectHeight: Int?,
        baseClipId: String?,
        baseClipIds: List<String>,
        selectedClipId: String?,
        sceneNodes: List<Map<String, Any?>>,
        positionSeconds: Double,
        isPlaying: Boolean,
    ) {
        val selectionChanged = selectedClipId != currentSelectedClipId
        val playStateChanged = isPlaying != isCurrentlyPlaying
        val transportChanged = transportRevision != lastAppliedTransportRevision
        lastAppliedTransportRevision = transportRevision
        val nextSourceStartSeconds = kotlin.math.max(0.0, sourceStartSeconds ?: 0.0)
        val nextHasSource = sourceId != null || sourcePath != null || sourceKind != null
        val currentHasSource =
            currentSourceId != null || currentSourcePath != null || currentSourceKind != null
        val sourceChanged =
            nextHasSource != currentHasSource ||
                (
                    nextHasSource &&
                        !previewSourceMatches(
                            sourceId = sourceId,
                            sourcePath = sourcePath,
                            sourceKind = sourceKind,
                            sourceStartSeconds = nextSourceStartSeconds,
                            sourceEndSeconds = sourceEndSeconds,
                            againstId = currentSourceId,
                            againstPath = currentSourcePath,
                            againstKind = currentSourceKind,
                            againstStartSeconds = currentSourceStartSeconds,
                            againstEndSeconds = currentSourceEndSeconds,
                        )
                )
        currentSourceId = sourceId
        currentSourcePath = sourcePath
        currentSourceKind = sourceKind
        this.upcomingSourceId = upcomingSourceId
        this.upcomingSourcePath = upcomingSourcePath
        this.upcomingSourceKind = upcomingSourceKind
        currentClipStartSeconds = kotlin.math.max(0.0, clipStartSeconds ?: 0.0)
        currentClipEndSeconds = clipEndSeconds
        currentSourceStartSeconds = nextSourceStartSeconds
        currentSourceEndSeconds = sourceEndSeconds
        this.upcomingSourceStartSeconds =
            kotlin.math.max(0.0, upcomingSourceStartSeconds ?: 0.0)
        this.upcomingSourceEndSeconds = upcomingSourceEndSeconds
        currentProjectWidth = projectWidth ?: 0
        currentProjectHeight = projectHeight ?: 0
        currentBaseClipId = baseClipId
        currentBaseClipIds =
            buildSet {
                addAll(baseClipIds)
                baseClipId?.let(::add)
            }
        currentSelectedClipId = selectedClipId
        currentSceneNodes = sceneNodes
        currentPositionSeconds = positionSeconds
        isCurrentlyPlaying = isPlaying
        if (sourceChanged || transportChanged || playStateChanged) {
            noteTransportMutation(expectFrame = currentSourceKind == "video")
        }
        if (sourceChanged) {
            loadSource()
        }
        prepareUpcomingSource()
        val nextSceneKey = sceneIdentityKey()
        if (
            nextSceneKey != lastRenderedSceneKey ||
                (selectionChanged && !isCurrentlyPlaying && !playStateChanged)
        ) {
            renderCompositionScene()
            lastRenderedSceneKey = nextSceneKey
        }
        applyTransport(
            shouldRetarget = sourceChanged || transportChanged,
        )
        reportRuntimeState(force = true)
    }

    fun dispose() {
        releasePlayer()
        releasePreloadedSource()
        removeCallbacks(boundaryRunnable)
        surface?.release()
        surface = null
        FusionPreviewRegistry.detachLegacyView(projectId, this)
    }

    private fun loadSource() {
        when (currentSourceKind) {
            "video" -> {
                imageView.setImageDrawable(null)
                imageView.visibility = View.GONE
                textureView.visibility = View.VISIBLE
                runtimeFrameReady = false
                prepareVideoPlayer()
            }

            "image" -> {
                releasePlayer()
                textureView.visibility = View.GONE
                imageView.visibility = View.VISIBLE
                val bitmap =
                    takePreloadedImageIfMatching()
                        ?: currentSourcePath?.let { BitmapFactory.decodeFile(it) }
                imageView.setImageBitmap(bitmap)
                runtimeFrameReady = bitmap != null
                awaitingPreviewFrame = false
                runtimeIsBuffering = false
                reportRuntimeState(force = true)
            }

            else -> {
                releasePlayer()
                textureView.visibility = View.GONE
                imageView.setImageDrawable(null)
                imageView.visibility = View.GONE
                releasePreloadedSource()
                runtimeFrameReady = false
                awaitingPreviewFrame = false
                runtimeIsBuffering = false
                reportRuntimeState(force = true)
            }
        }
    }

    private fun prepareVideoPlayer() {
        val path = currentSourcePath ?: run {
            releasePlayer()
            runtimeFrameReady = false
            reportRuntimeState(force = true)
            return
        }
        val previewSurface = surface ?: run {
            runtimeFrameReady = false
            reportRuntimeState(force = true)
            return
        }
        val nextPlayer = takePreloadedPlayerIfMatching()
        releasePlayer()
        isPrepared = false
        if (nextPlayer != null) {
            mediaPlayer = nextPlayer
            mediaPlayer?.setVolume(1f, 1f)
            mediaPlayer?.setSurface(previewSurface)
            installPlayerListeners(mediaPlayer) {
                isPrepared = true
                applyTransport(shouldRetarget = true)
            }
            isPrepared = isPreloadedPrepared
            isPreloadedPrepared = false
            if (isPrepared) {
                applyTransport(shouldRetarget = true)
            }
            reportRuntimeState(force = true)
            return
        }

        mediaPlayer = buildVideoPlayer(path, previewSurface) {
            isPrepared = true
            runtimeIsBuffering = false
            applyTransport(shouldRetarget = true)
            reportRuntimeState(force = true)
        }
    }

    private fun buildVideoPlayer(
        path: String,
        surface: Surface? = null,
        muted: Boolean = false,
        onPrepared: () -> Unit,
    ): MediaPlayer {
        val player = MediaPlayer()
        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build(),
        )
        player.setDataSource(path)
        if (surface != null) {
            player.setSurface(surface)
        }
        player.setVolume(if (muted) 0f else 1f, if (muted) 0f else 1f)
        player.isLooping = false
        installPlayerListeners(player, onPrepared)
        player.prepareAsync()
        return player
    }

    private fun installPlayerListeners(
        player: MediaPlayer?,
        onPrepared: (() -> Unit)? = null,
    ) {
        player ?: return
        player.setOnPreparedListener { onPrepared?.invoke() }
        player.setOnInfoListener { mp, what, _ ->
            if (mp !== mediaPlayer) {
                return@setOnInfoListener false
            }
            when (what) {
                MediaPlayer.MEDIA_INFO_BUFFERING_START -> {
                    runtimeIsBuffering = true
                    runtimeBufferUnderrunCount += 1
                    reportRuntimeState(force = true)
                }

                MediaPlayer.MEDIA_INFO_BUFFERING_END -> {
                    runtimeIsBuffering = false
                    reportRuntimeState(force = true)
                }
            }
            false
        }
        player.setOnSeekCompleteListener {
            if (it !== mediaPlayer) {
                return@setOnSeekCompleteListener
            }
            handleSeekComplete(it)
        }
    }

    private fun clearPlayerListeners(player: MediaPlayer?) {
        player?.setOnPreparedListener(null)
        player?.setOnInfoListener(null)
        player?.setOnSeekCompleteListener(null)
    }

    private fun handleSeekComplete(player: MediaPlayer) {
        if (!isPrepared || player !== mediaPlayer) {
            return
        }
        val targetMs = pendingSeekTargetMs ?: run {
            applyDesiredPlaybackState(player)
            return
        }
        val completionToleranceMs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            48
        } else {
            120
        }
        if (
            kotlin.math.abs(player.currentPosition - targetMs) > completionToleranceMs &&
            pendingSeekRetryCount < 1
        ) {
            pendingSeekRetryCount += 1
            performPlayerSeek(player, targetMs)
            return
        }
        pendingSeekStartedRealtimeMs?.let {
            runtimeSeekLatencyMillis = (SystemClock.elapsedRealtime() - it).toDouble()
        }
        pendingSeekStartedRealtimeMs = null
        runtimeIsBuffering = false
        pendingSeekRetryCount = 0
        pendingSeekTargetMs = null
        applyDesiredPlaybackState(player)
        reportRuntimeState(force = true)
    }

    private fun performPlayerSeek(player: MediaPlayer, targetMs: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            player.seekTo(targetMs.toLong(), MediaPlayer.SEEK_CLOSEST)
        } else {
            player.seekTo(targetMs)
        }
    }

    private fun requestPlayerSeek(
        player: MediaPlayer,
        targetMs: Int,
        startAfterSeek: Boolean,
    ) {
        pendingSeekTargetMs = targetMs
        pendingPlayAfterSeek = startAfterSeek
        pendingSeekRetryCount = 0
        pendingSeekStartedRealtimeMs = SystemClock.elapsedRealtime()
        runtimeIsBuffering = true
        if (player.isPlaying) {
            player.pause()
        }
        performPlayerSeek(player, targetMs)
        reportRuntimeState(force = true)
    }

    private fun applyDesiredPlaybackState(player: MediaPlayer) {
        val shouldPlay = pendingSeekTargetMs == null && (pendingPlayAfterSeek || isCurrentlyPlaying)
        pendingPlayAfterSeek = false
        removeCallbacks(boundaryRunnable)
        if (shouldPlay) {
            if (!player.isPlaying) {
                player.start()
            }
            reportRuntimeState(force = true)
            return
        }
        if (player.isPlaying) {
            player.pause()
        }
        reportRuntimeState(force = true)
    }

    private fun prepareUpcomingSource() {
        val sourceId = upcomingSourceId
        val path = upcomingSourcePath
        val kind = upcomingSourceKind
        if (sourceId.isNullOrBlank() || path.isNullOrBlank() || kind.isNullOrBlank()) {
            releasePreloadedSource()
            return
        }

        if (
            previewSourceMatches(
                sourceId = sourceId,
                sourcePath = path,
                sourceKind = kind,
                sourceStartSeconds = upcomingSourceStartSeconds,
                sourceEndSeconds = upcomingSourceEndSeconds,
                againstId = currentSourceId,
                againstPath = currentSourcePath,
                againstKind = currentSourceKind,
                againstStartSeconds = currentSourceStartSeconds,
                againstEndSeconds = currentSourceEndSeconds,
            )
        ) {
            releasePreloadedSource()
            return
        }

        if (
            previewSourceMatches(
                sourceId = sourceId,
                sourcePath = path,
                sourceKind = kind,
                sourceStartSeconds = upcomingSourceStartSeconds,
                sourceEndSeconds = upcomingSourceEndSeconds,
                againstId = preloadedSourceId,
                againstPath = preloadedSourcePath,
                againstKind = preloadedSourceKind,
                againstStartSeconds = preloadedSourceStartSeconds,
                againstEndSeconds = preloadedSourceEndSeconds,
            )
        ) {
            return
        }

        releasePreloadedSource()
        preloadedSourceId = sourceId
        preloadedSourcePath = path
        preloadedSourceKind = kind
        preloadedSourceStartSeconds = upcomingSourceStartSeconds
        preloadedSourceEndSeconds = upcomingSourceEndSeconds

        when (kind) {
            "video" -> {
                isPreloadedPrepared = false
                preloadedMediaPlayer = buildVideoPlayer(path, muted = true) {
                    preloadedMediaPlayer?.seekTo(
                        (upcomingSourceStartSeconds * 1000.0).roundToInt().coerceAtLeast(0),
                    )
                    isPreloadedPrepared = true
                }
            }

            "image" -> {
                preloadedImageBitmap = BitmapFactory.decodeFile(path)
            }

            else -> {
                releasePreloadedSource()
            }
        }
    }

    private fun takePreloadedPlayerIfMatching(): MediaPlayer? {
        if (
            !previewSourceMatches(
                sourceId = currentSourceId,
                sourcePath = currentSourcePath,
                sourceKind = currentSourceKind,
                sourceStartSeconds = currentSourceStartSeconds,
                sourceEndSeconds = currentSourceEndSeconds,
                againstId = preloadedSourceId,
                againstPath = preloadedSourcePath,
                againstKind = preloadedSourceKind,
                againstStartSeconds = preloadedSourceStartSeconds,
                againstEndSeconds = preloadedSourceEndSeconds,
            )
        ) {
            return null
        }
        val nextPlayer = preloadedMediaPlayer ?: return null
        preloadedMediaPlayer = null
        preloadedImageBitmap = null
        preloadedSourceId = null
        preloadedSourcePath = null
        preloadedSourceKind = null
        preloadedSourceStartSeconds = 0.0
        preloadedSourceEndSeconds = null
        isPreloadedPrepared = false
        return nextPlayer
    }

    private fun takePreloadedImageIfMatching(): Bitmap? {
        if (
            !previewSourceMatches(
                sourceId = currentSourceId,
                sourcePath = currentSourcePath,
                sourceKind = currentSourceKind,
                sourceStartSeconds = currentSourceStartSeconds,
                sourceEndSeconds = currentSourceEndSeconds,
                againstId = preloadedSourceId,
                againstPath = preloadedSourcePath,
                againstKind = preloadedSourceKind,
                againstStartSeconds = preloadedSourceStartSeconds,
                againstEndSeconds = preloadedSourceEndSeconds,
            )
        ) {
            return null
        }
        val nextImage = preloadedImageBitmap
        releasePreloadedSource()
        return nextImage
    }

    private fun releasePreloadedSource() {
        clearPlayerListeners(preloadedMediaPlayer)
        preloadedMediaPlayer?.setVolume(0f, 0f)
        preloadedMediaPlayer?.stopSafely()
        preloadedMediaPlayer?.release()
        preloadedMediaPlayer = null
        preloadedImageBitmap = null
        preloadedSourceId = null
        preloadedSourcePath = null
        preloadedSourceKind = null
        preloadedSourceStartSeconds = 0.0
        preloadedSourceEndSeconds = null
        isPreloadedPrepared = false
    }

    private fun previewSourceMatches(
        sourceId: String?,
        sourcePath: String?,
        sourceKind: String?,
        sourceStartSeconds: Double,
        sourceEndSeconds: Double?,
        againstId: String?,
        againstPath: String?,
        againstKind: String?,
        againstStartSeconds: Double,
        againstEndSeconds: Double?,
    ): Boolean {
        if (
            !sourcePath.isNullOrBlank() &&
            !sourceKind.isNullOrBlank() &&
            !againstPath.isNullOrBlank() &&
            !againstKind.isNullOrBlank()
        ) {
            return sourcePath == againstPath &&
                sourceKind == againstKind &&
                kotlin.math.abs(sourceStartSeconds - againstStartSeconds) <= 0.001 &&
                kotlin.math.abs((sourceEndSeconds ?: 0.0) - (againstEndSeconds ?: 0.0)) <=
                    0.001
        }
        if (!sourceId.isNullOrBlank() && !againstId.isNullOrBlank()) {
            return sourceId == againstId
        }
        return sourceId.isNullOrBlank() &&
            sourcePath.isNullOrBlank() &&
            sourceKind.isNullOrBlank() &&
            againstId.isNullOrBlank() &&
            againstPath.isNullOrBlank() &&
            againstKind.isNullOrBlank()
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
            if (currentBaseClipIds.contains(clipId)) continue

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
                            if (!isCurrentlyPlaying) {
                                (2f * resources.displayMetrics.density).roundToInt()
                            } else {
                                (1f * resources.displayMetrics.density).roundToInt()
                            }
                        } else {
                            (1f * resources.displayMetrics.density).roundToInt()
                        },
                        if (clipId == currentSelectedClipId) {
                            if (!isCurrentlyPlaying) {
                                Color.parseColor("#47E0D4")
                            } else {
                                Color.argb(36, 255, 255, 255)
                            }
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

    private fun noteTransportMutation(expectFrame: Boolean) {
        lastTransportMutationRealtimeMs = SystemClock.elapsedRealtime()
        awaitingPreviewFrame = expectFrame
        if (expectFrame) {
            runtimeFrameReady = false
        } else {
            runtimeFrameReady =
                currentSourceKind == "image" && !currentSourcePath.isNullOrBlank()
            runtimePreviewLatencyMillis = 0.0
        }
    }

    private fun currentProjectPlaybackSeconds(): Double {
        if (currentSourceKind != "video") {
            return currentPositionSeconds.coerceAtLeast(0.0)
        }

        val rawSourcePositionSeconds = when {
            pendingSeekTargetMs != null -> pendingSeekTargetMs!!.toDouble() / 1000.0
            mediaPlayer != null -> mediaPlayer!!.currentPosition.coerceAtLeast(0).toDouble() / 1000.0
            else -> currentSourceStartSeconds
        }
        val relativeToClip = (rawSourcePositionSeconds - currentSourceStartSeconds).coerceAtLeast(0.0)
        val projectPosition = currentClipStartSeconds + relativeToClip
        return currentClipEndSeconds?.let { projectPosition.coerceIn(currentClipStartSeconds, it) }
            ?: projectPosition.coerceAtLeast(0.0)
    }

    private fun reportRuntimeState(force: Boolean = false) {
        val now = SystemClock.elapsedRealtime()
        val minEmitIntervalMs = if (isCurrentlyPlaying) 180L else 33L
        if (!force && now - lastRuntimeEmitRealtimeMs < minEmitIntervalMs) {
            return
        }
        lastRuntimeEmitRealtimeMs = now
        FusionPreviewRegistry.reportRuntimeState(
            projectId = projectId,
            state = FusionPreviewRuntimeState(
                positionSeconds = currentProjectPlaybackSeconds(),
                isPlaying = isCurrentlyPlaying,
                transportRevision = lastAppliedTransportRevision.coerceAtLeast(0),
                isBuffering = runtimeIsBuffering,
                frameReady = runtimeFrameReady,
                frameDropCount = runtimeFrameDropCount,
                audioDropCount = runtimeAudioDropCount,
                bufferUnderrunCount = runtimeBufferUnderrunCount,
                previewLatencyMillis = runtimePreviewLatencyMillis,
                seekLatencyMillis = runtimeSeekLatencyMillis,
            ),
        )
    }

    private fun applyTransport(shouldRetarget: Boolean) {
        val player = mediaPlayer ?: return
        if (!isPrepared) return

        val decision = PreviewTransportPlanner.decide(
            desiredPositionSeconds = currentPositionSeconds,
            sourceStartSeconds = currentSourceStartSeconds,
            sourceEndSeconds = currentSourceEndSeconds,
            playerPositionMs = player.currentPosition,
            isPlaying = isCurrentlyPlaying,
            shouldRetarget = shouldRetarget,
        )
        if (decision.shouldSeek) {
            requestPlayerSeek(
                player = player,
                targetMs = decision.targetPositionMs,
                startAfterSeek = decision.shouldStartAfterSeek,
            )
            return
        }

        pendingSeekTargetMs = null
        pendingPlayAfterSeek = false
        if (decision.shouldStartImmediately) {
            if (!player.isPlaying) {
                player.start()
            }
            removeCallbacks(boundaryRunnable)
        } else if (decision.shouldPauseImmediately && player.isPlaying) {
            player.pause()
            removeCallbacks(boundaryRunnable)
        } else {
            removeCallbacks(boundaryRunnable)
        }
    }

    private fun releasePlayer() {
        clearPlayerListeners(mediaPlayer)
        mediaPlayer?.setVolume(0f, 0f)
        mediaPlayer?.stopSafely()
        mediaPlayer?.release()
        mediaPlayer = null
        isPrepared = false
        pendingSeekTargetMs = null
        pendingPlayAfterSeek = false
        pendingSeekRetryCount = 0
        pendingSeekStartedRealtimeMs = null
        runtimeIsBuffering = false
        runtimeFrameReady = false
        awaitingPreviewFrame = false
        removeCallbacks(boundaryRunnable)
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

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
        val now = SystemClock.elapsedRealtime()
        if (isCurrentlyPlaying && lastFrameRealtimeMs > 0L) {
            val deltaMs = now - lastFrameRealtimeMs
            if (deltaMs >= 120L) {
                runtimeFrameDropCount += ((deltaMs / 33L).toInt() - 1).coerceAtLeast(1)
            }
        }
        lastFrameRealtimeMs = now
        runtimeFrameReady = true
        runtimeIsBuffering = false
        if (awaitingPreviewFrame && lastTransportMutationRealtimeMs > 0L) {
            runtimePreviewLatencyMillis =
                (now - lastTransportMutationRealtimeMs).coerceAtLeast(0L).toDouble()
            awaitingPreviewFrame = false
        }
        reportRuntimeState()
    }

    private fun sceneIdentityKey(): String {
        val overlayNodes = currentSceneNodes.filter {
            val clipId = it["clipId"] as? String
            clipId == null || !currentBaseClipIds.contains(clipId)
        }
        val builder = StringBuilder()
        builder
            .append("pw:")
            .append(currentProjectWidth)
            .append("|ph:")
            .append(currentProjectHeight)
            .append("|count:")
            .append(overlayNodes.size)

        overlayNodes
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
