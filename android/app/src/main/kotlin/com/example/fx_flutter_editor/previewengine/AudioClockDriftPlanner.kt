package com.example.fx_flutter_editor.previewengine

import kotlin.math.abs

internal object AudioClockDriftPlanner {
    fun shouldSyncFromRenderedFrame(
        lastSyncRealtimeMs: Long,
        nowRealtimeMs: Long,
    ): Boolean {
        if (lastSyncRealtimeMs <= 0L) {
            return true
        }
        return nowRealtimeMs - lastSyncRealtimeMs >= MIN_SYNC_INTERVAL_MS
    }

    fun shouldCorrectPlayback(
        currentPositionMs: Int,
        targetPositionMs: Int,
        lastCorrectionRealtimeMs: Long,
        nowRealtimeMs: Long,
    ): Boolean {
        val driftMs = abs(currentPositionMs - targetPositionMs)
        if (driftMs < HARD_DRIFT_TOLERANCE_MS) {
            return false
        }
        if (lastCorrectionRealtimeMs <= 0L) {
            return true
        }
        return nowRealtimeMs - lastCorrectionRealtimeMs >= MIN_CORRECTION_INTERVAL_MS
    }

    private const val HARD_DRIFT_TOLERANCE_MS = 160
    private const val MIN_CORRECTION_INTERVAL_MS = 240L
    private const val MIN_SYNC_INTERVAL_MS = 120L
}
