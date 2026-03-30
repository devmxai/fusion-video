package com.example.fx_flutter_editor.previewengine

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import kotlin.math.max
import kotlin.math.roundToInt

data class ResolvedPreviewConfiguration(
    val projectId: Int,
    val positionSeconds: Double,
    val isPlaying: Boolean,
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
    val continuityKind: String?,
    val sceneNodes: List<Map<String, Any?>>,
    val audioNodes: List<Map<String, Any?>>,
)

data class PreviewTransportCommandEnvelope(
    val projectId: Int,
    val transportRevision: Int,
    val kind: String,
    val positionSeconds: Double?,
    val isPlaying: Boolean?,
)

data class ResolvedPreviewFrameRequest(
    val projectId: Int,
    val transportRevision: Int,
    val transportKind: String?,
    val baseClipId: String?,
    val sourceId: String?,
    val sourcePath: String,
    val sourceKind: String,
    val timelinePositionSeconds: Double,
    val sourcePositionSeconds: Double?,
    val clipStartSeconds: Double,
    val clipEndSeconds: Double?,
    val sourceStartSeconds: Double,
    val sourceEndSeconds: Double?,
    val projectWidth: Int?,
    val projectHeight: Int?,
    val continuityKind: String?,
    val isPlaying: Boolean,
    val frameToken: String,
)

data class ResolvedPreviewAudioRequest(
    val projectId: Int,
    val clipId: String?,
    val sourcePath: String,
    val sourceKind: String,
    val continuityKind: String?,
    val timelinePositionSeconds: Double,
    val sourcePositionSeconds: Double,
    val clipStartSeconds: Double,
    val clipEndSeconds: Double?,
    val sourceStartSeconds: Double,
    val sourceEndSeconds: Double?,
    val gain: Double,
    val isMuted: Boolean,
    val transportRevision: Int,
    val isPlaying: Boolean,
) {
    val sessionKey: String
        get() =
            if (continuityKind == "sameSourceContiguous" && sourceKind != "image") {
                "$projectId|$sourcePath|$sourceKind|continuous"
            } else {
                buildString {
                    append(projectId)
                    append('|')
                    append(sourcePath)
                    append('|')
                    append(sourceKind)
                    append('|')
                    append(sourceStartSeconds)
                    append('|')
                    append(sourceEndSeconds ?: -1.0)
                }
            }
}

internal object PreviewFramePlanner {
    fun clampTimelinePosition(
        configuration: ResolvedPreviewConfiguration?,
        requestedPositionSeconds: Double,
    ): Double {
        val requested = requestedPositionSeconds.coerceAtLeast(0.0)
        configuration ?: return requested
        val clipStart = max(0.0, configuration.clipStartSeconds ?: 0.0)
        val clipEnd = resolveTimelineEnd(configuration)
        return if (clipEnd == null) {
            max(clipStart, requested)
        } else {
            requested.coerceIn(clipStart, clipEnd)
        }
    }

    fun resolveTimelineEnd(configuration: ResolvedPreviewConfiguration): Double? {
        configuration.clipEndSeconds?.let { return it }
        val clipStart = max(0.0, configuration.clipStartSeconds ?: 0.0)
        val sourceStart = max(0.0, configuration.sourceStartSeconds ?: 0.0)
        val sourceEnd = configuration.sourceEndSeconds ?: return null
        return clipStart + max(0.0, sourceEnd - sourceStart)
    }

