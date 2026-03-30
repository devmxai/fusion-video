package com.example.fx_flutter_editor.previewengine

import android.graphics.Bitmap
import java.io.ByteArrayOutputStream
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.roundToInt

class AndroidTimelineThumbnailRepository(
    private val mediaIo: AndroidMediaIo,
    private val byteLoader: ((String, Double, Int, Int) -> ByteArray?)? = null,
) {
    private val frameBytesCache = ConcurrentHashMap<String, ByteArray>()

    fun loadVideoThumbnails(
        path: String,
        timestampsSeconds: List<Double>,
        targetWidth: Int,
        targetHeight: Int,
    ): List<ByteArray> {
        if (timestampsSeconds.isEmpty()) {
            return emptyList()
        }
        val normalizedWidth = targetWidth.coerceAtLeast(24)
        val normalizedHeight = targetHeight.coerceAtLeast(24)
        val resolvedThumbnails = ArrayList<ByteArray>(timestampsSeconds.size)
        val localResults = linkedMapOf<String, ByteArray>()
        val uncachedTimestamps = ArrayList<Double>()
        val uncachedKeys = ArrayList<String>()
        for (timestampSeconds in timestampsSeconds) {
            val normalizedTimestamp = normalizeTimestamp(timestampSeconds)
            val cacheKey =
                buildCacheKey(
                    path = path,
                    timestampSeconds = normalizedTimestamp,
                    targetWidth = normalizedWidth,
                    targetHeight = normalizedHeight,
                )
            val cachedBytes = localResults[cacheKey] ?: frameBytesCache[cacheKey]
            if (cachedBytes != null) {
                localResults[cacheKey] = cachedBytes
                continue
            }
            if (!uncachedKeys.contains(cacheKey)) {
                uncachedKeys.add(cacheKey)
                uncachedTimestamps.add(normalizedTimestamp)
            }
        }
        if (uncachedTimestamps.isNotEmpty()) {
            val batchedBytes =
                if (byteLoader != null) {
                    uncachedTimestamps.map { timestamp ->
                        byteLoader.invoke(path, timestamp, normalizedWidth, normalizedHeight)
                    }
                } else {
                    mediaIo.loadTimelineBitmaps(
                        path = path,
                        timestampsSeconds = uncachedTimestamps,
                        targetWidth = normalizedWidth,
                        targetHeight = normalizedHeight,
                    ).map { bitmap ->
                        bitmap?.toPngByteArray()
                    }
                }
            for (index in uncachedKeys.indices) {
                val encodedBytes = batchedBytes.getOrNull(index) ?: continue
                val cacheKey = uncachedKeys[index]
                frameBytesCache.putIfAbsent(cacheKey, encodedBytes)
                localResults[cacheKey] = encodedBytes
            }
        }
        for (timestampSeconds in timestampsSeconds) {
            val normalizedTimestamp = normalizeTimestamp(timestampSeconds)
            val cacheKey =
                buildCacheKey(
                    path = path,
                    timestampSeconds = normalizedTimestamp,
                    targetWidth = normalizedWidth,
                    targetHeight = normalizedHeight,
                )
            val resolvedBytes = localResults[cacheKey] ?: frameBytesCache[cacheKey] ?: continue
            resolvedThumbnails.add(resolvedBytes)
        }
        return resolvedThumbnails
    }

    private fun normalizeTimestamp(value: Double): Double {
        return (value * 20.0).roundToInt() / 20.0
    }

    private fun buildCacheKey(
        path: String,
        timestampSeconds: Double,
        targetWidth: Int,
        targetHeight: Int,
    ): String {
        return "$path|${String.format(Locale.US, "%.2f", timestampSeconds)}|$targetWidth|$targetHeight"
    }

    private fun Bitmap.toPngByteArray(): ByteArray {
        val output = ByteArrayOutputStream()
        compress(Bitmap.CompressFormat.PNG, 100, output)
        return output.toByteArray()
    }
}
