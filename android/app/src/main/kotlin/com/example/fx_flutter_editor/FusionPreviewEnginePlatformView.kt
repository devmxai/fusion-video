package com.example.fx_flutter_editor

import android.content.Context
import android.graphics.Color
import android.os.SystemClock
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import com.example.fx_flutter_editor.previewengine.AndroidCodecVideoSession
import com.example.fx_flutter_editor.previewengine.DecodedPreviewFrameResult
import com.example.fx_flutter_editor.previewengine.FusionAndroidPreviewEngine
import com.example.fx_flutter_editor.previewengine.PreviewContentLayout
import com.example.fx_flutter_editor.previewengine.PreviewGlSurfaceView
import com.example.fx_flutter_editor.previewengine.PreviewLayoutPlanner
import com.example.fx_flutter_editor.previewengine.PreviewNodeLayout
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
            visibility = View.GONE
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
    private var lastRenderedFrameToken: String? = null
    private var lastFrameRequest: ResolvedPreviewFrameRequest? = null
    private var lastPlayingFrameRequest: ResolvedPreviewFrameRequest? = null
    private var activePlaybackSessionKey: String? = null
    private var lastAppliedLayoutKey: String? = null
    private var frameDropCount: Int = 0
    private var bufferUnderrunCount: Int = 0
    private var lastSeekLatencyMillis: Double = 0.0
    private var lastRuntimeEmitRealtimeMs: Long = 0L

    init {
        setBackgroundColor(Color.BLACK)
        videoSurfaceView.apply {
            visibility = View.GONE
            holder.addCallback(
                object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) {
                        videoSession.attachSurface(holder.surface)
                        lastPlayingFrameRequest?.let(videoSession::play)
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
            lastFrameRequest = null
            lastPlayingFrameRequest = null
            activePlaybackSessionKey = null
            lastAppliedLayoutKey = null
            videoSession.stopPlayback()
            videoContainer.visibility = View.GONE
            rendererContainer.visibility = View.VISIBLE
            lastRenderedFrameToken = null
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
        if (frameRequest.sourceKind == "video" && frameRequest.isPlaying) {
            val nextPlaybackSessionKey = playbackSessionKey(frameRequest)
            val isSamePlaybackSession = nextPlaybackSessionKey == activePlaybackSessionKey
            lastPlayingFrameRequest = frameRequest
            updateBaseVisualLayout(frameRequest)
            videoContainer.visibility = View.VISIBLE
            rendererContainer.visibility = View.GONE
            if (!isSamePlaybackSession) {
                activePlaybackSessionKey = nextPlaybackSessionKey
                videoSession.play(frameRequest)
                reportRuntimeState(
                    frameRequest = frameRequest,
                    isBuffering = true,
                    frameReady = true,
                    previewLatencyMillis = 0.0,
                    seekLatencyMillis = lastSeekLatencyMillis,
                    force = true,
                )
            }
            return
        }

        lastPlayingFrameRequest = null
        activePlaybackSessionKey = null
        videoSession.stopPlayback()
        videoContainer.visibility = View.GONE
        rendererContainer.visibility = View.VISIBLE
        updateBaseVisualLayout(frameRequest)

        if (frameRequest.frameToken == lastRenderedFrameToken) {
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
        reportRuntimeState(
            frameRequest = frameRequest,
            isBuffering = true,
            frameReady = lastRenderedFrameToken != null,
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

    fun dispose() {
        previewEngine.detachOutput(projectId, this)
        previewEngine.decodeScheduler.cancelProject(projectId)
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
        lastRenderedFrameToken = result.frameRequest.frameToken
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
        )
        reportRuntimeState(
            frameRequest = result.frameRequest,
            isBuffering = false,
            frameReady = result.bitmap != null,
            previewLatencyMillis = result.previewLatencyMillis,
            seekLatencyMillis = lastSeekLatencyMillis,
            force = !result.frameRequest.isPlaying,
        )
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
        val sceneNode = previewEngine.sceneNodeForClip(projectId, frameRequest.sourceId)
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
                mediaWidth = descriptor?.width ?: descriptor?.displayWidth,
                mediaHeight = descriptor?.height ?: descriptor?.displayHeight,
                mediaRotationDegrees = descriptor?.rotationDegrees ?: 0,
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
        reportRuntimeState(
            frameRequest = lastPlayingFrameRequest,
            isBuffering = isBuffering,
            frameReady = true,
            previewLatencyMillis = 0.0,
            seekLatencyMillis = lastSeekLatencyMillis,
            force = isBuffering,
        )
    }

    override fun onCodecFrameRendered(sourcePositionSeconds: Double) {
        val frameRequest = lastPlayingFrameRequest ?: return
        val clipLocalSeconds = sourcePositionSeconds - frameRequest.sourceStartSeconds
        val timelinePositionSeconds =
            (frameRequest.clipStartSeconds + clipLocalSeconds).coerceAtLeast(0.0)
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
        val clipLocalSeconds = sourcePositionSeconds - frameRequest.sourceStartSeconds
        val timelinePositionSeconds =
            (frameRequest.clipStartSeconds + clipLocalSeconds).coerceAtLeast(0.0)
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
                    audioDropCount = 0,
                    bufferUnderrunCount = bufferUnderrunCount.coerceAtLeast(0),
                    previewLatencyMillis = previewLatencyMillis,
                    seekLatencyMillis = seekLatencyMillis,
                ),
        )
    }

    private fun playbackSessionKey(frameRequest: ResolvedPreviewFrameRequest): String {
        return buildString {
            append(frameRequest.sourcePath)
            append('|')
            append(frameRequest.sourceStartSeconds)
            append('|')
            append(frameRequest.sourceEndSeconds ?: -1.0)
            append('|')
            append(frameRequest.transportRevision)
        }
    }
}