    fun resolveFrameRequest(
        configuration: ResolvedPreviewConfiguration,
        timelinePositionSeconds: Double,
        isPlaying: Boolean,
        transportRevision: Int,
        transportKind: String?,
    ): ResolvedPreviewFrameRequest? {
        val sourcePath = configuration.sourcePath?.takeIf { it.isNotBlank() } ?: return null
        val sourceKind = configuration.sourceKind?.takeIf { it.isNotBlank() } ?: return null
        val clipStart = max(0.0, configuration.clipStartSeconds ?: 0.0)
        val clipEnd = resolveTimelineEnd(configuration)
        val clampedTimelinePosition =
            if (clipEnd == null) {
                max(clipStart, timelinePositionSeconds)
            } else {
                timelinePositionSeconds.coerceIn(clipStart, clipEnd)
            }
        val sourceStart = max(0.0, configuration.sourceStartSeconds ?: 0.0)
        val sourcePositionSeconds =
            if (sourceKind == "video") {
                val clipLocalSeconds = max(0.0, clampedTimelinePosition - clipStart)
                val requestedSourcePosition = sourceStart + clipLocalSeconds
                configuration.sourceEndSeconds?.let {
                    requestedSourcePosition.coerceAtMost(it)
                } ?: requestedSourcePosition
            } else {
                null
            }
        val frameToken =
            if (sourceKind == "video") {
                val millis = ((sourcePositionSeconds ?: sourceStart) * 1000.0).roundToInt()
                "video:$sourcePath:$millis"
            } else {
                "image:$sourcePath"
            }
        return ResolvedPreviewFrameRequest(
            projectId = configuration.projectId,
            transportRevision = transportRevision,
            transportKind = transportKind,
            baseClipId = configuration.baseClipId,
            sourceId = configuration.sourceId,
            sourcePath = sourcePath,
            sourceKind = sourceKind,
            timelinePositionSeconds = clampedTimelinePosition,
            sourcePositionSeconds = sourcePositionSeconds,
            clipStartSeconds = clipStart,
            clipEndSeconds = clipEnd,
            sourceStartSeconds = sourceStart,
            sourceEndSeconds = configuration.sourceEndSeconds,
            projectWidth = configuration.projectWidth,
            projectHeight = configuration.projectHeight,
            continuityKind = configuration.continuityKind,
            isPlaying = isPlaying,
            frameToken = frameToken,
        )
    }
}

internal object PreviewAudioPlanner {
    fun resolveAudioRequest(
        configuration: ResolvedPreviewConfiguration,
        timelinePositionSeconds: Double,
        transportRevision: Int,
        isPlaying: Boolean,
    ): ResolvedPreviewAudioRequest? {
        val activeRequests =
            configuration.audioNodes.mapNotNull { node ->
                resolveAudioNode(
                    configuration = configuration,
                    node = node,
                    timelinePositionSeconds = timelinePositionSeconds,
                    transportRevision = transportRevision,
                    isPlaying = isPlaying,
                )
            }
        if (activeRequests.isEmpty()) {
            return null
        }
        return activeRequests.maxWithOrNull(
            compareBy<ResolvedPreviewAudioRequest>(
                { audioPriority(configuration, it) },
                { it.clipStartSeconds },
                { it.sourceStartSeconds },
            ),
        )
    }

    private fun resolveAudioNode(
        configuration: ResolvedPreviewConfiguration,
        node: Map<String, Any?>,
        timelinePositionSeconds: Double,
        transportRevision: Int,
        isPlaying: Boolean,
    ): ResolvedPreviewAudioRequest? {
        val sourcePath = (node["localPath"] as? String)?.takeIf { it.isNotBlank() } ?: return null
        val sourceKind = (node["kind"] as? String)?.takeIf { it.isNotBlank() } ?: return null
        val clipStartSeconds = max(0.0, (node["clipStartSeconds"] as? Number)?.toDouble() ?: 0.0)
        val clipEndSeconds = (node["clipEndSeconds"] as? Number)?.toDouble()
        if (timelinePositionSeconds + AUDIO_EPSILON < clipStartSeconds) {
            return null
        }
        if (clipEndSeconds != null && timelinePositionSeconds > clipEndSeconds + AUDIO_EPSILON) {
            return null
        }
        val sourceStartSeconds =
            max(0.0, (node["sourceStartSeconds"] as? Number)?.toDouble() ?: 0.0)
        val sourceEndSeconds = (node["sourceEndSeconds"] as? Number)?.toDouble()
        val clipLocalSeconds = max(0.0, timelinePositionSeconds - clipStartSeconds)
        val sourcePositionSeconds =
            sourceEndSeconds?.let { (sourceStartSeconds + clipLocalSeconds).coerceAtMost(it) }
                ?: (sourceStartSeconds + clipLocalSeconds)
        return ResolvedPreviewAudioRequest(
            projectId = configuration.projectId,
            clipId = node["clipId"] as? String,
            sourcePath = sourcePath,
            sourceKind = sourceKind,
            continuityKind = configuration.continuityKind,
            timelinePositionSeconds = timelinePositionSeconds.coerceAtLeast(0.0),
            sourcePositionSeconds = sourcePositionSeconds.coerceAtLeast(0.0),
            clipStartSeconds = clipStartSeconds,
            clipEndSeconds = clipEndSeconds,
            sourceStartSeconds = sourceStartSeconds,
            sourceEndSeconds = sourceEndSeconds,
            gain = (node["gain"] as? Number)?.toDouble() ?: 1.0,
            isMuted = node["isMuted"] as? Boolean ?: false,
            transportRevision = transportRevision,
            isPlaying = isPlaying,
        )
    }

