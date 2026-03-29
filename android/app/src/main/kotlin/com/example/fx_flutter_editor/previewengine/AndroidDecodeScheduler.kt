package com.example.fx_flutter_editor.previewengine

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.util.LinkedHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
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
    private val executor: ExecutorService = Executors.newSingleThreadExecutor(),
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
) {
    private val lock = Any()
    private val latestSequenceByProject = mutableMapOf<Int, Long>()
    private val frameCache =
        object : LinkedHashMap<String, Bitmap>(12, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Bitmap>?): Boolean {
                return size > 12
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
            if (frameRequest.isPlaying) {
                prefetchAdjacentFrames(mediaIo, frameRequest, targetWidth, targetHeight)
            }
            return
        }

        executor.execute {
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
            if (frameRequest.isPlaying) {
                prefetchAdjacentFrames(mediaIo, frameRequest, targetWidth, targetHeight)
            }
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
        }
    }

    fun reset() {
        synchronized(lock) {
            latestSequenceByProject.clear()
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
        for (offset in 1..2) {
            val nextSourcePositionSeconds = sourcePositionSeconds + (frameStepSeconds * offset)
            if (
                frameRequest.sourceEndSeconds != null &&
                nextSourcePositionSeconds > frameRequest.sourceEndSeconds + 0.0001
            ) {
                break
            }
            val nextFrameRequest =
                frameRequest.copy(
                    timelinePositionSeconds =
                        frameRequest.timelinePositionSeconds + (frameStepSeconds * offset),
                    sourcePositionSeconds = nextSourcePositionSeconds,
                    frameToken =
                        "video:${frameRequest.sourcePath}:${(nextSourcePositionSeconds * 1000.0).roundToInt()}",
                )
            val nextCacheKey = cacheKey(nextFrameRequest, targetWidth, targetHeight)
            val isAlreadyCached =
                synchronized(lock) {
                    frameCache.containsKey(nextCacheKey)
                }
            if (isAlreadyCached) {
                continue
            }
            val prefetchedBitmap =
                mediaIo.loadPreviewBitmap(
                    frameRequest = nextFrameRequest,
                    targetWidth = targetWidth,
                    targetHeight = targetHeight,
                )
            if (prefetchedBitmap != null) {
                synchronized(lock) {
                    frameCache[nextCacheKey] = prefetchedBitmap
                }
            }
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
