package com.example.fx_flutter_editor.previewengine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackContinuityPlannerTest {
    private fun frameRequest(
        continuityKind: String?,
        sourcePath: String = "/tmp/video.mp4",
    ) = ResolvedPreviewFrameRequest(
        projectId = 1,
        transportRevision = 5,
        transportKind = "play",
        sourceId = "clip-a",
        sourcePath = sourcePath,
        sourceKind = "video",
        timelinePositionSeconds = 1.0,
        sourcePositionSeconds = 1.0,
        clipStartSeconds = 0.0,
        clipEndSeconds = 2.0,
        sourceStartSeconds = 0.0,
        sourceEndSeconds = 2.0,
        projectWidth = 1080,
        projectHeight = 1920,
        continuityKind = continuityKind,
        isPlaying = true,
        frameToken = "video:$sourcePath:1000",
    )

    @Test
    fun `same source contiguous video uses continuous stream session`() {
        val request = frameRequest(continuityKind = "sameSourceContiguous")
        assertTrue(PlaybackContinuityPlanner.usesContinuousStreamSession(request))
        assertFalse(PlaybackContinuityPlanner.shouldEnforceSourceWindow(request))
        assertEquals(
            "/tmp/video.mp4|video|continuous|5",
            PlaybackContinuityPlanner.buildPlaybackSessionKey(request),
        )
    }

    @Test
    fun `different source keeps bounded playback session`() {
        val request = frameRequest(continuityKind = "differentSource")
        assertFalse(PlaybackContinuityPlanner.usesContinuousStreamSession(request))
        assertTrue(PlaybackContinuityPlanner.shouldEnforceSourceWindow(request))
        assertEquals(
            "/tmp/video.mp4|0.0|2.0|5",
            PlaybackContinuityPlanner.buildPlaybackSessionKey(request),
        )
    }
}
