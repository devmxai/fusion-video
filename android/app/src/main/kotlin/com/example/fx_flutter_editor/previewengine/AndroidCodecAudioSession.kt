package com.example.fx_flutter_editor.previewengine

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.SystemClock
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToLong

class AndroidCodecAudioSession {
    data class RuntimeSnapshot(
        val currentPositionMs: Int,
        val dropCount: Int,
        val decoderRestartCount: Int,
        val isPlaying: Boolean,
    )

    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var disposed = false
    @Volatile private var pendingPlaybackRequest: PlaybackRequest? = null
    @Volatile private var stopRequested = false
    @Volatile private var paused = false
    @Volatile private var currentPlaybackToken: String? = null
    @Volatile private var currentSessionKey: String? = null
    @Volatile private var currentContinuityKind: String? = null
    @Volatile private var currentGain: Float = 1f
    @Volatile private var currentSourcePositionUs: Long = 0L
    @Volatile private var dropCount: Int = 0
    @Volatile private var decoderRestartCount: Int = 0

    private var extractor: MediaExtractor? = null
    private var codec: MediaCodec? = null
    private var audioTrack: AudioTrack? = null
    private var currentDecoderPath: String? = null
    private var currentDecoderStartUs: Long = 0L
    private var currentDecoderEndUs: Long? = null
    private var trackIndex: Int = -1
    private var inputEos = false
    private var audioSampleRate = 0
    private var audioChannelCount = 0
    private var audioChannelMask = 0
    private var audioEncoding = AudioFormat.ENCODING_PCM_16BIT
    private var queuedAudioBytesBeforePlay = 0

    init {
        executor.execute(::runLoop)
    }

    val currentPositionMs: Int
        get() = (currentSourcePositionUs / 1_000L).toInt()

    val runtimeSnapshot: RuntimeSnapshot
        get() =
            RuntimeSnapshot(
                currentPositionMs = currentPositionMs,
                dropCount = dropCount,
                decoderRestartCount = decoderRestartCount,
                isPlaying = audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING,
            )

    fun play(request: ResolvedPreviewAudioRequest) {
        currentGain = request.volumeLevel
        currentSessionKey = request.sessionKey
        currentContinuityKind = request.continuityKind
        currentPlaybackToken = request.playbackToken
        pendingPlaybackRequest = PlaybackRequest.from(request)
        stopRequested = false
        paused = false
    }

    fun setGain(level: Float) {
        currentGain = level.coerceIn(0f, 1f)
        audioTrack?.let { applyTrackVolume(it, currentGain) }
    }

    fun pause() {
        paused = true
        audioTrack?.pause()
    }

    fun stop() {
        stopRequested = true
        paused = false
        pendingPlaybackRequest = null
        currentPlaybackToken = null
        currentSessionKey = null
        currentContinuityKind = null
        currentSourcePositionUs = 0L
    }

    fun canResume(
        sessionKey: String,
        continuityKind: String?,
        targetPositionMs: Int,
    ): Boolean {
        val targetSourcePositionUs = targetPositionMs.toLong() * 1_000L
        return currentSessionKey == sessionKey &&
            paused &&
            !stopRequested &&
            !disposed &&
            AudioPlaybackReplacementPlanner.canResumePausedSession(
                continuityKind = continuityKind ?: currentContinuityKind,
                targetSourcePositionUs = targetSourcePositionUs,
                currentSourcePositionUs = currentSourcePositionUs,
            )
    }

    fun resume() {
        paused = false
        audioTrack?.let { track ->
            if (track.playState != AudioTrack.PLAYSTATE_PLAYING) {
                track.play()
            }
        }
    }

    fun dispose() {
        disposed = true
        stop()
        executor.shutdownNow()
        releaseDecoder()
        releaseAudioTrack()
    }

