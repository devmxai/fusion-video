package com.example.fx_flutter_editor.previewengine

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.util.LinkedHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

data class DecodedPreviewFrameResult(
    val frameRequest: ResolvedPreviewFrameRequest,
    val bitmap: Bitmap?,
    val cacheHit: Boolean,
    val isStale: Boolean,
    val previewLatencyMillis: Double,
    val droppedFrameCount: Int,
)

class AndroidDecodeScheduler(
    private val executor: ExecutorService = Executors.newFixedThreadPool(2),
    private val prefetchExecutor: ExecutorService = Executors.newSingleThreadExecutor(),
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
) {
    private val lock = Any()
    private val latestSequenceByProject = mutableMapOf<Int, Long>()
    private val prefetchGenerationByProject = mutableMapOf<Int, Long>()
    private val pendingPrefetchKeys = mutableSetOf<String>()
    private val frameCache =
        object : LinkedHashMap<String, Bitmap>(24, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Bitmap>?): Boolean {
                return size > 24
            }
        }

    fun requestFrame(
        mediaIo: AndroidMediaIo,
        frameRequest: ResolvedPreviewFrameRequest,
        targetWidth: Int,
        targetHeight: Int,
        onFrameDecoded: (DecodedPreviewFrameResult) -> Unit,
    ) {
        val cacheKey = cacheKey(frameRequest, targetWidth, targetHeight)
        val startedRealtimeMs = SystemClock.elapsedRealtime()
        val sequence =
            synchronized(lock) {
                val nextSequence = (latestSequenceByProject[frameRequest.projectId] ?: 0L) + 1L
                latestSequenceByProject[frameRequest.projectId] = nextSequence
                nextSequence
            }

        val cachedFrame =
            synchronized(lock) {
                frameCache[cacheKey]
            }
        if (cachedFrame != null) {
            onFrameDecoded(
                DecodedPreviewFrameResult(
                    frameRequest = frameRequest,
                    bitmap = cachedFrame,
                    cacheHit = true,
                    isStale = false,
                    previewLatencyMillis = 0.0,
                    droppedFrameCount = 0,
                ),
            )
            prefetchContextFrames(mediaIo, frameRequest, targetWidth, targetHeight)
            return
        }

        executor.execute {
            if (shouldDropBeforeDecode(frameRequest.projectId, sequence)) {
                mainHandler.post {
                    onFrameDecoded(
                        DecodedPreviewFrameResult(
                            frameRequest = frameRequest,
                            bitmap = null,
                            cacheHit = false,
                            isStale = true,
                            previewLatencyMillis =
                                (SystemClock.elapsedRealtime() - startedRealtimeMs).toDouble(),
                            droppedFrameCount = 1,
                        ),
                    )
                }
                return@execute
            }
            val decodedBitmap =
                mediaIo.loadPreviewBitmap(
                    frameRequest = frameRequest,
                    targetWidth = targetWidth,
                    targetHeight = targetHeight,
                )
            if (decodedBitmap != null) {
                synchronized(lock) {
                    frameCache[cacheKey] = decodedBitmap
                }
            }
            val isStale =
                synchronized(lock) {
                    latestSequenceByProject[frameRequest.projectId] != sequence
                }
            prefetchContextFrames(mediaIo, frameRequest, targetWidth, targetHeight)
            mainHandler.post {
                onFrameDecoded(
                    DecodedPreviewFrameResult(
                        frameRequest = frameRequest,
                        bitmap = decodedBitmap,
                        cacheHit = false,
                        isStale = isStale,
                        previewLatencyMillis =
                            (SystemClock.elapsedRealtime() - startedRealtimeMs).toDouble(),
                        droppedFrameCount = if (isStale) 1 else 0,
                    ),
                )
            }
        }
    }

    fun cancelProject(projectId: Int) {
        synchronized(lock) {
            latestSequenceByProject.remove(projectId)
            prefetchGenerationByProject.remove(projectId)
        }
    }

    fun cancelProjectPrefetch(projectId: Int) {
        synchronized(lock) {
            prefetchGenerationByProject[projectId] =
                (prefetchGenerationByProject[projectId] ?: 0L) + 1L
        }
    }

    fun prefetchFrame(
        mediaIo: AndroidMediaIo,
        frameRequest: ResolvedPreviewFrameRequest,
        targetWidth: Int,
        targetHeight: Int,
    ) {
        val cacheKey = cacheKey(frameRequest, targetWidth, targetHeight)
        synchronized(lock) {
            if (frameCache.containsKey(cacheKey) || pendingPrefetchKeys.contains(cacheKey)) {
                return
            }
            pendingPrefetchKeys.add(cacheKey)
        }
        val prefetchGeneration =
            synchronized(lock) {
                prefetchGenerationByProject[frameRequest.projectId] ?: 0L
            }

        prefetchExecutor.execute {
            try {
                if (isPrefetchCancelled(frameRequest.projectId, prefetchGeneration)) {
                    return@execute
                }
                val bitmap =
                    mediaIo.loadPreviewBitmap(
                        frameRequest = frameRequest,
                        targetWidth = targetWidth,
                        targetHeight = targetHeight,
                    ) ?: return@execute
                if (isPrefetchCancelled(frameRequest.projectId, prefetchGeneration)) {
                    return@execute
                }
                synchronized(lock) {
                    frameCache[cacheKey] = bitmap
                }
            } finally {
                synchronized(lock) {
                    pendingPrefetchKeys.remove(cacheKey)
                }
            }
        }
    }

    fun reset() {
        synchronized(lock) {
            latestSequenceByProject.clear()
            prefetchGenerationByProject.clear()
            pendingPrefetchKeys.clear()
            frameCache.clear()
        }
    }

    private fun prefetchAdjacentFrames(
        mediaIo: AndroidMediaIo,
        frameRequest: ResolvedPreviewFrameRequest,
        targetWidth: Int,
        targetHeight: Int,
    ) {
        if (frameRequest.sourceKind != "video") {
            return
        }
        val sourcePositionSeconds = frameRequest.sourcePositionSeconds ?: return
        val frameStepSeconds =
            mediaIo.inspectVideoStream(frameRequest.sourcePath)?.frameStepSeconds ?: (1.0 / 30.0)
        val offsets =
            if (frameRequest.isPlaying) {
                listOf(1, 2)
            } else {
                listOf(-1, 1)
            }
        for (offset in offsets) {
            val candidateSourcePositionSeconds =
                sourcePositionSeconds + (frameStepSeconds * offset.toDouble())
            if (candidateSourcePositionSeconds < frameRequest.sourceStartSeconds - 0.0001) {
                continue
            }
            if (
                frameRequest.sourceEndSeconds != null &&
                candidateSourcePositionSeconds > frameRequest.sourceEndSeconds + 0.0001
            ) {
                continue
            }
            val candidateTimelinePositionSeconds =
                if (offset < 0) {
                    max(
                        frameRequest.clipStartSeconds,
                        frameRequest.timelinePositionSeconds + (frameStepSeconds * offset.toDouble()),
                    )
                } else {
                    frameRequest.timelinePositionSeconds + (frameStepSeconds * offset.toDouble())
                }
            val adjacentFrameRequest =
                frameRequest.copy(
                    timelinePositionSeconds = candidateTimelinePositionSeconds,
                    sourcePositionSeconds = candidateSourcePositionSeconds,
                    frameToken =
                        "video:${frameRequest.sourcePath}:${(candidateSourcePositionSeconds * 1000.0).roundToInt()}",
                )
            val adjacentCacheKey = cacheKey(adjacentFrameRequest, targetWidth, targetHeight)
            val isAlreadyCached =
                synchronized(lock) {
                    frameCache.containsKey(adjacentCacheKey) ||
                        pendingPrefetchKeys.contains(adjacentCacheKey)
                }
            if (isAlreadyCached) {
                continue
            }
            prefetchFrame(
                mediaIo = mediaIo,
                frameRequest = adjacentFrameRequest,
                targetWidth = targetWidth,
                targetHeight = targetHeight,
            )
        }
    }

    private fun prefetchContextFrames(
        mediaIo: AndroidMediaIo,
        frameRequest: ResolvedPreviewFrameRequest,
        targetWidth: Int,
        targetHeight: Int,
    ) {
        if (!shouldPrefetchContext(frameRequest)) {
            return
        }
        prefetchAdjacentFrames(
            mediaIo = mediaIo,
            frameRequest = frameRequest,
            targetWidth = targetWidth,
            targetHeight = targetHeight,
        )
    }

    private fun shouldPrefetchContext(frameRequest: ResolvedPreviewFrameRequest): Boolean {
        return when (frameRequest.transportKind) {
            "scrubBegin", "scrubUpdate", "seek" -> false
            else -> true
        }
    }

    private fun isPrefetchCancelled(
        projectId: Int,
        generation: Long,
    ): Boolean {
        return synchronized(lock) {
            (prefetchGenerationByProject[projectId] ?: 0L) != generation
        }
    }

    private fun shouldDropBeforeDecode(
        projectId: Int,
        sequence: Long,
    ): Boolean {
        return synchronized(lock) {
            latestSequenceByProject[projectId] != sequence
        }
    }

    private fun cacheKey(
        frameRequest: ResolvedPreviewFrameRequest,
        targetWidth: Int,
        targetHeight: Int,
    ): String {
        return "${frameRequest.frameToken}:$targetWidth:$targetHeight"
    }
}
