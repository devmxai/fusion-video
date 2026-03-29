package com.example.fx_flutter_editor

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PreviewTransportPlannerTest {
    @Test
    fun `scrub seek resolves exact paused preview target`() {
        val decision = PreviewTransportPlanner.decide(
            desiredPositionSeconds = 5.25,
            sourceStartSeconds = 0.0,
            sourceEndSeconds = 18.0,
            playerPositionMs = 0,
            isPlaying = false,
            shouldRetarget = true,
        )

        assertEquals(5250, decision.targetPositionMs)
        assertTrue(decision.shouldSeek)
        assertTrue(decision.shouldPauseImmediately)
        assertFalse(decision.shouldStartImmediately)
        assertFalse(decision.shouldStartAfterSeek)
    }

    @Test
    fun `play starts from scrubbed position instead of source start`() {
        val decision = PreviewTransportPlanner.decide(
            desiredPositionSeconds = 16.8,
            sourceStartSeconds = 0.0,
            sourceEndSeconds = 18.0,
            playerPositionMs = 0,
            isPlaying = true,
            shouldRetarget = true,
        )

        assertEquals(16800, decision.targetPositionMs)
        assertTrue(decision.shouldSeek)
        assertFalse(decision.shouldStartImmediately)
        assertTrue(decision.shouldStartAfterSeek)
    }

    @Test
    fun `remaining right split keeps source offset after deleting first half`() {
        val decision = PreviewTransportPlanner.decide(
            desiredPositionSeconds = 3.0,
            sourceStartSeconds = 3.0,
            sourceEndSeconds = 6.0,
            playerPositionMs = 0,
            isPlaying = true,
            shouldRetarget = true,
        )

        assertEquals(3000, decision.targetPositionMs)
        assertTrue(decision.shouldSeek)
        assertTrue(decision.shouldStartAfterSeek)
    }

    @Test
    fun `target clamps to surviving clip bounds near clip end`() {
        val decision = PreviewTransportPlanner.decide(
            desiredPositionSeconds = 7.8,
            sourceStartSeconds = 3.0,
            sourceEndSeconds = 6.0,
            playerPositionMs = 3100,
            isPlaying = true,
            shouldRetarget = true,
        )

        assertEquals(6000, decision.targetPositionMs)
        assertTrue(decision.shouldSeek)
    }
}
