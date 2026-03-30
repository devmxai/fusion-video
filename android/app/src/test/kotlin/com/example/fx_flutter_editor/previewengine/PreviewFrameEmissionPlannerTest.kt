package com.example.fx_flutter_editor.previewengine

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PreviewFrameEmissionPlannerTest {
    @Test
    fun `steady playing video tick can be coalesced`() {
        val previous =
            sampleRequest(
                sourcePositionSeconds = 1.000,
                timelinePositionSeconds = 1.000,
            )
        val current =
            sampleRequest(
                sourcePositionSeconds = 1.016,
                timelinePositionSeconds = 1.016,
            )

        assertFalse(
            PreviewFrameEmissionPlanner.shouldEmit(
                previous = previous,
                current = current,
                nowRealtimeMs = 1016L,
                lastEmitRealtimeMs = 1000L,
            ),
        )
    }

    @Test
    fun `steady playing video emits after interval`() {
        val previous =
            sampleRequest(
                sourcePositionSeconds = 1.000,
                timelinePositionSeconds = 1.000,
            )
        val current =
            sampleRequest(
                sourcePositionSeconds = 1.032,
                timelinePositionSeconds = 1.032,
            )

        assertTrue(
            PreviewFrameEmissionPlanner.shouldEmit(
                previous = previous,
                current = current,
                nowRealtimeMs = 1050L,
                lastEmitRealtimeMs = 1000L,
            ),
        )
    }

    @Test
    fun `transport change always emits`() {
        val previous = sampleRequest(transportRevision = 4)
        val current = sampleRequest(transportRevision = 5)

        assertTrue(
            PreviewFrameEmissionPlanner.shouldEmit(
                previous = previous,
                current = current,
                nowRealtimeMs = 1005L,
                lastEmitRealtimeMs = 1000L,
            ),
        )
    }

    private fun sampleRequest(
        transportRevision: Int = 4,
        sourcePositionSeconds: Double = 1.0,
        timelinePositionSeconds: Double = 1.0,
    ): ResolvedPreviewFrameRequest =
        ResolvedPreviewFrameRequest(
            projectId = 7,
            transportRevision = transportRevision,
            transportKind = "playbackTick",
            baseClipId = "clip-a",
            sourceId = "clip-a",
            sourcePath = "/tmp/source.mp4",
            sourceKind = "video",
            timelinePositionSeconds = timelinePositionSeconds,
            sourcePositionSeconds = sourcePositionSeconds,
            clipStartSeconds = 0.0,
            clipEndSeconds = 5.0,
            sourceStartSeconds = 0.0,
            sourceEndSeconds = 5.0,
            projectWidth = 1080,
            projectHeight = 1920,
            continuityKind = "sameSourceContiguous",
            isPlaying = true,
            frameToken = "video:/tmp/source.mp4:${(sourcePositionSeconds * 1000.0).toInt()}",
        )
}
