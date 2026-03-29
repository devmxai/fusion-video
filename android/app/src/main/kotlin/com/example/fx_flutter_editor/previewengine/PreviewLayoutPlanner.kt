package com.example.fx_flutter_editor.previewengine

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

data class PreviewNodeLayout(
    val left: Int,
    val top: Int,
    val width: Int,
    val height: Int,
    val rotationDegrees: Float,
)

data class PreviewContentLayout(
    val left: Int,
    val top: Int,
    val width: Int,
    val height: Int,
    val rotationDegrees: Float,
)

object PreviewLayoutPlanner {
    fun resolveNodeLayout(
        parentWidth: Int,
        parentHeight: Int,
        projectWidth: Int,
        projectHeight: Int,
        sceneNode: Map<String, Any?>?,
    ): PreviewNodeLayout {
        val safeProjectWidth = max(1, projectWidth)
        val safeProjectHeight = max(1, projectHeight)
        val safeParentWidth = max(1, parentWidth)
        val safeParentHeight = max(1, parentHeight)
        val scaleX = safeParentWidth.toFloat() / safeProjectWidth.toFloat()
        val scaleY = safeParentHeight.toFloat() / safeProjectHeight.toFloat()
        val nodeLeft =
            (((sceneNode?.get("x") as? Number)?.toDouble() ?: 0.0) * scaleX)
                .roundToInt()
                .coerceAtLeast(0)
        val nodeTop =
            (((sceneNode?.get("y") as? Number)?.toDouble() ?: 0.0) * scaleY)
                .roundToInt()
                .coerceAtLeast(0)
        val nodeWidth =
            (((sceneNode?.get("width") as? Number)?.toDouble()
                ?: safeProjectWidth.toDouble()) * scaleX)
                .roundToInt()
                .coerceAtLeast(1)
        val nodeHeight =
            (((sceneNode?.get("height") as? Number)?.toDouble()
                ?: safeProjectHeight.toDouble()) * scaleY)
                .roundToInt()
                .coerceAtLeast(1)
        val nodeRotation =
            ((sceneNode?.get("rotationDegrees") as? Number)?.toFloat() ?: 0f)
        return PreviewNodeLayout(
            left = nodeLeft,
            top = nodeTop,
            width = nodeWidth,
            height = nodeHeight,
            rotationDegrees = nodeRotation,
        )
    }

    fun resolveContentLayout(
        containerWidth: Int,
        containerHeight: Int,
        mediaWidth: Int?,
        mediaHeight: Int?,
        mediaRotationDegrees: Int,
    ): PreviewContentLayout {
        val safeContainerWidth = max(1, containerWidth)
        val safeContainerHeight = max(1, containerHeight)
        val normalizedRotation = normalizeRotation(mediaRotationDegrees)
        val quarterTurn = abs(normalizedRotation) == 90
        val rawMediaWidth = max(1, mediaWidth ?: safeContainerWidth)
        val rawMediaHeight = max(1, mediaHeight ?: safeContainerHeight)
        val displayWidth = if (quarterTurn) rawMediaHeight else rawMediaWidth
        val displayHeight = if (quarterTurn) rawMediaWidth else rawMediaHeight
        val fitScale =
            min(
                safeContainerWidth.toFloat() / displayWidth.toFloat(),
                safeContainerHeight.toFloat() / displayHeight.toFloat(),
            )
        val fittedDisplayWidth =
            (displayWidth.toFloat() * fitScale).roundToInt().coerceAtLeast(1)
        val fittedDisplayHeight =
            (displayHeight.toFloat() * fitScale).roundToInt().coerceAtLeast(1)
        val rotatedChildWidth =
            if (quarterTurn) fittedDisplayHeight else fittedDisplayWidth
        val rotatedChildHeight =
            if (quarterTurn) fittedDisplayWidth else fittedDisplayHeight
        return PreviewContentLayout(
            left = ((safeContainerWidth - rotatedChildWidth) / 2).coerceAtLeast(0),
            top = ((safeContainerHeight - rotatedChildHeight) / 2).coerceAtLeast(0),
            width = rotatedChildWidth,
            height = rotatedChildHeight,
            rotationDegrees = normalizedRotation.toFloat(),
        )
    }

    private fun normalizeRotation(rotationDegrees: Int): Int {
        val normalized = rotationDegrees % 360
        return when {
            normalized > 180 -> normalized - 360
            normalized < -180 -> normalized + 360
            else -> normalized
        }
    }
}