    private fun runLoop() {
        while (!disposed) {
            if (stopRequested) {
                releaseDecoder()
                releaseAudioTrack()
                stopRequested = false
                SystemClock.sleep(IDLE_SLEEP_MS)
                continue
            }
            val request = pendingPlaybackRequest
            if (request == null) {
                SystemClock.sleep(IDLE_SLEEP_MS)
                continue
            }
            pendingPlaybackRequest = null
            playRequest(request)
        }
        releaseDecoder()
        releaseAudioTrack()
    }

    private fun playRequest(request: PlaybackRequest) {
        try {
            ensureDecoder(request)
            extractor?.seekTo(request.sourcePositionUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            codec?.flush()
            audioTrack?.pause()
            audioTrack?.flush()
            inputEos = false
            queuedAudioBytesBeforePlay = 0
            currentSourcePositionUs = request.sourcePositionUs

            var outputEos = false
            var lastRenderedSourceUs = request.sourcePositionUs
            val bufferInfo = MediaCodec.BufferInfo()

            while (!disposed && !stopRequested && currentPlaybackToken == request.playbackToken && !outputEos) {
                if (paused) {
                    audioTrack?.pause()
                    if (pendingPlaybackRequest != null && pendingPlaybackRequest?.playbackToken != request.playbackToken) {
                        return
                    }
                    SystemClock.sleep(IDLE_SLEEP_MS)
                    continue
                }
                feedDecoderInput(request)
                val outputIndex = codec?.dequeueOutputBuffer(bufferInfo, OUTPUT_TIMEOUT_US) ?: -1
                when {
                    outputIndex >= 0 -> {
                        val presentationUs = bufferInfo.presentationTimeUs
                        val reachedEnd =
                            request.enforceSourceWindow &&
                                request.sourceEndUs != null &&
                                presentationUs >= request.sourceEndUs - END_TOLERANCE_US
                        val shouldPlayBuffer =
                            bufferInfo.size > 0 &&
                                presentationUs >= request.sourcePositionUs - END_TOLERANCE_US
                        if (shouldPlayBuffer) {
                            if (ensureAudioTrack(codec?.outputFormat, request.gainLevel)) {
                                val pcmBytes = readOutputBytes(codec, outputIndex, bufferInfo)
                                val track = audioTrack
                                if (track != null && pcmBytes.isNotEmpty()) {
                                    val writtenBytes = writeToTrack(track, pcmBytes)
                                    queuedAudioBytesBeforePlay += writtenBytes
                                    if (
                                        track.playState != AudioTrack.PLAYSTATE_PLAYING &&
                                            (
                                                AudioPlaybackBufferPlanner.shouldStartPlayback(
                                                    queuedBytes = queuedAudioBytesBeforePlay,
                                                    sampleRate = audioSampleRate,
                                                    channelCount = audioChannelCount,
                                                    encoding = audioEncoding,
                                                ) ||
                                                    (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                                                )
                                    ) {
                                        track.play()
                                    }
                                    lastRenderedSourceUs = presentationUs
                                    currentSourcePositionUs = presentationUs
                                }
                            }
                        }
                        codec?.releaseOutputBuffer(outputIndex, false)
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 || reachedEnd) {
                            outputEos = true
                        }
                    }

                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        ensureAudioTrack(codec?.outputFormat, request.gainLevel)
                    }
                }

                val replacementRequest = pendingPlaybackRequest
                if (
                    replacementRequest != null &&
                        AudioPlaybackReplacementPlanner.shouldRestart(
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
                            currentRenderedSourceUs = lastRenderedSourceUs,
                        )
                ) {
                    return
                }
            }
        } catch (_: Throwable) {
            dropCount += 1
            releaseDecoder()
            releaseAudioTrack()
        }
    }

