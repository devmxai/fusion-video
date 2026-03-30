package com.example.fx_flutter_editor.previewengine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidTimelineThumbnailRepositoryTest {
    @Test
    fun `reuses cached bytes across repeated requests`() {
        var loaderCalls = 0
        val repository =
            AndroidTimelineThumbnailRepository(
                mediaIo = AndroidMediaIo(),
                byteLoader = { _, _, _, _ ->
                    loaderCalls += 1
                    byteArrayOf(1, 2, 3)
                },
            )

        val first =
            repository.loadVideoThumbnails(
                path = "/tmp/video.mp4",
                timestampsSeconds = listOf(0.5, 1.0),
                targetWidth = 96,
                targetHeight = 68,
            )
        val second =
            repository.loadVideoThumbnails(
                path = "/tmp/video.mp4",
                timestampsSeconds = listOf(0.5, 1.0),
                targetWidth = 96,
                targetHeight = 68,
            )

        assertEquals(2, loaderCalls)
        assertEquals(2, first.size)
        assertEquals(2, second.size)
        assertTrue(first[0].isNotEmpty())
        assertTrue(second[1].isNotEmpty())
    }

    @Test
    fun `deduplicates repeated timestamps inside one request`() {
        var loaderCalls = 0
        val repository =
            AndroidTimelineThumbnailRepository(
                mediaIo = AndroidMediaIo(),
                byteLoader = { _, _, _, _ ->
                    loaderCalls += 1
                    byteArrayOf(4, 5, 6)
                },
            )

        val thumbnails =
            repository.loadVideoThumbnails(
                path = "/tmp/video.mp4",
                timestampsSeconds = listOf(0.5, 0.5, 0.52),
                targetWidth = 96,
                targetHeight = 68,
            )

        assertEquals(1, loaderCalls)
        assertEquals(3, thumbnails.size)
    }
}
