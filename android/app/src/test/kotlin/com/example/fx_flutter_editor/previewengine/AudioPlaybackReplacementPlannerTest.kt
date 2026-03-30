package com.example.fx_flutter_editor.previewengine

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioPlaybackReplacementPlannerTest {
    @Test
    fun `same source contiguous audio tolerates larger restart drift`() {
        assertFalse(
            AudioPlaybackReplacementPlanner.shouldRestart(
                currentSourcePath = "/tmp/source.mp4",
                currentContinuityKind = "sameSourceContiguous",
                currentSourceStartUs = 0L,
                currentSourceEndUs = 1_000_000L,
                currentEnforceSourceWindow = false,
                replacementSourcePath = "/tmp/source.mp4",
                replacementContinuityKind = "sameSourceContiguous",
                replacementSourceStartUs = 1_000_000L,
                replacementSourceEndUs = 2_000_000L,
                replacementEnforceSourceWindow = false,
                replacementSourcePositionUs = 1_180_000L,
                currentRenderedSourceUs = 1_020_000L,
            ),
        )
    }

    @Test
    fun `audio restart occurs when source changes`() {
        assertTrue(
            AudioPlaybackReplacementPlanner.shouldRestart(
                currentSourcePath = "/tmp/left.mp4",
                currentContinuityKind = "sameSourceContiguous",
                currentSourceStartUs = 0L,
                currentSourceEndUs = 1_000_000L,
                currentEnforceSourceWindow = false,
                replacementSourcePath = "/tmp/right.mp4",
                replacementContinuityKind = "differentSource",
                replacementSourceStartUs = 0L,
                replacementSourceEndUs = 1_000_000L,
                replacementEnforceSourceWindow = true,
                replacementSourcePositionUs = 0L,
                currentRenderedSourceUs = 900_000L,
            ),
        )
    }

    @Test
    fun `same source contiguous audio can resume with slightly larger drift`() {
        assertTrue(
            AudioPlaybackReplacementPlanner.canResumePausedSession(
                continuityKind = "sameSourceContiguous",
                targetSourcePositionUs = 1_120_000L,
                currentSourcePositionUs = 1_000_000L,
            ),
        )
        assertFalse(
            AudioPlaybackReplacementPlanner.canResumePausedSession(
                continuityKind = "sameSourceNonContiguous",
                targetSourcePositionUs = 1_120_000L,
                currentSourcePositionUs = 1_000_000L,
            ),
        )
    }

    @Test
    fun `retarget remains conservative for non contiguous audio`() {
        assertFalse(
            AudioPlaybackReplacementPlanner.shouldRetargetActiveSession(
                continuityKind = "sameSourceNonContiguous",
                targetSourcePositionUs = 1_100_000L,
                currentSourcePositionUs = 980_000L,
            ),
        )
        assertTrue(
            AudioPlaybackReplacementPlanner.shouldRetargetActiveSession(
                continuityKind = "sameSourceNonContiguous",
                targetSourcePositionUs = 1_220_000L,
                currentSourcePositionUs = 980_000L,
            ),
        )
    }
}
