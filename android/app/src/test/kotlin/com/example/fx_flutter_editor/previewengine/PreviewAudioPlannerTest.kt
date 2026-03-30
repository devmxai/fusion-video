package com.example.fx_flutter_editor.previewengine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Test

class PreviewAudioPlannerTest {
    @Test
    fun `remaining split segment keeps audio source offset after deleting first half`() {
        val configuration =
            ResolvedPreviewConfiguration(
                projectId = 5,
                positionSeconds = 0.0,
                isPlaying = false,
                transportRevision = 11,
                sourceId = "clip-b",
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
                baseClipId = "clip-b",
                baseClipIds = listOf("clip-b"),
                selectedClipId = null,
                continuityKind = "sameSourceContiguous",
                sceneNodes = emptyList(),
                audioNodes =
                    listOf(
                        mapOf(
                            "clipId" to "clip-b",
                            "kind" to "video",
                            "localPath" to "/tmp/source.mp4",
                            "clipStartSeconds" to 0.0,
                            "clipEndSeconds" to 30.0,
                            "sourceStartSeconds" to 30.0,
                            "sourceEndSeconds" to 60.0,
                            "gain" to 1.0,
                            "isMuted" to false,
                        ),
                    ),
            )

        val request =
            PreviewAudioPlanner.resolveAudioRequest(
                configuration = configuration,
                timelinePositionSeconds = 0.0,
                transportRevision = 11,
                isPlaying = false,
            )

        assertNotNull(request)
        assertEquals(30.0, request?.sourcePositionSeconds ?: 0.0, 0.0001)
        assertEquals("/tmp/source.mp4", request?.sourcePath)
    }

    @Test
    fun `same source contiguous audio keeps stable session key across clip windows`() {
        val leftRequest =
            ResolvedPreviewAudioRequest(
                projectId = 7,
                clipId = "clip-left",
                sourcePath = "/tmp/source.mp4",
                sourceKind = "video",
                continuityKind = "sameSourceContiguous",
                timelinePositionSeconds = 0.5,
                sourcePositionSeconds = 0.5,
                clipStartSeconds = 0.0,
                clipEndSeconds = 1.0,
                sourceStartSeconds = 0.0,
                sourceEndSeconds = 1.0,
                gain = 1.0,
                isMuted = false,
                transportRevision = 11,
                isPlaying = true,
            )
        val rightRequest =
            leftRequest.copy(
                clipId = "clip-right",
                timelinePositionSeconds = 1.2,
                sourcePositionSeconds = 1.2,
                clipStartSeconds = 1.0,
                clipEndSeconds = 2.0,
                sourceStartSeconds = 1.0,
                sourceEndSeconds = 2.0,
                transportRevision = 12,
            )

        assertEquals(leftRequest.sessionKey, rightRequest.sessionKey)
    }

    @Test
    fun `different source windows still produce distinct audio sessions`() {
        val leftRequest =
            ResolvedPreviewAudioRequest(
                projectId = 7,
                clipId = "clip-left",
                sourcePath = "/tmp/source.mp4",
                sourceKind = "video",
                continuityKind = "sameSourceNonContiguous",
                timelinePositionSeconds = 0.5,
                sourcePositionSeconds = 0.5,
                clipStartSeconds = 0.0,
                clipEndSeconds = 1.0,
                sourceStartSeconds = 0.0,
                sourceEndSeconds = 1.0,
                gain = 1.0,
                isMuted = false,
                transportRevision = 11,
                isPlaying = true,
            )
        val rightRequest =
            leftRequest.copy(
                clipId = "clip-right",
                timelinePositionSeconds = 3.2,
                sourcePositionSeconds = 7.2,
                clipStartSeconds = 3.0,
                clipEndSeconds = 4.0,
                sourceStartSeconds = 7.0,
                sourceEndSeconds = 8.0,
                transportRevision = 12,
            )

        assertNotEquals(leftRequest.sessionKey, rightRequest.sessionKey)
    }
}
