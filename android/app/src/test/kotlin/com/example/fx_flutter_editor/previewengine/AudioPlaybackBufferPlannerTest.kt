package com.example.fx_flutter_editor.previewengine

import android.media.AudioFormat
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioPlaybackBufferPlannerTest {
    @Test
    fun `small queued audio does not start playback yet`() {
        assertFalse(
            AudioPlaybackBufferPlanner.shouldStartPlayback(
                queuedBytes = 2_048,
                sampleRate = 48_000,
                channelCount = 2,
                encoding = AudioFormat.ENCODING_PCM_16BIT,
            ),
        )
    }

    @Test
    fun `sufficient queued audio starts playback`() {
        assertTrue(
            AudioPlaybackBufferPlanner.shouldStartPlayback(
                queuedBytes = 5_120,
                sampleRate = 48_000,
                channelCount = 2,
                encoding = AudioFormat.ENCODING_PCM_16BIT,
            ),
        )
    }
}
