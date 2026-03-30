package com.example.fx_flutter_editor

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.SystemClock
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import com.example.fx_flutter_editor.previewengine.AndroidCodecVideoSession
import com.example.fx_flutter_editor.previewengine.AudioClockDriftPlanner
import com.example.fx_flutter_editor.previewengine.DecodedPreviewFrameResult
import com.example.fx_flutter_editor.previewengine.FusionAndroidPreviewEngine
import com.example.fx_flutter_editor.previewengine.PreviewContentLayout
import com.example.fx_flutter_editor.previewengine.PreviewContentFitMode
import com.example.fx_flutter_editor.previewengine.PreviewGlSurfaceView
import com.example.fx_flutter_editor.previewengine.PreviewLayoutPlanner
import com.example.fx_flutter_editor.previewengine.PreviewNodeLayout
import com.example.fx_flutter_editor.previewengine.PlaybackContinuityPlanner
import com.example.fx_flutter_editor.previewengine.ResolvedPreviewFrameRequest
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class FusionEnginePreviewViewFactory(
    private val previewEngine: FusionAndroidPreviewEngine,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val projectId = ((args as? Map<*, *>)?.get("projectId") as? Number)?.toInt() ?: viewId
        return FusionEnginePreviewPlatformView(context, projectId, previewEngine)
    }
}

private class FusionEnginePreviewPlatformView(
    context: Context,
    projectId: Int,
    previewEngine: FusionAndroidPreviewEngine,
) : PlatformView {
    private val nativeView = FusionEnginePreviewNativeView(context, projectId, previewEngine)

    override fun getView(): View = nativeView

    override fun dispose() {
        nativeView.dispose()
    }
}

