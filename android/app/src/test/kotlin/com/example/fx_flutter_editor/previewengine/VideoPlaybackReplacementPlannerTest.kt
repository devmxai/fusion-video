package com.example.fx_flutter_editor.previewengine

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VideoPlaybackReplacementPlannerTest {
    @Test
    fun `active same source contiguous session tolerates small drift`() {
        assertFalse(
            VideoPlaybackReplacementPlanner.shouldRetargetActiveSession(
                continuityKind = "sameSourceContiguous",
                targetSourcePositionUs = 1_140_000L,
                currentSourcePositionUs = 1_000_000L,
            ),
        )
    }

    @Test
    fun `active bounded session retargets on large drift`() {
        assertTrue(
            VideoPlaybackReplacementPlanner.shouldRetargetActiveSession(
                continuityKind = "sameSourceNonContiguous",
                targetSourcePositionUs = 1_200_000L,
                currentSourcePositionUs = 1_000_000L,
            ),
        )
    }

    @Test
    fun `same source contiguous replacement tolerates small drift`() {
        assertFalse(
            VideoPlaybackReplacementPlanner.shouldRestart(
                currentSourcePath = "/tmp/source.mp4",
                currentContinuityKind = "sameSourceContiguous",
                currentSourceStartUs = 0L,
                currentSourceEndUs = null,
                currentEnforceSourceWindow = false,
                replacementSourcePath = "/tmp/source.mp4",
                replacementContinuityKind = "sameSourceContiguous",
                replacementSourceStartUs = 1_000_000L,
                replacementSourceEndUs = null,
                replacementEnforceSourceWindow = false,
                replacementSourcePositionUs = 1_140_000L,
                lastRenderedSourceUs = 1_000_000L,
            ),
        )
    }

    @Test
    fun `same source contiguous replacement restarts on large drift`() {
        assertTrue(
            VideoPlaybackReplacementPlanner.shouldRestart(
                currentSourcePath = "/tmp/source.mp4",
                currentContinuityKind = "sameSourceContiguous",
                currentSourceStartUs = 0L,
                currentSourceEndUs = null,
                currentEnforceSourceWindow = false,
                replacementSourcePath = "/tmp/source.mp4",
                replacementContinuityKind = "sameSourceContiguous",
                replacementSourceStartUs = 1_000_000L,
                replacementSourceEndUs = null,
                replacementEnforceSourceWindow = false,
                replacementSourcePositionUs = 1_220_000L,
                lastRenderedSourceUs = 1_000_000L,
            ),
        )
    }

    @Test
    fun `different source always restarts`() {
        assertTrue(
            VideoPlaybackReplacementPlanner.shouldRestart(
                currentSourcePath = "/tmp/source-a.mp4",
                currentContinuityKind = "differentSource",
                currentSourceStartUs = 0L,
                currentSourceEndUs = 2_000_000L,
                currentEnforceSourceWindow = true,
                replacementSourcePath = "/tmp/source-b.mp4",
                replacementContinuityKind = "differentSource",
                replacementSourceStartUs = 0L,
                replacementSourceEndUs = 2_000_000L,
                replacementEnforceSourceWindow = true,
                replacementSourcePositionUs = 1_000_000L,
                lastRenderedSourceUs = 900_000L,
            ),
        )
    }

    @Test
    fun `bounded source window change restarts`() {
        assertTrue(
            VideoPlaybackReplacementPlanner.shouldRestart(
                currentSourcePath = "/tmp/source.mp4",
                currentContinuityKind = "sameSourceNonContiguous",
                currentSourceStartUs = 0L,
                currentSourceEndUs = 1_000_000L,
                currentEnforceSourceWindow = true,
                replacementSourcePath = "/tmp/source.mp4",
                replacementContinuityKind = "sameSourceNonContiguous",
                replacementSourceStartUs = 2_000_000L,
                replacementSourceEndUs = 3_000_000L,
                replacementEnforceSourceWindow = true,
                replacementSourcePositionUs = 2_050_000L,
                lastRenderedSourceUs = 900_000L,
            ),
        )
    }
}
