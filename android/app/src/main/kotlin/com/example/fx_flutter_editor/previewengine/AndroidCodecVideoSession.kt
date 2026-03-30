package com.example.fx_flutter_editor.previewengine

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Surface
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToLong

class AndroidCodecVideoSession(
    private val listener: Listener,
) {
    interface Listener {
        fun onCodecBufferingChanged(isBuffering: Boolean)
        fun onCodecFrameRendered(sourcePositionSeconds: Double)
        fun onCodecPlaybackCompleted(sourcePositionSeconds: Double)
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var disposed = false
    @Volatile private var currentSurface: Surface? = null
    @Volatile private var pendingPlaybackRequest: PlaybackRequest? = null
    @Volatile private var stopRequested = false
    @Volatile private var paused = false
    @Volatile private var currentPlaybackToken: String? = null
    @Volatile private var currentSessionKey: String? = null
    @Volatile private var currentSourcePositionUs: Long = 0L
    private var currentDecoderPath: String? = null
    private var currentDecoderStartUs: Long = 0L
    private var currentDecoderEndUs: Long? = null
    private var extractor: MediaExtractor? = null
    private var codec: MediaCodec? = null
    private var trackIndex: Int = -1
    private var inputEos: Boolean = false

    init {
        executor.execute(::runLoop)
    }

    fun attachSurface(surface: Surface?) {
        currentSurface = surface
        if (surface == null) {
            stopPlayback()
        }
    }

    fun play(
        frameRequest: ResolvedPreviewFrameRequest,
        sessionKey: String,
    ) {
        currentPlaybackToken = frameRequest.frameToken
        currentSessionKey = sessionKey
        pendingPlaybackRequest =
            PlaybackRequest(
                sourcePath = frameRequest.sourcePath,
                sourceKind = frameRequest.sourceKind,
                continuityKind = frameRequest.continuityKind,
                sourceStartUs = (frameRequest.sourceStartSeconds * 1_000_000.0).roundToLong(),
                sourceEndUs = frameRequest.sourceEndSeconds?.times(1_000_000.0)?.roundToLong(),
                sourcePositionUs =
                    (
                        (frameRequest.sourcePositionSeconds ?: frameRequest.sourceStartSeconds) *
                            1_000_000.0
                        ).roundToLong(),
                frameToken = frameRequest.frameToken,
                sessionKey = sessionKey,
            )
        stopRequested = false
        paused = false
    }

    fun pausePlayback() {
        paused = true
    }

    fun canResume(
        sessionKey: String,
        targetSourcePositionSeconds: Double,
    ): Boolean {
        val targetSourcePositionUs = (targetSourcePositionSeconds * 1_000_000.0).roundToLong()
        return currentSessionKey == sessionKey &&
            paused &&
            !stopRequested &&
            !disposed &&
            codec != null &&
            extractor != null &&
            abs(currentSourcePositionUs - targetSourcePositionUs) <= RESUME_POSITION_TOLERANCE_US
    }

    fun isPausedForSession(sessionKey: String): Boolean {
        return currentSessionKey == sessionKey && paused && !stopRequested && !disposed
    }

    fun shouldRetargetPlayback(
        sessionKey: String,
        continuityKind: String?,
        targetSourcePositionSeconds: Double,
    ): Boolean {
        if (currentSessionKey != sessionKey || stopRequested || disposed) {
            return true
        }
        val targetSourcePositionUs = (targetSourcePositionSeconds * 1_000_000.0).roundToLong()
        return VideoPlaybackReplacementPlanner.shouldRetargetActiveSession(
            continuityKind = continuityKind,
            targetSourcePositionUs = targetSourcePositionUs,
            currentSourcePositionUs = currentSourcePositionUs,
        )
    }

    fun resumePlayback() {
        paused = false
    }

    fun stopPlayback() {
        stopRequested = true
        paused = false
        pendingPlaybackRequest = null
        currentPlaybackToken = null
        currentSessionKey = null
        currentSourcePositionUs = 0L
    }

    fun dispose() {
        disposed = true
        stopPlayback()
        executor.shutdownNow()
        releaseDecoder()
    }

    private fun runLoop() {
        while (!disposed) {
            val request = pendingPlaybackRequest
            if (request == null || currentSurface == null || stopRequested) {
                SystemClock.sleep(8)
                continue
            }
            pendingPlaybackRequest = null
            playRequest(request)
        }
        releaseDecoder()
    }

    private fun playRequest(request: PlaybackRequest) {
        val surface = currentSurface ?: return
        try {
            dispatchToMain { listener.onCodecBufferingChanged(true) }
            ensureDecoder(request, surface)
            extractor?.seekTo(request.sourcePositionUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            codec?.flush()
            inputEos = false
            currentSourcePositionUs = request.sourcePositionUs

            val playbackAnchorRealtimeNs = System.nanoTime()
            val playbackAnchorSourceUs = request.sourcePositionUs
            var outputEos = false
            var lastRenderedSourceUs = request.sourcePositionUs
            val bufferInfo = MediaCodec.BufferInfo()

            while (!disposed && !stopRequested && currentPlaybackToken == request.frameToken && !outputEos) {
                if (paused) {
                    dispatchToMain { listener.onCodecBufferingChanged(false) }
                    if (pendingPlaybackRequest != null && pendingPlaybackRequest?.frameToken != request.frameToken) {
                        return
                    }
                    SystemClock.sleep(PAUSED_SLEEP_MS)
                    continue
                }
                feedDecoderInput(request)
                val outputIndex = codec?.dequeueOutputBuffer(bufferInfo, 10_000) ?: -1
                when {
                    outputIndex >= 0 -> {
                        val presentationUs = bufferInfo.presentationTimeUs
                        val reachedEnd =
                            request.enforceSourceWindow &&
                                request.sourceEndUs != null &&
                                presentationUs >= request.sourceEndUs - 1_000
                        val shouldRender =
                            bufferInfo.size > 0 &&
                                presentationUs >= request.sourcePositionUs - 1_000
                        if (shouldRender) {
                            val targetRealtimeNs =
                                playbackAnchorRealtimeNs +
                                    max(
                                        0L,
                                        presentationUs - playbackAnchorSourceUs,
                                    ) * 1_000L
                            releaseOutputBufferAt(codec, outputIndex, targetRealtimeNs)
                            lastRenderedSourceUs = presentationUs
                            currentSourcePositionUs = presentationUs
                            dispatchToMain { listener.onCodecBufferingChanged(false) }
                            dispatchToMain {
                                listener.onCodecFrameRendered(presentationUs / 1_000_000.0)
                            }
                        } else {
                            codec?.releaseOutputBuffer(outputIndex, false)
                        }
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 || reachedEnd) {
                            outputEos = true
                        }
                    }

                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        dispatchToMain { listener.onCodecBufferingChanged(false) }
                    }
                }

                val replacementRequest = pendingPlaybackRequest
                if (
                    replacementRequest != null &&
                        VideoPlaybackReplacementPlanner.shouldRestart(
                            currentSourcePath = request.sourcePath,
                            currentContinuityKind = request.continuityKind,
                            currentSourceStartUs = request.sourceStartUs,
                            currentSourceEndUs = request.sourceEndUs,
                            currentEnforceSourceWindow = request.enforceSourceWindow,
                            replacementSourcePath = replacementRequest.sourcePath,
                            replacementContinuityKind = replacementRequest.continuityKind,
                            replacementSourceStartUs = replacementRequest.sourceStartUs,
                            replacementSourceEndUs = replacementRequest.sourceEndUs,
                            replacementEnforceSourceWindow = replacementRequest.enforceSourceWindow,
                            replacementSourcePositionUs = replacementRequest.sourcePositionUs,
                            lastRenderedSourceUs = lastRenderedSourceUs,
                        )
                ) {
                    return
                }
            }

            if (!stopRequested && currentPlaybackToken == request.frameToken) {
                dispatchToMain {
                    listener.onCodecPlaybackCompleted(lastRenderedSourceUs / 1_000_000.0)
                }
            }
        } catch (_: Throwable) {
            releaseDecoder()
        } finally {
            dispatchToMain { listener.onCodecBufferingChanged(false) }
        }
    }

    private fun dispatchToMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainHandler.post(action)
        }
    }

    private fun releaseOutputBufferAt(
        codec: MediaCodec?,
        outputIndex: Int,
        targetRealtimeNs: Long,
    ) {
        val safeCodec = codec ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val renderTimestampNs = max(System.nanoTime(), targetRealtimeNs)
            safeCodec.releaseOutputBuffer(outputIndex, renderTimestampNs)
            return
        }
        val targetRealtimeMs = targetRealtimeNs / 1_000_000L
        val remainingDelayMs = targetRealtimeMs - SystemClock.elapsedRealtime()
        if (remainingDelayMs > 1L) {
            SystemClock.sleep(remainingDelayMs)
        }
        safeCodec.releaseOutputBuffer(outputIndex, true)
    }

    private fun ensureDecoder(
        request: PlaybackRequest,
        surface: Surface,
    ) {
        val needsRebuild =
            request.sourcePath != currentDecoderPath ||
                extractor == null ||
                codec == null ||
                (
                    request.enforceSourceWindow &&
                        (
                            request.sourceStartUs != currentDecoderStartUs ||
                                request.sourceEndUs != currentDecoderEndUs
                            )
                    )
        if (!needsRebuild) {
            return
        }

        releaseDecoder()
        val mediaExtractor = MediaExtractor().apply {
            setDataSource(request.sourcePath)
        }
        val selectedTrackIndex =
            (0 until mediaExtractor.trackCount).firstOrNull { index ->
                val mime = mediaExtractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                mime?.startsWith("video/") == true
            } ?: run {
                mediaExtractor.release()
                return
            }
        mediaExtractor.selectTrack(selectedTrackIndex)
        val format = mediaExtractor.getTrackFormat(selectedTrackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME) ?: run {
            mediaExtractor.release()
            return
        }
        val mediaCodec = MediaCodec.createDecoderByType(mime)
        mediaCodec.configure(format, surface, null, 0)
        mediaCodec.start()

        extractor = mediaExtractor
        codec = mediaCodec
        trackIndex = selectedTrackIndex
        currentDecoderPath = request.sourcePath
        currentDecoderStartUs = request.sourceStartUs
        currentDecoderEndUs = request.sourceEndUs
        inputEos = false
    }

    private fun feedDecoderInput(request: PlaybackRequest) {
        val codec = codec ?: return
        val extractor = extractor ?: return
        if (inputEos) {
            return
        }
        val inputIndex = codec.dequeueInputBuffer(0)
        if (inputIndex < 0) {
            return
        }
        val inputBuffer = codec.getInputBuffer(inputIndex) ?: return
        val sampleSize = extractor.readSampleData(inputBuffer, 0)
        if (sampleSize < 0) {
            codec.queueInputBuffer(
                inputIndex,
                0,
                0,
                0,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
            )
            inputEos = true
            return
        }
        val sampleTimeUs = extractor.sampleTime
        if (request.enforceSourceWindow && request.sourceEndUs != null && sampleTimeUs > request.sourceEndUs) {
            codec.queueInputBuffer(
                inputIndex,
                0,
                0,
                0,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
            )
            inputEos = true
            return
        }
        codec.queueInputBuffer(
            inputIndex,
            0,
            sampleSize,
            sampleTimeUs,
            0,
        )
        extractor.advance()
    }

    private fun releaseDecoder() {
        try {
            codec?.stop()
        } catch (_: Throwable) {
        }
        try {
            codec?.release()
        } catch (_: Throwable) {
        }
        try {
            extractor?.release()
        } catch (_: Throwable) {
        }
        codec = null
        extractor = null
        trackIndex = -1
        currentDecoderPath = null
        currentDecoderStartUs = 0L
        currentDecoderEndUs = null
        inputEos = false
    }

    private data class PlaybackRequest(
        val sourcePath: String,
        val sourceKind: String,
        val continuityKind: String?,
        val sourceStartUs: Long,
        val sourceEndUs: Long?,
        val sourcePositionUs: Long,
        val frameToken: String,
        val sessionKey: String,
    ) {
        val enforceSourceWindow: Boolean
            get() =
                !(
                    sourceKind == "video" &&
                        continuityKind == "sameSourceContiguous"
                    )
    }

    private companion object {
        private const val PAUSED_SLEEP_MS = 8L
        private const val RESUME_POSITION_TOLERANCE_US = 80_000L
    }
}
