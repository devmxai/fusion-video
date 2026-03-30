package com.example.fx_flutter_editor.previewengine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class PreviewFramePlannerTest {
    @Test
    fun `remaining split segment keeps source offset after deleting first half`() {
        val configuration =
            ResolvedPreviewConfiguration(
                projectId = 7,
                positionSeconds = 0.0,
                isPlaying = false,
                transportRevision = 3,
                sourceId = "video-b",
                sourcePath = "/tmp/source.mp4",
                sourceKind = "video",
                upcomingSourceId = null,
                upcomingSourcePath = null,
                upcomingSourceKind = null,
                clipStartSeconds = 0.0,
                clipEndSeconds = 30.0,
                sourceStartSeconds = 30.0,
                sourceEndSeconds = 60.0,
                upcomingSourceStartSeconds = null,
                upcomingSourceEndSeconds = null,
                projectWidth = 1080,
                projectHeight = 1920,
                baseClipId = null,
                baseClipIds = emptyList(),
                selectedClipId = null,
                continuityKind = "sameSourceContiguous",
                sceneNodes = emptyList(),
                audioNodes = emptyList(),
            )

        val frameRequest =
            PreviewFramePlanner.resolveFrameRequest(
                configuration = configuration,
                timelinePositionSeconds = 0.0,
                isPlaying = false,
                transportRevision = 3,
                transportKind = "seek",
            )

        assertNotNull(frameRequest)
        assertEquals(30.0, frameRequest?.sourcePositionSeconds ?: 0.0, 0.0001)
    }

    @Test
    fun `timeline position clamps to derived clip end from source bounds`() {
        val configuration =
            ResolvedPreviewConfiguration(
                projectId = 7,
                positionSeconds = 0.0,
                isPlaying = true,
                transportRevision = 8,
                sourceId = "clip-a",
                sourcePath = "/tmp/source.mp4",
                sourceKind = "video",
                upcomingSourceId = null,
                upcomingSourcePath = null,
                upcomingSourceKind = null,
                clipStartSeconds = 2.0,
                clipEndSeconds = null,
                sourceStartSeconds = 10.0,
                sourceEndSeconds = 15.0,
                upcomingSourceStartSeconds = null,
                upcomingSourceEndSeconds = null,
                projectWidth = 1080,
                projectHeight = 1920,
                baseClipId = null,
                baseClipIds = emptyList(),
                selectedClipId = null,
                continuityKind = "sameSourceNonContiguous",
                sceneNodes = emptyList(),
                audioNodes = emptyList(),
            )

        val frameRequest =
            PreviewFramePlanner.resolveFrameRequest(
                configuration = configuration,
                timelinePositionSeconds = 99.0,
                isPlaying = true,
                transportRevision = 8,
                transportKind = "play",
            )

        assertNotNull(frameRequest)
        assertEquals(7.0, frameRequest?.timelinePositionSeconds ?: 0.0, 0.0001)
        assertEquals(15.0, frameRequest?.sourcePositionSeconds ?: 0.0, 0.0001)
    }
}
