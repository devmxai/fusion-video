package com.example.fx_flutter_editor.previewengine

import android.os.SystemClock
import kotlin.math.roundToInt

class AndroidAudioEngine(
    private val codecSession: AndroidCodecAudioSession = AndroidCodecAudioSession(),
) {
    val runtimeSnapshot: AndroidCodecAudioSession.RuntimeSnapshot
        get() = codecSession.runtimeSnapshot

    private var activeSessionKey: String? = null
    private var latestRequest: ResolvedPreviewAudioRequest? = null
    private var isPlaying: Boolean = false
    private var lastCorrectionRealtimeMs: Long = 0L
    private var lastPlaybackStartRealtimeMs: Long = 0L

    fun play(request: ResolvedPreviewAudioRequest) {
        if (request.isMuted || request.gain <= MIN_AUDIBLE_GAIN) {
            stopInternal()
            return
        }
        latestRequest = request
        val targetPositionMs = request.sourcePositionMillis
        val nowRealtimeMs = SystemClock.elapsedRealtime()
        if (
            activeSessionKey == request.sessionKey &&
                !isPlaying &&
                codecSession.canResume(
                    sessionKey = request.sessionKey,
                    continuityKind = request.continuityKind,
                    targetPositionMs = targetPositionMs,
                )
        ) {
            codecSession.setGain(request.volumeLevel)
            codecSession.resume()
            isPlaying = true
            lastCorrectionRealtimeMs = nowRealtimeMs
            lastPlaybackStartRealtimeMs = nowRealtimeMs
            return
        }
        if (activeSessionKey != request.sessionKey || !isPlaying) {
            codecSession.play(request)
            activeSessionKey = request.sessionKey
            isPlaying = true
            lastCorrectionRealtimeMs = nowRealtimeMs
            lastPlaybackStartRealtimeMs = nowRealtimeMs
            return
        }
        codecSession.setGain(request.volumeLevel)
        if (
            AudioPlaybackReplacementPlanner.shouldRetargetActiveSession(
                continuityKind = request.continuityKind,
                targetSourcePositionUs = targetPositionMs.toLong() * 1_000L,
                currentSourcePositionUs = codecSession.currentPositionMs.toLong() * 1_000L,
            )
        ) {
            codecSession.play(request)
            lastCorrectionRealtimeMs = nowRealtimeMs
            lastPlaybackStartRealtimeMs = nowRealtimeMs
        }
    }

    fun pause(request: ResolvedPreviewAudioRequest?) {
        request?.let {
            latestRequest = it
            activeSessionKey = it.sessionKey
        }
        isPlaying = false
        codecSession.pause()
    }

    fun syncPlayback(request: ResolvedPreviewAudioRequest) {
        latestRequest = request
        if (request.isMuted || request.gain <= MIN_AUDIBLE_GAIN) {
            codecSession.setGain(0f)
            return
        }
        codecSession.setGain(request.volumeLevel)
        if (activeSessionKey != request.sessionKey || !isPlaying) {
            play(request)
            return
        }
        val targetPositionMs = request.sourcePositionMillis
        val nowRealtimeMs = SystemClock.elapsedRealtime()
        if (
            lastPlaybackStartRealtimeMs > 0L &&
                nowRealtimeMs - lastPlaybackStartRealtimeMs < STARTUP_CORRECTION_GRACE_MS
        ) {
            return
        }
        if (
            AudioClockDriftPlanner.shouldCorrectPlayback(
                currentPositionMs = codecSession.currentPositionMs,
                targetPositionMs = targetPositionMs,
                lastCorrectionRealtimeMs = lastCorrectionRealtimeMs,
                nowRealtimeMs = nowRealtimeMs,
            ) &&
                AudioPlaybackReplacementPlanner.shouldRetargetActiveSession(
                    continuityKind = request.continuityKind,
                    targetSourcePositionUs = targetPositionMs.toLong() * 1_000L,
                    currentSourcePositionUs = codecSession.currentPositionMs.toLong() * 1_000L,
                )
        ) {
            codecSession.play(request)
            lastCorrectionRealtimeMs = nowRealtimeMs
        }
    }

    fun stop() {
        stopInternal()
    }

    fun flush() {
        stop()
    }

    private fun stopInternal() {
        isPlaying = false
        activeSessionKey = null
        latestRequest = null
        lastCorrectionRealtimeMs = 0L
        lastPlaybackStartRealtimeMs = 0L
        codecSession.stop()
    }

    private val ResolvedPreviewAudioRequest.sourcePositionMillis: Int
        get() = (sourcePositionSeconds.coerceAtLeast(0.0) * 1000.0).roundToInt()

    private val ResolvedPreviewAudioRequest.volumeLevel: Float
        get() = if (isMuted) 0f else gain.coerceIn(0.0, 1.0).toFloat()

    private companion object {
        private const val MIN_AUDIBLE_GAIN = 0.0001
        private const val STARTUP_CORRECTION_GRACE_MS = 420L
    }
}
