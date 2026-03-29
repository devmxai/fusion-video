package com.example.fx_flutter_editor.previewengine

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
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
    @Volatile private var currentPlaybackToken: String? = null
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

    fun play(frameRequest: ResolvedPreviewFrameRequest) {
        currentPlaybackToken = frameRequest.frameToken
        pendingPlaybackRequest =
            PlaybackRequest(
                sourcePath = frameRequest.sourcePath,
                sourceStartUs = (frameRequest.sourceStartSeconds * 1_000_000.0).roundToLong(),
                sourceEndUs = frameRequest.sourceEndSeconds?.times(1_000_000.0)?.roundToLong(),
                sourcePositionUs =
                    (
                        (frameRequest.sourcePositionSeconds ?: frameRequest.sourceStartSeconds) *
                            1_000_000.0
                        ).roundToLong(),
                frameToken = frameRequest.frameToken,
            )
        stopRequested = false
    }

    fun stopPlayback() {
        stopRequested = true
        pendingPlaybackRequest = null
        currentPlaybackToken = null
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

            val playbackAnchorRealtimeMs = SystemClock.elapsedRealtime()
            val playbackAnchorSourceUs = request.sourcePositionUs
            var outputEos = false
            var lastRenderedSourceUs = request.sourcePositionUs
            val bufferInfo = MediaCodec.BufferInfo()

            while (!disposed && !stopRequested && currentPlaybackToken == request.frameToken && !outputEos) {
                feedDecoderInput(request)
                val outputIndex = codec?.dequeueOutputBuffer(bufferInfo, 10_000) ?: -1
                when {
                    outputIndex >= 0 -> {
                        val presentationUs = bufferInfo.presentationTimeUs
                        val reachedEnd =
                            request.sourceEndUs != null &&
                                presentationUs >= request.sourceEndUs - 1_000
                        val shouldRender =
                            bufferInfo.size > 0 &&
                                presentationUs >= request.sourcePositionUs - 1_000
                        if (shouldRender) {
                            val targetRealtimeMs =
                                playbackAnchorRealtimeMs +
                                    max(
                                        0L,
                                        ((presentationUs - playbackAnchorSourceUs) / 1000.0)
                                            .roundToLong(),
                                    )
                            val remainingDelayMs =
                                targetRealtimeMs - SystemClock.elapsedRealtime()
                            if (remainingDelayMs > 1L) {
                                SystemClock.sleep(remainingDelayMs)
                            }
                            codec?.releaseOutputBuffer(outputIndex, true)
                            lastRenderedSourceUs = presentationUs
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
                        (
                            replacementRequest.sourcePath != request.sourcePath ||
                                replacementRequest.sourceStartUs != request.sourceStartUs ||
                                replacementRequest.sourceEndUs != request.sourceEndUs ||
                                abs(replacementRequest.sourcePositionUs - lastRenderedSourceUs) > 50_000L
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

    private fun ensureDecoder(
        request: PlaybackRequest,
        surface: Surface,
    ) {
        val needsRebuild =
            request.sourcePath != currentDecoderPath ||
                request.sourceStartUs != currentDecoderStartUs ||
                request.sourceEndUs != currentDecoderEndUs ||
                extractor == null ||
                codec == null
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
        if (request.sourceEndUs != null && sampleTimeUs > request.sourceEndUs) {
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
        val sourceStartUs: Long,
        val sourceEndUs: Long?,
        val sourcePositionUs: Long,
        val frameToken: String,
    )
}