    private fun audioPriority(
        configuration: ResolvedPreviewConfiguration,
        request: ResolvedPreviewAudioRequest,
    ): Int {
        return when {
            request.clipId != null &&
                request.clipId == configuration.baseClipId &&
                request.sourceKind == "video" -> 500
            request.clipId != null &&
                configuration.baseClipIds.contains(request.clipId) &&
                request.sourceKind == "video" -> 400
            request.sourceKind == "video" -> 300
            request.sourceKind == "audio" -> 200
            else -> 100
        }
    }

    private const val AUDIO_EPSILON = 0.0005
}

class FusionAndroidPreviewEngine(
    val mediaIo: AndroidMediaIo = AndroidMediaIo(),
    val decodeScheduler: AndroidDecodeScheduler = AndroidDecodeScheduler(),
    val renderer: AndroidPreviewRenderer = AndroidPreviewRenderer(),
    val audioEngine: AndroidAudioEngine = AndroidAudioEngine(),
    val exportPipeline: AndroidExportPipeline = AndroidExportPipeline(),
) {
    interface Output {
        fun onFrameRequest(frameRequest: ResolvedPreviewFrameRequest?)
    }

    private data class PreviewSession(
        val projectId: Int,
        var configuration: ResolvedPreviewConfiguration? = null,
        var currentTimelinePositionSeconds: Double = 0.0,
        var isPlaying: Boolean = false,
        var transportRevision: Int = 0,
        var lastTransportKind: String? = null,
        var playbackAnchorRealtimeMs: Long = 0L,
        var playbackAnchorPositionSeconds: Double = 0.0,
        var tickScheduled: Boolean = false,
        var lastEmittedFrameRequest: ResolvedPreviewFrameRequest? = null,
        var lastFrameEmitRealtimeMs: Long = 0L,
        val outputs: MutableSet<Output> = linkedSetOf(),
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val sessions = linkedMapOf<Int, PreviewSession>()
    val isScaffoldReady: Boolean = true
    var lastConfiguration: ResolvedPreviewConfiguration? = null
        private set
    var lastCommand: PreviewTransportCommandEnvelope? = null
        private set

    fun attachOutput(projectId: Int, output: Output) {
        val session = sessionFor(projectId)
        session.outputs.add(output)
        emitFrameRequest(session, force = true)
        if (session.isPlaying) {
            schedulePlaybackTick(projectId)
        }
    }

    fun detachOutput(projectId: Int, output: Output) {
        val session = sessions[projectId] ?: return
        session.outputs.remove(output)
        if (session.outputs.isEmpty()) {
            session.tickScheduled = false
        }
    }

    fun configure(configuration: ResolvedPreviewConfiguration) {
        lastConfiguration = configuration
        val session = sessionFor(configuration.projectId)
        session.configuration = configuration
        session.currentTimelinePositionSeconds =
            PreviewFramePlanner.clampTimelinePosition(
                configuration,
                configuration.positionSeconds,
            )
        session.transportRevision = configuration.transportRevision
        session.lastTransportKind = if (configuration.isPlaying) "play" else "configure"
        session.isPlaying = configuration.isPlaying
        if (session.isPlaying) {
            startPlaybackClock(session)
        } else {
            stopPlaybackClock(session)
        }
        emitFrameRequest(session, force = true)
    }

    fun dispatch(command: PreviewTransportCommandEnvelope) {
        lastCommand = command
        val session = sessionFor(command.projectId)
        val configuration = session.configuration
        session.transportRevision = command.transportRevision
        session.lastTransportKind = command.kind
        val targetTimelinePosition =
            PreviewFramePlanner.clampTimelinePosition(
                configuration,
                command.positionSeconds ?: session.currentTimelinePositionSeconds,
            )
        when (command.kind) {
            "play" -> {
                session.currentTimelinePositionSeconds = targetTimelinePosition
                session.isPlaying = true
                startPlaybackClock(session)
            }

            "pause" -> {
                session.currentTimelinePositionSeconds = targetTimelinePosition
                session.isPlaying = false
                stopPlaybackClock(session)
            }

            "seek" -> {
                session.currentTimelinePositionSeconds = targetTimelinePosition
                session.isPlaying = command.isPlaying ?: session.isPlaying
                if (session.isPlaying) {
                    startPlaybackClock(session)
                } else {
                    stopPlaybackClock(session)
                }
            }

            "scrubBegin",
            "scrubUpdate",
            -> {
                session.currentTimelinePositionSeconds = targetTimelinePosition
                session.isPlaying = false
                stopPlaybackClock(session)
            }

            "scrubEnd" -> {
                session.currentTimelinePositionSeconds = targetTimelinePosition
                session.isPlaying = command.isPlaying ?: false
                if (session.isPlaying) {
                    startPlaybackClock(session)
                } else {
                    stopPlaybackClock(session)
                }
            }

            else -> {
                session.currentTimelinePositionSeconds = targetTimelinePosition
            }
        }
        emitFrameRequest(session, force = true)
    }

    fun sceneNodeForClip(
        projectId: Int,
        clipId: String?,
    ): Map<String, Any?>? {
        if (clipId.isNullOrBlank()) {
            return null
        }
        return sessions[projectId]
            ?.configuration
            ?.sceneNodes
            ?.lastOrNull { node -> (node["clipId"] as? String) == clipId }
    }

    fun audioRequestForProject(projectId: Int): ResolvedPreviewAudioRequest? {
        val session = sessions[projectId] ?: return null
        val configuration = session.configuration ?: return null
        return PreviewAudioPlanner.resolveAudioRequest(
            configuration = configuration,
            timelinePositionSeconds = session.currentTimelinePositionSeconds,
            transportRevision = session.transportRevision,
            isPlaying = session.isPlaying,
        )
    }

    fun upcomingWarmupFrameRequestForProject(projectId: Int): ResolvedPreviewFrameRequest? {
        val session = sessions[projectId] ?: return null
        val configuration = session.configuration ?: return null
        val sourcePath = configuration.upcomingSourcePath?.takeIf { it.isNotBlank() } ?: return null
        val sourceKind = configuration.upcomingSourceKind?.takeIf { it.isNotBlank() } ?: return null
        val sourceStartSeconds = max(0.0, configuration.upcomingSourceStartSeconds ?: 0.0)
        val sourcePositionSeconds =
            if (sourceKind == "video") {
                configuration.upcomingSourceStartSeconds ?: 0.0
            } else {
                null
            }
        val frameToken =
            if (sourceKind == "video") {
                val millis = ((sourcePositionSeconds ?: sourceStartSeconds) * 1000.0).roundToInt()
                "video:$sourcePath:$millis"
            } else {
                "image:$sourcePath"
            }
        return ResolvedPreviewFrameRequest(
            projectId = configuration.projectId,
            transportRevision = session.transportRevision,
            transportKind = "upcomingWarmup",
            baseClipId = configuration.baseClipId,
            sourceId = configuration.upcomingSourceId,
            sourcePath = sourcePath,
            sourceKind = sourceKind,
            timelinePositionSeconds = session.currentTimelinePositionSeconds,
            sourcePositionSeconds = sourcePositionSeconds,
            clipStartSeconds = session.currentTimelinePositionSeconds,
            clipEndSeconds = null,
            sourceStartSeconds = sourceStartSeconds,
            sourceEndSeconds = configuration.upcomingSourceEndSeconds,
            projectWidth = configuration.projectWidth,
            projectHeight = configuration.projectHeight,
            continuityKind = configuration.continuityKind,
            isPlaying = false,
            frameToken = frameToken,
        )
    }

    fun syncRenderedTimelinePosition(
        projectId: Int,
        timelinePositionSeconds: Double,
        isPlaying: Boolean,
    ) {
        val session = sessions[projectId] ?: return
        val configuration = session.configuration ?: return
        val clampedTimelinePosition =
            PreviewFramePlanner.clampTimelinePosition(configuration, timelinePositionSeconds)
        session.currentTimelinePositionSeconds = clampedTimelinePosition
        session.isPlaying = isPlaying
        if (isPlaying) {
            session.playbackAnchorRealtimeMs = SystemClock.elapsedRealtime()
            session.playbackAnchorPositionSeconds = clampedTimelinePosition
            session.lastTransportKind = "playbackTick"
        } else {
            stopPlaybackClock(session)
            session.lastTransportKind = "pause"
        }
    }

    private fun sessionFor(projectId: Int): PreviewSession =
        sessions.getOrPut(projectId) { PreviewSession(projectId = projectId) }

    private fun startPlaybackClock(session: PreviewSession) {
        session.playbackAnchorRealtimeMs = SystemClock.elapsedRealtime()
        session.playbackAnchorPositionSeconds = session.currentTimelinePositionSeconds
        schedulePlaybackTick(session.projectId)
    }

    private fun stopPlaybackClock(session: PreviewSession) {
        session.playbackAnchorRealtimeMs = 0L
        session.playbackAnchorPositionSeconds = session.currentTimelinePositionSeconds
    }

    private fun schedulePlaybackTick(projectId: Int) {
        val session = sessions[projectId] ?: return
        if (session.tickScheduled) {
            return
        }
        session.tickScheduled = true
        mainHandler.postDelayed(
            {
                session.tickScheduled = false
                advancePlayback(projectId)
            },
            PLAYBACK_TICK_MS,
        )
    }

    private fun advancePlayback(projectId: Int) {
        val session = sessions[projectId] ?: return
        if (!session.isPlaying) {
            emitFrameRequest(session)
            return
        }
        val configuration = session.configuration ?: return
        val elapsedSeconds =
            (SystemClock.elapsedRealtime() - session.playbackAnchorRealtimeMs).toDouble() / 1000.0
        val requestedTimelinePosition =
            session.playbackAnchorPositionSeconds + elapsedSeconds
        val clampedTimelinePosition =
            PreviewFramePlanner.clampTimelinePosition(configuration, requestedTimelinePosition)
        session.currentTimelinePositionSeconds = clampedTimelinePosition
        val clipEnd = PreviewFramePlanner.resolveTimelineEnd(configuration)
        val reachedEnd =
            clipEnd != null && clampedTimelinePosition >= clipEnd - 0.0005
        if (reachedEnd) {
            session.isPlaying = false
            stopPlaybackClock(session)
        }
        emitFrameRequest(session)
        if (!reachedEnd && session.isPlaying) {
            schedulePlaybackTick(projectId)
        }
    }

    private fun emitFrameRequest(
        session: PreviewSession,
        force: Boolean = false,
    ) {
        val configuration = session.configuration
        val frameRequest =
            configuration?.let {
                PreviewFramePlanner.resolveFrameRequest(
                    configuration = it,
                    timelinePositionSeconds = session.currentTimelinePositionSeconds,
                    isPlaying = session.isPlaying,
                    transportRevision = session.transportRevision,
                    transportKind = session.lastTransportKind,
                )
            }
        val nowRealtimeMs = SystemClock.elapsedRealtime()
        if (
            !PreviewFrameEmissionPlanner.shouldEmit(
                previous = session.lastEmittedFrameRequest,
                current = frameRequest,
                nowRealtimeMs = nowRealtimeMs,
                lastEmitRealtimeMs = session.lastFrameEmitRealtimeMs,
                force = force,
            )
        ) {
            return
        }
        session.lastEmittedFrameRequest = frameRequest
        session.lastFrameEmitRealtimeMs = nowRealtimeMs
        session.outputs.forEach { it.onFrameRequest(frameRequest) }
    }

    private companion object {
        private const val PLAYBACK_TICK_MS = 16L
    }

}
