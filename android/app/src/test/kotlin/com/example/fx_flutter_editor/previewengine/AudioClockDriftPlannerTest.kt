package com.example.fx_flutter_editor.previewengine

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioClockDriftPlannerTest {
    @Test
    fun `allows initial rendered frame sync immediately`() {
        assertTrue(
            AudioClockDriftPlanner.shouldSyncFromRenderedFrame(
                lastSyncRealtimeMs = 0,
                nowRealtimeMs = 2_000,
            ),
        )
    }

    @Test
    fun `rate limits rendered frame sync sampling`() {
        assertFalse(
            AudioClockDriftPlanner.shouldSyncFromRenderedFrame(
                lastSyncRealtimeMs = 2_000,
                nowRealtimeMs = 2_080,
            ),
        )
        assertTrue(
            AudioClockDriftPlanner.shouldSyncFromRenderedFrame(
                lastSyncRealtimeMs = 2_000,
                nowRealtimeMs = 2_140,
            ),
        )
    }

    @Test
    fun `ignores small playback drift`() {
        assertFalse(
            AudioClockDriftPlanner.shouldCorrectPlayback(
                currentPositionMs = 1_000,
                targetPositionMs = 1_110,
                lastCorrectionRealtimeMs = 2_000,
                nowRealtimeMs = 2_100,
            ),
        )
    }

    @Test
    fun `corrects large drift when no previous correction exists`() {
        assertTrue(
            AudioClockDriftPlanner.shouldCorrectPlayback(
                currentPositionMs = 1_000,
                targetPositionMs = 1_240,
                lastCorrectionRealtimeMs = 0,
                nowRealtimeMs = 2_000,
            ),
        )
    }

    @Test
    fun `rate limits repeated correction requests`() {
        assertFalse(
            AudioClockDriftPlanner.shouldCorrectPlayback(
                currentPositionMs = 1_000,
                targetPositionMs = 1_300,
                lastCorrectionRealtimeMs = 2_000,
                nowRealtimeMs = 2_100,
            ),
        )
        assertTrue(
            AudioClockDriftPlanner.shouldCorrectPlayback(
                currentPositionMs = 1_000,
                targetPositionMs = 1_300,
                lastCorrectionRealtimeMs = 2_000,
                nowRealtimeMs = 2_300,
            ),
        )
    }
}
