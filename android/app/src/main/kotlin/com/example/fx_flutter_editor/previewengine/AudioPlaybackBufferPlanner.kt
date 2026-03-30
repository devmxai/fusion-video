package com.example.fx_flutter_editor.previewengine

import android.media.AudioFormat

internal object AudioPlaybackBufferPlanner {
    fun shouldStartPlayback(
        queuedBytes: Int,
        sampleRate: Int,
        channelCount: Int,
        encoding: Int,
    ): Boolean {
        if (queuedBytes <= 0 || sampleRate <= 0 || channelCount <= 0) {
            return false
        }
        val bytesPerSample =
            when (encoding) {
                AudioFormat.ENCODING_PCM_8BIT -> 1
                AudioFormat.ENCODING_PCM_FLOAT -> 4
                else -> 2
            }
        val bytesPerSecond = sampleRate * channelCount * bytesPerSample
        if (bytesPerSecond <= 0) {
            return true
        }
        val queuedDurationMs = (queuedBytes * 1000L) / bytesPerSecond.toLong()
        return queuedDurationMs >= MIN_START_BUFFER_MS
    }

    private const val MIN_START_BUFFER_MS = 24L
}
