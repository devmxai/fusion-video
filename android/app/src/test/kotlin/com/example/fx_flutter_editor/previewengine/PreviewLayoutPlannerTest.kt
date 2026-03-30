package com.example.fx_flutter_editor.previewengine

import org.junit.Assert.assertEquals
import org.junit.Test

class PreviewLayoutPlannerTest {
    @Test
    fun `node layout scales project coordinates into parent bounds`() {
        val layout =
            PreviewLayoutPlanner.resolveNodeLayout(
                parentWidth = 540,
                parentHeight = 960,
                projectWidth = 1080,
                projectHeight = 1920,
                sceneNode =
                    mapOf(
                        "x" to 108.0,
                        "y" to 192.0,
                        "width" to 540.0,
                        "height" to 960.0,
                        "rotationDegrees" to 12.0,
                    ),
            )

        assertEquals(54, layout.left)
        assertEquals(96, layout.top)
        assertEquals(270, layout.width)
        assertEquals(480, layout.height)
        assertEquals(12f, layout.rotationDegrees)
        assertEquals(1f, layout.opacity)
    }

    @Test
    fun `node layout preserves negative offsets and clip opacity`() {
        val layout =
            PreviewLayoutPlanner.resolveNodeLayout(
                parentWidth = 540,
                parentHeight = 960,
                projectWidth = 1080,
                projectHeight = 1920,
                sceneNode =
                    mapOf(
                        "x" to -108.0,
                        "y" to -192.0,
                        "width" to 756.0,
                        "height" to 1344.0,
                        "rotationDegrees" to 0.0,
                        "opacity" to 0.64,
                    ),
            )

        assertEquals(-54, layout.left)
        assertEquals(-96, layout.top)
        assertEquals(378, layout.width)
        assertEquals(672, layout.height)
        assertEquals(0f, layout.rotationDegrees)
        assertEquals(0.64f, layout.opacity)
    }

    @Test
    fun `content layout swaps bounds for quarter turn video rotation`() {
        val layout =
            PreviewLayoutPlanner.resolveContentLayout(
                containerWidth = 540,
                containerHeight = 960,
                mediaWidth = 1920,
                mediaHeight = 1080,
                mediaRotationDegrees = 90,
            )

        assertEquals(-210, layout.left)
        assertEquals(210, layout.top)
        assertEquals(960, layout.width)
        assertEquals(540, layout.height)
        assertEquals(90f, layout.rotationDegrees)
    }

    @Test
    fun `content layout keeps portrait media inside portrait canvas`() {
        val layout =
            PreviewLayoutPlanner.resolveContentLayout(
                containerWidth = 540,
                containerHeight = 960,
                mediaWidth = 1080,
                mediaHeight = 1920,
                mediaRotationDegrees = 0,
            )

        assertEquals(0, layout.left)
        assertEquals(0, layout.top)
        assertEquals(540, layout.width)
        assertEquals(960, layout.height)
        assertEquals(0f, layout.rotationDegrees)
    }

    @Test
    fun `cover mode crops portrait media to fill project canvas without side bars`() {
        val layout =
            PreviewLayoutPlanner.resolveContentLayout(
                containerWidth = 540,
                containerHeight = 960,
                mediaWidth = 1080,
                mediaHeight = 1350,
                mediaRotationDegrees = 0,
                fitMode = PreviewContentFitMode.COVER,
            )

        assertEquals(-114, layout.left)
        assertEquals(0, layout.top)
        assertEquals(768, layout.width)
        assertEquals(960, layout.height)
    }

    @Test
    fun `contain mode keeps portrait media centered with bars when requested`() {
        val layout =
            PreviewLayoutPlanner.resolveContentLayout(
                containerWidth = 540,
                containerHeight = 960,
                mediaWidth = 1080,
                mediaHeight = 1350,
                mediaRotationDegrees = 0,
                fitMode = PreviewContentFitMode.CONTAIN,
            )

        assertEquals(0, layout.left)
        assertEquals(142, layout.top)
        assertEquals(540, layout.width)
        assertEquals(675, layout.height)
    }
}
