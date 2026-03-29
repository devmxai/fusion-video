package com.example.fx_flutter_editor

import kotlin.math.abs
import kotlin.math.roundToInt

internal data class PreviewTransportDecision(
    val targetPositionMs: Int,
    val shouldSeek: Boolean,
    val shouldPauseImmediately: Boolean,
    val shouldStartImmediately: Boolean,
    val shouldStartAfterSeek: Boolean,
)

internal object PreviewTransportPlanner {
    fun decide(
        desiredPositionSeconds: Double,
        sourceStartSeconds: Double,
        sourceEndSeconds: Double?,
        playerPositionMs: Int,
        isPlaying: Boolean,
        shouldRetarget: Boolean,
    ): PreviewTransportDecision {
        val lowerBoundMs = (sourceStartSeconds * 1000.0).roundToInt().coerceAtLeast(0)
        val upperBoundMs = sourceEndSeconds
            ?.let { (it * 1000.0).roundToInt().coerceAtLeast(lowerBoundMs) }
        val unclampedTargetMs = (desiredPositionSeconds * 1000.0).roundToInt().coerceAtLeast(0)
        val targetPositionMs = when (upperBoundMs) {
            null -> unclampedTargetMs.coerceAtLeast(lowerBoundMs)
            else -> unclampedTargetMs.coerceIn(lowerBoundMs, upperBoundMs)
        }
        val seekThresholdMs = if (isPlaying) 180 else 40
        val shouldSeek =
            shouldRetarget && abs(playerPositionMs - targetPositionMs) > seekThresholdMs

        return PreviewTransportDecision(
            targetPositionMs = targetPositionMs,
            shouldSeek = shouldSeek,
            shouldPauseImmediately = !isPlaying || shouldSeek,
            shouldStartImmediately = isPlaying && !shouldSeek,
            shouldStartAfterSeek = isPlaying && shouldSeek,
        )
    }
}