private class FusionEnginePreviewNativeView(
    context: Context,
    private val projectId: Int,
    private val previewEngine: FusionAndroidPreviewEngine,
) : FrameLayout(context), FusionAndroidPreviewEngine.Output, AndroidCodecVideoSession.Listener {
    private val videoContainer =
        FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
            clipChildren = true
            visibility = View.VISIBLE
        }
    private val videoSurfaceView = SurfaceView(context)
    private val rendererContainer =
        FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
            clipChildren = true
            visibility = View.VISIBLE
        }
    private val rendererView: PreviewGlSurfaceView = previewEngine.renderer.createView(context)
    private val videoSession = AndroidCodecVideoSession(this)
    private var lastRenderedRendererRequestKey: String? = null
    private var lastFrameRequest: ResolvedPreviewFrameRequest? = null
    private var lastPlayingFrameRequest: ResolvedPreviewFrameRequest? = null
    private var pendingRendererHandoffRequestKey: String? = null
    private var activePlaybackSessionKey: String? = null
    private var activeAudioSessionKey: String? = null
    private var audioWasPlaying: Boolean = false
    private var lastAudioSyncRealtimeMs: Long = 0L
    private var lastVideoPlaybackStartRealtimeMs: Long = 0L
    private var isCodecFrameReady: Boolean = false
    private var lastAppliedLayoutKey: String? = null
    private var lastPlaybackWarmKey: String? = null
    private var lastUpcomingWarmFrameToken: String? = null
    private var frameDropCount: Int = 0
    private var bufferUnderrunCount: Int = 0
    private var lastSeekLatencyMillis: Double = 0.0
    private var lastRuntimeEmitRealtimeMs: Long = 0L

    init {
        setBackgroundColor(Color.BLACK)
        videoSurfaceView.apply {
            visibility = View.VISIBLE
            setZOrderOnTop(false)
            setZOrderMediaOverlay(false)
            holder.setFormat(PixelFormat.OPAQUE)
            holder.addCallback(
                object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) {
                        videoSession.attachSurface(holder.surface)
                        lastPlayingFrameRequest?.let {
                            videoSession.play(it, playbackSessionKey(it))
                        }
                    }

                    override fun surfaceChanged(
                        holder: SurfaceHolder,
                        format: Int,
                        width: Int,
                        height: Int,
                    ) {
                        videoSession.attachSurface(holder.surface)
                    }

                    override fun surfaceDestroyed(holder: SurfaceHolder) {
                        videoSession.attachSurface(null)
                    }
                },
            )
        }
        videoContainer.addView(
            videoSurfaceView,
            LayoutParams(1, 1).apply {
                gravity = Gravity.CENTER
            },
        )
        rendererContainer.addView(
            rendererView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        addView(
            videoContainer,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.CENTER
            },
        )
        addView(
            rendererContainer,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        previewEngine.attachOutput(projectId, this)
    }

    override fun onFrameRequest(frameRequest: ResolvedPreviewFrameRequest?) {
        if (frameRequest == null) {
            previewEngine.audioEngine.stop()
            activeAudioSessionKey = null
            audioWasPlaying = false
            lastAudioSyncRealtimeMs = 0L
            lastFrameRequest = null
            lastPlayingFrameRequest = null
            pendingRendererHandoffRequestKey = null
            activePlaybackSessionKey = null
            isCodecFrameReady = false
            lastAppliedLayoutKey = null
            lastPlaybackWarmKey = null
            lastUpcomingWarmFrameToken = null
            lastVideoPlaybackStartRealtimeMs = 0L
            videoSession.stopPlayback()
            showRendererOnly()
            lastRenderedRendererRequestKey = null
            rendererView.clearFrame()
            reportRuntimeState(
                frameRequest = null,
                isBuffering = false,
                frameReady = false,
                previewLatencyMillis = 0.0,
                seekLatencyMillis = lastSeekLatencyMillis,
            )
            return
        }

        lastFrameRequest = frameRequest
        syncAudio(frameRequest)
        if (frameRequest.sourceKind == "video" && frameRequest.isPlaying) {
            pendingRendererHandoffRequestKey = null
            val nextPlaybackSessionKey = playbackSessionKey(frameRequest)
            val nowRealtimeMs = SystemClock.elapsedRealtime()
            val isSamePlaybackSession = nextPlaybackSessionKey == activePlaybackSessionKey
            val previousPlayingFrameRequest = lastPlayingFrameRequest
            val targetSourcePositionSeconds =
                frameRequest.sourcePositionSeconds ?: frameRequest.sourceStartSeconds
            val isWithinVideoStartupGrace =
                isSamePlaybackSession &&
                    !isCodecFrameReady &&
                    lastVideoPlaybackStartRealtimeMs > 0L &&
                    nowRealtimeMs - lastVideoPlaybackStartRealtimeMs < VIDEO_STARTUP_GRACE_MS
            val canResumePlayback =
                videoSession.canResume(
                    sessionKey = nextPlaybackSessionKey,
                    targetSourcePositionSeconds = targetSourcePositionSeconds,
                )
            val isPausedPlaybackSession =
                videoSession.isPausedForSession(nextPlaybackSessionKey)
            val shouldRetargetPlayback =
                isSamePlaybackSession &&
                    !isWithinVideoStartupGrace &&
                    !isPausedPlaybackSession &&
                    videoSession.shouldRetargetPlayback(
                        sessionKey = nextPlaybackSessionKey,
                        continuityKind = frameRequest.continuityKind,
                        targetSourcePositionSeconds = targetSourcePositionSeconds,
                    )
            val canBypassSteadyPlaybackTick =
                isSamePlaybackSession &&
                    !canResumePlayback &&
                    !isPausedPlaybackSession &&
                    !shouldRetargetPlayback &&
                    isCodecFrameReady &&
                    previousPlayingFrameRequest != null &&
                    sameSteadyPlaybackWindow(
                        previous = previousPlayingFrameRequest,
                        current = frameRequest,
                    )
            val isWaitingForFirstCodecFrame =
                isWithinVideoStartupGrace &&
                    !canResumePlayback &&
                    !isPausedPlaybackSession &&
                    !shouldRetargetPlayback
            lastPlayingFrameRequest = frameRequest
            if (canBypassSteadyPlaybackTick) {
                showVideoOnly()
                prewarmUpcomingSourceFrame(frameRequest)
                return
            }
            if (isWaitingForFirstCodecFrame) {
                showRendererOnly()
                prewarmUpcomingSourceFrame(frameRequest)
                return
            }
            updateBaseVisualLayout(frameRequest)
            if (!isSamePlaybackSession) {
                activePlaybackSessionKey = nextPlaybackSessionKey
                isCodecFrameReady = false
                lastVideoPlaybackStartRealtimeMs = nowRealtimeMs
                showRendererOnly()
                warmCurrentPlaybackFrame(frameRequest)
                videoSession.play(frameRequest, nextPlaybackSessionKey)
                reportRuntimeState(
                    frameRequest = frameRequest,
                    isBuffering = true,
                    frameReady = lastRenderedRendererRequestKey != null,
                    previewLatencyMillis = 0.0,
                    seekLatencyMillis = lastSeekLatencyMillis,
                    force = true,
                )
            } else if (canResumePlayback) {
                videoSession.resumePlayback()
                if (isCodecFrameReady) {
                    showVideoOnly()
                } else {
                    showRendererOnly()
                    warmCurrentPlaybackFrame(frameRequest)
                }
                reportRuntimeState(
                    frameRequest = frameRequest,
                    isBuffering = !isCodecFrameReady,
                    frameReady = isCodecFrameReady || lastRenderedRendererRequestKey != null,
                    previewLatencyMillis = 0.0,
                    seekLatencyMillis = lastSeekLatencyMillis,
                    force = true,
                )
            } else if (isPausedPlaybackSession) {
                isCodecFrameReady = false
                lastVideoPlaybackStartRealtimeMs = nowRealtimeMs
                showRendererOnly()
                warmCurrentPlaybackFrame(frameRequest)
                videoSession.play(frameRequest, nextPlaybackSessionKey)
                reportRuntimeState(
                    frameRequest = frameRequest,
                    isBuffering = true,
                    frameReady = lastRenderedRendererRequestKey != null,
                    previewLatencyMillis = 0.0,
                    seekLatencyMillis = lastSeekLatencyMillis,
                    force = true,
                )
            } else if (shouldRetargetPlayback) {
                isCodecFrameReady = false
                lastVideoPlaybackStartRealtimeMs = nowRealtimeMs
                showRendererOnly()
                warmCurrentPlaybackFrame(frameRequest)
                videoSession.play(frameRequest, nextPlaybackSessionKey)
                reportRuntimeState(
                    frameRequest = frameRequest,
                    isBuffering = true,
                    frameReady = lastRenderedRendererRequestKey != null,
                    previewLatencyMillis = 0.0,
                    seekLatencyMillis = lastSeekLatencyMillis,
                    force = true,
                )
            } else if (isCodecFrameReady) {
                showVideoOnly()
            } else {
                showRendererOnly()
            }
            prewarmUpcomingSourceFrame(frameRequest)
            return
        }

        lastPlayingFrameRequest = null
        val pausedPlaybackSessionKey =
            if (frameRequest.sourceKind == "video") {
                playbackSessionKey(frameRequest)
            } else {
                null
            }
        val shouldKeepPausedPlaybackSession =
            pausedPlaybackSessionKey != null &&
                activePlaybackSessionKey == pausedPlaybackSessionKey
        val shouldHoldVideoUntilRendererReady =
            videoContainer.visibility == View.VISIBLE &&
                frameRequest.sourceKind == "video" &&
                frameRequest.frameToken.isNotBlank()
        isCodecFrameReady = false
        if (shouldKeepPausedPlaybackSession) {
            activePlaybackSessionKey = pausedPlaybackSessionKey
            videoSession.pausePlayback()
        } else {
            activePlaybackSessionKey = null
            videoSession.stopPlayback()
        }
        if (shouldHoldVideoUntilRendererReady) {
            pendingRendererHandoffRequestKey = rendererRequestKey(frameRequest)
            holdVideoUntilRendererReady()
        } else {
            pendingRendererHandoffRequestKey = null
            showRendererOnly()
        }
        updateBaseVisualLayout(frameRequest)

        if (rendererRequestKey(frameRequest) == lastRenderedRendererRequestKey) {
            pendingRendererHandoffRequestKey = null
            showRendererOnly()
            reportRuntimeState(
                frameRequest = frameRequest,
                isBuffering = false,
                frameReady = true,
                previewLatencyMillis = 0.0,
                seekLatencyMillis = lastSeekLatencyMillis,
            )
            return
        }

        bufferUnderrunCount += 1
        if (
            frameRequest.transportKind == "seek" ||
                frameRequest.transportKind == "scrubBegin" ||
                frameRequest.transportKind == "scrubUpdate" ||
                frameRequest.transportKind == "scrubEnd"
        ) {
            previewEngine.decodeScheduler.cancelProjectPrefetch(projectId)
        }
        reportRuntimeState(
            frameRequest = frameRequest,
            isBuffering = true,
            frameReady = lastRenderedRendererRequestKey != null,
            previewLatencyMillis = 0.0,
            seekLatencyMillis = lastSeekLatencyMillis,
        )

        val targetWidth = resolveTargetWidth(frameRequest)
        val targetHeight = resolveTargetHeight(frameRequest)

        previewEngine.decodeScheduler.requestFrame(
            mediaIo = previewEngine.mediaIo,
            frameRequest = frameRequest,
            targetWidth = targetWidth,
            targetHeight = targetHeight,
            onFrameDecoded = ::handleDecodedFrame,
        )
    }

    private fun showRendererOnly() {
        setVisibility(videoContainer, View.VISIBLE)
        setVisibility(rendererContainer, View.VISIBLE)
    }

    private fun showVideoOnly() {
        setVisibility(videoContainer, View.VISIBLE)
        setVisibility(rendererContainer, View.GONE)
    }

    private fun holdVideoUntilRendererReady() {
        setVisibility(videoContainer, View.VISIBLE)
        setVisibility(rendererContainer, View.GONE)
    }

    private fun setVisibility(
        view: View,
        visibility: Int,
    ) {
        if (view.visibility != visibility) {
            view.visibility = visibility
        }
    }

    fun dispose() {
        previewEngine.detachOutput(projectId, this)
        previewEngine.decodeScheduler.cancelProject(projectId)
        previewEngine.audioEngine.stop()
        videoSession.dispose()
        rendererView.dispose()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        lastFrameRequest?.let {
            updateBaseVisualLayout(it, force = true)
        }
    }

    private fun resolveTargetWidth(frameRequest: ResolvedPreviewFrameRequest): Int {
        return when {
            width > 0 -> width
            frameRequest.projectWidth != null && frameRequest.projectWidth > 0 -> frameRequest.projectWidth
            else -> 960
        }
    }

    private fun resolveTargetHeight(frameRequest: ResolvedPreviewFrameRequest): Int {
        return when {
            height > 0 -> height
            frameRequest.projectHeight != null && frameRequest.projectHeight > 0 -> frameRequest.projectHeight
            else -> 540
        }
    }

    private fun handleDecodedFrame(result: DecodedPreviewFrameResult) {
        if (result.isStale) {
            frameDropCount += result.droppedFrameCount
            return
        }
        if (!result.frameRequest.isPlaying) {
            lastSeekLatencyMillis = result.previewLatencyMillis
        }
        val requestKey = rendererRequestKey(result.frameRequest)
        lastRenderedRendererRequestKey = requestKey
        val descriptor = previewEngine.mediaIo.inspectVideoStream(result.frameRequest.sourcePath)
        rendererView.submitFrame(
            bitmap = result.bitmap,
            contentWidth =
                descriptor?.displayWidth
                    ?: result.bitmap?.width
                    ?: resolveTargetWidth(result.frameRequest),
            contentHeight =
                descriptor?.displayHeight
                    ?: result.bitmap?.height
                    ?: resolveTargetHeight(result.frameRequest),
            fitMode = resolveContentFitMode(result.frameRequest),
        )
        if (pendingRendererHandoffRequestKey == requestKey) {
            pendingRendererHandoffRequestKey = null
            showRendererOnly()
        }
        reportRuntimeState(
            frameRequest = result.frameRequest,
            isBuffering = false,
            frameReady = result.bitmap != null,
            previewLatencyMillis = result.previewLatencyMillis,
            seekLatencyMillis = lastSeekLatencyMillis,
            force = !result.frameRequest.isPlaying,
        )
    }

    private fun warmCurrentPlaybackFrame(frameRequest: ResolvedPreviewFrameRequest) {
        val warmKey = playbackWarmKey(frameRequest)
        if (lastPlaybackWarmKey == warmKey) {
            return
        }
        lastPlaybackWarmKey = warmKey
        previewEngine.decodeScheduler.requestFrame(
            mediaIo = previewEngine.mediaIo,
            frameRequest = frameRequest.copy(isPlaying = false),
            targetWidth = resolveTargetWidth(frameRequest),
            targetHeight = resolveTargetHeight(frameRequest),
            onFrameDecoded = ::handleDecodedFrame,
        )
    }

    private fun prewarmUpcomingSourceFrame(frameRequest: ResolvedPreviewFrameRequest) {
        if (
            frameRequest.continuityKind != "differentSource" &&
                frameRequest.continuityKind != "videoToImage"
        ) {
            return
        }
        val upcomingFrameRequest = previewEngine.upcomingWarmupFrameRequestForProject(projectId) ?: return
        if (lastUpcomingWarmFrameToken == upcomingFrameRequest.frameToken) {
            return
        }
        lastUpcomingWarmFrameToken = upcomingFrameRequest.frameToken
        previewEngine.decodeScheduler.prefetchFrame(
            mediaIo = previewEngine.mediaIo,
            frameRequest = upcomingFrameRequest,
            targetWidth = resolveTargetWidth(frameRequest),
            targetHeight = resolveTargetHeight(frameRequest),
        )
    }

    private fun playbackWarmKey(frameRequest: ResolvedPreviewFrameRequest): String {
        return if (frameRequest.isPlaying) {
            val playbackSessionKey = playbackSessionKey(frameRequest)
            "play:$playbackSessionKey:${frameRequest.transportRevision}"
        } else {
            "still:${frameRequest.frameToken}"
        }
    }

    private fun rendererRequestKey(frameRequest: ResolvedPreviewFrameRequest): String {
        return buildString {
            append(frameRequest.frameToken)
            append('|')
            append(frameRequest.transportRevision)
            append('|')
            append(frameRequest.transportKind ?: "unknown")
            append('|')
            append(frameRequest.projectWidth ?: 0)
            append('x')
            append(frameRequest.projectHeight ?: 0)
        }
    }

    private fun sameSteadyPlaybackWindow(
        previous: ResolvedPreviewFrameRequest,
        current: ResolvedPreviewFrameRequest,
    ): Boolean {
        return previous.sourceId == current.sourceId &&
            previous.sourcePath == current.sourcePath &&
            previous.sourceKind == current.sourceKind &&
            previous.continuityKind == current.continuityKind &&
            previous.clipStartSeconds == current.clipStartSeconds &&
            previous.clipEndSeconds == current.clipEndSeconds &&
            previous.sourceStartSeconds == current.sourceStartSeconds &&
            previous.sourceEndSeconds == current.sourceEndSeconds &&
            previous.projectWidth == current.projectWidth &&
            previous.projectHeight == current.projectHeight &&
            previous.transportRevision == current.transportRevision
    }

    private fun updateBaseVisualLayout(
        frameRequest: ResolvedPreviewFrameRequest,
        force: Boolean = false,
    ) {
        val descriptor = previewEngine.mediaIo.inspectVideoStream(frameRequest.sourcePath)
        val parentWidth = width
        val parentHeight = height
        if (parentWidth <= 0 || parentHeight <= 0) {
            return
        }
        val sceneNode = previewEngine.sceneNodeForClip(projectId, frameRequest.baseClipId)
        val projectWidth = frameRequest.projectWidth ?: parentWidth
        val projectHeight = frameRequest.projectHeight ?: parentHeight
        val nodeLayout =
            PreviewLayoutPlanner.resolveNodeLayout(
                parentWidth = parentWidth,
                parentHeight = parentHeight,
                projectWidth = projectWidth,
                projectHeight = projectHeight,
                sceneNode = sceneNode,
            )
        val videoContentLayout =
            PreviewLayoutPlanner.resolveContentLayout(
                containerWidth = nodeLayout.width,
                containerHeight = nodeLayout.height,
                mediaWidth = descriptor?.displayWidth ?: descriptor?.width,
                mediaHeight = descriptor?.displayHeight ?: descriptor?.height,
                mediaRotationDegrees = descriptor?.rotationDegrees ?: 0,
                fitMode = resolveContentFitMode(frameRequest, sceneNode, projectWidth, projectHeight),
            )
        val layoutKey =
            buildString {
                append(nodeLayout.left)
                append('|')
                append(nodeLayout.top)
                append('|')
                append(nodeLayout.width)
                append('|')
                append(nodeLayout.height)
                append('|')
                append(nodeLayout.rotationDegrees)
                append('|')
                append(nodeLayout.opacity)
                append('|')
                append(videoContentLayout.left)
                append('|')
                append(videoContentLayout.top)
                append('|')
                append(videoContentLayout.width)
                append('|')
                append(videoContentLayout.height)
                append('|')
                append(videoContentLayout.rotationDegrees)
            }
        if (!force && layoutKey == lastAppliedLayoutKey) {
            return
        }
        lastAppliedLayoutKey = layoutKey

        applyNodeLayout(videoContainer, nodeLayout)
        applyNodeLayout(rendererContainer, nodeLayout)
        applyContentLayout(videoSurfaceView, videoContentLayout)
        applyRendererLayout(rendererView)
    }

    private fun applyNodeLayout(
        view: View,
        layout: PreviewNodeLayout,
    ) {
        val params =
            LayoutParams(layout.width, layout.height).apply {
                leftMargin = layout.left
                topMargin = layout.top
            }
        view.layoutParams = params
        view.pivotX = layout.width / 2f
        view.pivotY = layout.height / 2f
        view.rotation = layout.rotationDegrees
        view.alpha = layout.opacity
        view.requestLayout()
    }

    private fun applyContentLayout(
        view: View,
        layout: PreviewContentLayout,
    ) {
        val params =
            FrameLayout.LayoutParams(layout.width, layout.height).apply {
                leftMargin = layout.left
                topMargin = layout.top
                gravity = Gravity.CENTER
            }
        view.layoutParams = params
        view.pivotX = layout.width / 2f
        view.pivotY = layout.height / 2f
        view.rotation = layout.rotationDegrees
        view.requestLayout()
    }

    private fun applyRendererLayout(view: View) {
        view.layoutParams =
            FrameLayout.LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT,
            )
        view.pivotX = 0f
        view.pivotY = 0f
        view.rotation = 0f
        view.requestLayout()
    }

    override fun onCodecBufferingChanged(isBuffering: Boolean) {
        if (isBuffering && !isCodecFrameReady) {
            showRendererOnly()
        }
        reportRuntimeState(
            frameRequest = lastPlayingFrameRequest,
            isBuffering = isBuffering,
            frameReady = isCodecFrameReady || lastRenderedRendererRequestKey != null,
            previewLatencyMillis = 0.0,
            seekLatencyMillis = lastSeekLatencyMillis,
            force = isBuffering,
        )
    }

    override fun onCodecFrameRendered(sourcePositionSeconds: Double) {
        val frameRequest = lastPlayingFrameRequest ?: return
        isCodecFrameReady = true
        lastVideoPlaybackStartRealtimeMs = 0L
        showVideoOnly()
        val clipLocalSeconds = sourcePositionSeconds - frameRequest.sourceStartSeconds
        val timelinePositionSeconds =
            (frameRequest.clipStartSeconds + clipLocalSeconds).coerceAtLeast(0.0)
        previewEngine.syncRenderedTimelinePosition(
            projectId = projectId,
            timelinePositionSeconds = timelinePositionSeconds,
            isPlaying = true,
        )
        syncAudioToRenderedPosition()
        reportRuntimeState(
            frameRequest =
                frameRequest.copy(
                    timelinePositionSeconds = timelinePositionSeconds,
                    sourcePositionSeconds = sourcePositionSeconds,
                ),
            isBuffering = false,
            frameReady = true,
            previewLatencyMillis = 0.0,
            seekLatencyMillis = lastSeekLatencyMillis,
            force = false,
        )
    }

    override fun onCodecPlaybackCompleted(sourcePositionSeconds: Double) {
        val frameRequest = lastPlayingFrameRequest ?: return
        isCodecFrameReady = false
        val clipLocalSeconds = sourcePositionSeconds - frameRequest.sourceStartSeconds
        val timelinePositionSeconds =
            (frameRequest.clipStartSeconds + clipLocalSeconds).coerceAtLeast(0.0)
        previewEngine.syncRenderedTimelinePosition(
            projectId = projectId,
            timelinePositionSeconds = timelinePositionSeconds,
            isPlaying = false,
        )
        reportRuntimeState(
            frameRequest =
                frameRequest.copy(
                    timelinePositionSeconds = timelinePositionSeconds,
                    sourcePositionSeconds = sourcePositionSeconds,
                    isPlaying = false,
                ),
            isBuffering = false,
            frameReady = true,
            previewLatencyMillis = 0.0,
            seekLatencyMillis = lastSeekLatencyMillis,
            force = true,
        )
        activePlaybackSessionKey = null
        lastVideoPlaybackStartRealtimeMs = 0L
    }

    private fun reportRuntimeState(
        frameRequest: ResolvedPreviewFrameRequest?,
        isBuffering: Boolean,
        frameReady: Boolean,
        previewLatencyMillis: Double,
        seekLatencyMillis: Double,
        force: Boolean = false,
    ) {
        val now = SystemClock.elapsedRealtime()
        val isPlaying = frameRequest?.isPlaying ?: false
        if (!force && isPlaying && now - lastRuntimeEmitRealtimeMs < 120L) {
            return
        }
        lastRuntimeEmitRealtimeMs = now
        FusionPreviewRegistry.reportRuntimeState(
            projectId = projectId,
            state =
                FusionPreviewRuntimeState(
                    positionSeconds = frameRequest?.timelinePositionSeconds ?: 0.0,
                    isPlaying = frameRequest?.isPlaying ?: false,
                    transportRevision = frameRequest?.transportRevision ?: 0,
                    isBuffering = isBuffering,
                    frameReady = frameReady,
                    frameDropCount = frameDropCount.coerceAtLeast(0),
                    audioDropCount = previewEngine.audioEngine.runtimeSnapshot.dropCount,
                    bufferUnderrunCount = bufferUnderrunCount.coerceAtLeast(0),
                    previewLatencyMillis = previewLatencyMillis,
                    seekLatencyMillis = seekLatencyMillis,
                ),
        )
    }

    private fun playbackSessionKey(frameRequest: ResolvedPreviewFrameRequest): String {
        return PlaybackContinuityPlanner.buildPlaybackSessionKey(frameRequest)
    }

    private fun resolveContentFitMode(
        frameRequest: ResolvedPreviewFrameRequest,
        sceneNode: Map<String, Any?>? = previewEngine.sceneNodeForClip(projectId, frameRequest.baseClipId),
        projectWidth: Int = frameRequest.projectWidth ?: width,
        projectHeight: Int = frameRequest.projectHeight ?: height,
    ): PreviewContentFitMode {
        if (frameRequest.sourceKind != "video" && frameRequest.sourceKind != "image") {
            return PreviewContentFitMode.CONTAIN
        }
        if (projectWidth <= 0 || projectHeight <= 0) {
            return PreviewContentFitMode.CONTAIN
        }
        if (sceneNode == null) {
            return PreviewContentFitMode.COVER
        }
        val nodeX = (sceneNode["x"] as? Number)?.toDouble() ?: 0.0
        val nodeY = (sceneNode["y"] as? Number)?.toDouble() ?: 0.0
        val nodeWidth = (sceneNode["width"] as? Number)?.toDouble() ?: projectWidth.toDouble()
        val nodeHeight = (sceneNode["height"] as? Number)?.toDouble() ?: projectHeight.toDouble()
        val fillsProject =
            nodeX <= LAYOUT_EPSILON &&
                nodeY <= LAYOUT_EPSILON &&
                kotlin.math.abs(nodeWidth - projectWidth.toDouble()) <= LAYOUT_EPSILON &&
                kotlin.math.abs(nodeHeight - projectHeight.toDouble()) <= LAYOUT_EPSILON
        return if (fillsProject) {
            PreviewContentFitMode.COVER
        } else {
            PreviewContentFitMode.CONTAIN
        }
    }

    private companion object {
        private const val LAYOUT_EPSILON = 1.0
        private const val VIDEO_STARTUP_GRACE_MS = 420L
    }

    private fun syncAudio(frameRequest: ResolvedPreviewFrameRequest) {
        val audioRequest = previewEngine.audioRequestForProject(projectId)
        if (audioRequest == null) {
            previewEngine.audioEngine.stop()
            activeAudioSessionKey = null
            audioWasPlaying = false
            lastAudioSyncRealtimeMs = 0L
            return
        }
        if (frameRequest.isPlaying) {
            if (activeAudioSessionKey != audioRequest.sessionKey || !audioWasPlaying) {
                previewEngine.audioEngine.play(audioRequest)
                activeAudioSessionKey = audioRequest.sessionKey
                audioWasPlaying = true
                lastAudioSyncRealtimeMs = 0L
            }
        } else {
            previewEngine.audioEngine.pause(audioRequest)
            activeAudioSessionKey = audioRequest.sessionKey
            audioWasPlaying = false
            lastAudioSyncRealtimeMs = 0L
        }
    }

    private fun syncAudioToRenderedPosition() {
        val audioRequest = previewEngine.audioRequestForProject(projectId) ?: return
        if (activeAudioSessionKey != audioRequest.sessionKey || !audioWasPlaying) {
            return
        }
        val nowRealtimeMs = SystemClock.elapsedRealtime()
        if (
            !AudioClockDriftPlanner.shouldSyncFromRenderedFrame(
                lastSyncRealtimeMs = lastAudioSyncRealtimeMs,
                nowRealtimeMs = nowRealtimeMs,
            )
        ) {
            return
        }
        lastAudioSyncRealtimeMs = nowRealtimeMs
        previewEngine.audioEngine.syncPlayback(audioRequest)
    }
}
