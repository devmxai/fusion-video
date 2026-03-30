package com.example.fx_flutter_editor.previewengine

import kotlin.math.abs

internal object AudioPlaybackReplacementPlanner {
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
        currentRenderedSourceUs: Long,
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
                currentContinuityKind == SAME_SOURCE_CONTIGUOUS &&
                    replacementContinuityKind == SAME_SOURCE_CONTIGUOUS
            ) {
                SAME_SOURCE_CONTIGUOUS_RESTART_TOLERANCE_US
            } else {
                DEFAULT_RESTART_TOLERANCE_US
            }
        return abs(replacementSourcePositionUs - currentRenderedSourceUs) > allowedDriftUs
    }

    fun shouldRetargetActiveSession(
        continuityKind: String?,
        targetSourcePositionUs: Long,
        currentSourcePositionUs: Long,
    ): Boolean {
        val allowedDriftUs =
            if (continuityKind == SAME_SOURCE_CONTIGUOUS) {
                SAME_SOURCE_CONTIGUOUS_RESTART_TOLERANCE_US
            } else {
                DEFAULT_RESTART_TOLERANCE_US
            }
        return abs(targetSourcePositionUs - currentSourcePositionUs) > allowedDriftUs
    }

    fun canResumePausedSession(
        continuityKind: String?,
        targetSourcePositionUs: Long,
        currentSourcePositionUs: Long,
    ): Boolean {
        val allowedDriftUs =
            if (continuityKind == SAME_SOURCE_CONTIGUOUS) {
                SAME_SOURCE_CONTIGUOUS_RESUME_TOLERANCE_US
            } else {
                DEFAULT_RESUME_TOLERANCE_US
            }
        return abs(targetSourcePositionUs - currentSourcePositionUs) <= allowedDriftUs
    }

    private const val SAME_SOURCE_CONTIGUOUS = "sameSourceContiguous"
    private const val DEFAULT_RESTART_TOLERANCE_US = 160_000L
    private const val SAME_SOURCE_CONTIGUOUS_RESTART_TOLERANCE_US = 240_000L
    private const val DEFAULT_RESUME_TOLERANCE_US = 90_000L
    private const val SAME_SOURCE_CONTIGUOUS_RESUME_TOLERANCE_US = 140_000L
}
