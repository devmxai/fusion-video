package com.example.fx_flutter_editor.previewengine

import kotlin.math.abs

internal object PreviewFrameEmissionPlanner {
    fun shouldEmit(
        previous: ResolvedPreviewFrameRequest?,
        current: ResolvedPreviewFrameRequest?,
        nowRealtimeMs: Long,
        lastEmitRealtimeMs: Long,
        force: Boolean = false,
    ): Boolean {
        if (force) {
            return true
        }
        if (previous == null || current == null) {
            return true
        }
        if (previous.isPlaying != current.isPlaying) {
            return true
        }
        if (previous.sourceKind != current.sourceKind) {
            return true
        }
        if (previous.sourcePath != current.sourcePath) {
            return true
        }
        if (previous.sourceId != current.sourceId) {
            return true
        }
        if (previous.transportRevision != current.transportRevision) {
            return true
        }
        if (previous.continuityKind != current.continuityKind) {
            return true
        }
        if (
            previous.clipStartSeconds != current.clipStartSeconds ||
                previous.clipEndSeconds != current.clipEndSeconds ||
                previous.sourceStartSeconds != current.sourceStartSeconds ||
                previous.sourceEndSeconds != current.sourceEndSeconds
        ) {
            return true
        }
        if (
            previous.projectWidth != current.projectWidth ||
                previous.projectHeight != current.projectHeight
        ) {
            return true
        }
        if (!current.isPlaying || current.sourceKind != "video") {
            return previous.frameToken != current.frameToken
        }
        if (
            abs((previous.sourcePositionSeconds ?: 0.0) - (current.sourcePositionSeconds ?: 0.0)) >=
                PLAYING_VIDEO_POSITION_STEP_SECONDS
        ) {
            return true
        }
        return nowRealtimeMs - lastEmitRealtimeMs >= PLAYING_VIDEO_EMIT_INTERVAL_MS
    }

    private const val PLAYING_VIDEO_EMIT_INTERVAL_MS = 48L
    private const val PLAYING_VIDEO_POSITION_STEP_SECONDS = 0.048
}
