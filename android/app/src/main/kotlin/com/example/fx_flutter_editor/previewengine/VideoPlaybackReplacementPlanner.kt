package com.example.fx_flutter_editor.previewengine

import kotlin.math.abs

internal object VideoPlaybackReplacementPlanner {
    fun shouldRestart(
        currentSourcePath: String,
        currentContinuityKind: String?,
        currentSourceStartUs: Long,
        currentSourceEndUs: Long?,
        currentEnforceSourceWindow: Boolean,
        replacementSourcePath: String,
        replacementContinuityKind: String?,
        replacementSourceStartUs: Long,
        replacementSourceEndUs: Long?,
        replacementEnforceSourceWindow: Boolean,
        replacementSourcePositionUs: Long,
        lastRenderedSourceUs: Long,
    ): Boolean {
        if (replacementSourcePath != currentSourcePath) {
            return true
        }
        if (
            replacementEnforceSourceWindow &&
                currentEnforceSourceWindow &&
                (
                    replacementSourceStartUs != currentSourceStartUs ||
                        replacementSourceEndUs != currentSourceEndUs
                    )
        ) {
            return true
        }
        val allowedDriftUs =
            if (
                currentContinuityKind == "sameSourceContiguous" &&
                    replacementContinuityKind == "sameSourceContiguous"
            ) {
                SAME_SOURCE_CONTIGUOUS_RESTART_TOLERANCE_US
            } else {
                DEFAULT_RESTART_TOLERANCE_US
        }
        return abs(replacementSourcePositionUs - lastRenderedSourceUs) > allowedDriftUs
    }

    fun shouldRetargetActiveSession(
        continuityKind: String?,
        targetSourcePositionUs: Long,
        currentSourcePositionUs: Long,
    ): Boolean {
        val allowedDriftUs =
            if (continuityKind == "sameSourceContiguous") {
                SAME_SOURCE_CONTIGUOUS_RESTART_TOLERANCE_US
            } else {
                DEFAULT_RESTART_TOLERANCE_US
            }
        return abs(targetSourcePositionUs - currentSourcePositionUs) > allowedDriftUs
    }

    private const val DEFAULT_RESTART_TOLERANCE_US = 120_000L
    private const val SAME_SOURCE_CONTIGUOUS_RESTART_TOLERANCE_US = 180_000L
}