    private fun ensureDecoder(request: PlaybackRequest) {
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
        if (extractor != null || codec != null) {
            decoderRestartCount += 1
        }

        releaseDecoder()
        val mediaExtractor = MediaExtractor().apply { setDataSource(request.sourcePath) }
        val selectedTrackIndex =
            (0 until mediaExtractor.trackCount).firstOrNull { index ->
                val mime = mediaExtractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                mime?.startsWith("audio/") == true
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
        mediaCodec.configure(format, null, null, 0)
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
        if (inputEos) {
            return
        }
        val codec = codec ?: return
        val extractor = extractor ?: return
        val inputIndex = codec.dequeueInputBuffer(INPUT_TIMEOUT_US)
        if (inputIndex < 0) {
            return
        }
        val inputBuffer = getInputBuffer(codec, inputIndex) ?: return
        inputBuffer.clear()
        val sampleTimeUs = extractor.sampleTime
        if (
            sampleTimeUs < 0L ||
                (
                    request.enforceSourceWindow &&
                        request.sourceEndUs != null &&
                        sampleTimeUs >= request.sourceEndUs
                    )
        ) {
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
        if (sampleTimeUs + END_TOLERANCE_US < request.sourceStartUs) {
            extractor.advance()
            return
        }
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
        codec.queueInputBuffer(
            inputIndex,
            0,
            sampleSize,
            sampleTimeUs,
            0,
        )
        extractor.advance()
    }

    private fun ensureAudioTrack(
        format: MediaFormat?,
        gainLevel: Float,
    ): Boolean {
        val safeFormat = format ?: return audioTrack != null
        val sampleRate =
            if (safeFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                safeFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            } else {
                44_100
            }
        val channelCount =
            if (safeFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                safeFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            } else {
                2
            }
        val channelMask =
            when (channelCount) {
                1 -> AudioFormat.CHANNEL_OUT_MONO
                else -> AudioFormat.CHANNEL_OUT_STEREO
            }
        val encoding =
            if (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                    safeFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)
            ) {
                safeFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
            } else {
                AudioFormat.ENCODING_PCM_16BIT
            }
        if (
            audioTrack != null &&
                sampleRate == audioSampleRate &&
                channelMask == audioChannelMask &&
                encoding == audioEncoding
        ) {
            audioTrack?.let { applyTrackVolume(it, gainLevel) }
            return true
        }

        releaseAudioTrack()
        val minBufferSize = AudioTrack.getMinBufferSize(sampleRate, channelMask, encoding)
        val fallbackBufferSize =
            (sampleRate * max(1, channelCount) * PCM_BYTES_PER_SAMPLE / 4).coerceAtLeast(4_096)
        val bufferSize =
            if (minBufferSize > 0) {
                max(minBufferSize, fallbackBufferSize)
            } else {
                fallbackBufferSize
            }
        val track =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build(),
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(encoding)
                            .setSampleRate(sampleRate)
                            .setChannelMask(channelMask)
                            .build(),
                    )
                    .setBufferSizeInBytes(bufferSize)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                AudioTrack(
                    android.media.AudioManager.STREAM_MUSIC,
                    sampleRate,
                    channelMask,
                    encoding,
                    bufferSize,
                    AudioTrack.MODE_STREAM,
                )
            }
        applyTrackVolume(track, gainLevel)
        audioTrack = track
        audioSampleRate = sampleRate
        audioChannelCount = channelCount
        audioChannelMask = channelMask
        audioEncoding = encoding
        return true
    }

    private fun readOutputBytes(
        codec: MediaCodec?,
        outputIndex: Int,
        bufferInfo: MediaCodec.BufferInfo,
    ): ByteArray {
        val outputBuffer = getOutputBuffer(codec, outputIndex) ?: return ByteArray(0)
        outputBuffer.position(bufferInfo.offset)
        outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
        val pcmBytes = ByteArray(bufferInfo.size)
        outputBuffer.get(pcmBytes)
        outputBuffer.clear()
        return pcmBytes
    }

    private fun writeToTrack(
        track: AudioTrack,
        pcmBytes: ByteArray,
    ): Int {
        var writtenBytes = 0
        while (writtenBytes < pcmBytes.size && !stopRequested && !disposed) {
            val count =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    track.write(
                        pcmBytes,
                        writtenBytes,
                        pcmBytes.size - writtenBytes,
                        AudioTrack.WRITE_BLOCKING,
                    )
                } else {
                    track.write(pcmBytes, writtenBytes, pcmBytes.size - writtenBytes)
                }
            if (count <= 0) {
                dropCount += 1
                break
            }
            writtenBytes += count
        }
        return writtenBytes
    }

    private fun applyTrackVolume(
        track: AudioTrack,
        level: Float,
    ) {
        val clamped = level.coerceIn(0f, 1f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            track.setVolume(clamped)
        } else {
            @Suppress("DEPRECATION")
            track.setStereoVolume(clamped, clamped)
        }
    }

    @Suppress("DEPRECATION")
    private fun getInputBuffer(
        codec: MediaCodec,
        index: Int,
    ) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        codec.getInputBuffer(index)
    } else {
        codec.inputBuffers[index]
    }

    @Suppress("DEPRECATION")
    private fun getOutputBuffer(
        codec: MediaCodec?,
        index: Int,
    ) = when {
        codec == null -> null
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP -> codec.getOutputBuffer(index)
        else -> codec.outputBuffers[index]
    }

    private fun releaseDecoder() {
        inputEos = false
        trackIndex = -1
        currentDecoderPath = null
        currentDecoderStartUs = 0L
        currentDecoderEndUs = null
        extractor?.release()
        extractor = null
        codec?.runCatching { stop() }
        codec?.release()
        codec = null
    }

    private fun releaseAudioTrack() {
        audioTrack?.runCatching {
            pause()
            flush()
            release()
        }
        audioTrack = null
        audioSampleRate = 0
        audioChannelCount = 0
        audioChannelMask = 0
        audioEncoding = AudioFormat.ENCODING_PCM_16BIT
        queuedAudioBytesBeforePlay = 0
    }

    private data class PlaybackRequest(
        val sourcePath: String,
        val sourceKind: String,
        val continuityKind: String?,
        val sourceStartUs: Long,
        val sourceEndUs: Long?,
        val sourcePositionUs: Long,
        val gainLevel: Float,
        val playbackToken: String,
    ) {
        val enforceSourceWindow: Boolean
            get() = continuityKind != "sameSourceContiguous" || sourceKind == "image"

        companion object {
            fun from(request: ResolvedPreviewAudioRequest): PlaybackRequest {
                val sourcePositionUs =
                    (request.sourcePositionSeconds * 1_000_000.0).roundToLong()
                return PlaybackRequest(
                    sourcePath = request.sourcePath,
                    sourceKind = request.sourceKind,
                    continuityKind = request.continuityKind,
                    sourceStartUs = (request.sourceStartSeconds * 1_000_000.0).roundToLong(),
                    sourceEndUs = request.sourceEndSeconds?.times(1_000_000.0)?.roundToLong(),
                    sourcePositionUs = sourcePositionUs,
                    gainLevel = if (request.isMuted) 0f else request.gain.coerceIn(0.0, 1.0).toFloat(),
                    playbackToken = "${request.sessionKey}|${sourcePositionUs / 1_000L}",
                )
            }
        }
    }

    private val ResolvedPreviewAudioRequest.volumeLevel: Float
        get() = if (isMuted) 0f else gain.coerceIn(0.0, 1.0).toFloat()

    private val ResolvedPreviewAudioRequest.playbackToken: String
        get() = "${sessionKey}|${(sourcePositionSeconds.coerceAtLeast(0.0) * 1000.0).roundToLong()}"

    private companion object {
        private const val IDLE_SLEEP_MS = 8L
        private const val INPUT_TIMEOUT_US = 0L
        private const val OUTPUT_TIMEOUT_US = 10_000L
        private const val END_TOLERANCE_US = 1_000L
        private const val PCM_BYTES_PER_SAMPLE = 2
    }
}
