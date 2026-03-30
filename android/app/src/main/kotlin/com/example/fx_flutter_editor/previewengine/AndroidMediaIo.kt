package com.example.fx_flutter_editor.previewengine

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

data class VideoStreamDescriptor(
    val width: Int?,
    val height: Int?,
    val durationSeconds: Double?,
    val frameRate: Int?,
    val rotationDegrees: Int,
) {
    val displayWidth: Int?
        get() = if (rotationDegrees % 180 != 0) height else width

    val displayHeight: Int?
        get() = if (rotationDegrees % 180 != 0) width else height

    val frameStepSeconds: Double
        get() = 1.0 / ((frameRate ?: 30).coerceAtLeast(1))
}

class AndroidMediaIo {
    private val streamDescriptorCache = ConcurrentHashMap<String, VideoStreamDescriptor>()

    fun loadPreviewBitmap(
        frameRequest: ResolvedPreviewFrameRequest,
        targetWidth: Int,
        targetHeight: Int,
    ): Bitmap? =
        when (frameRequest.sourceKind) {
            "image" -> loadImageBitmap(frameRequest.sourcePath, targetWidth, targetHeight)
            "video" -> loadVideoFrameBitmap(
                path = frameRequest.sourcePath,
                positionSeconds = frameRequest.sourcePositionSeconds ?: frameRequest.sourceStartSeconds,
                targetWidth = targetWidth,
                targetHeight = targetHeight,
            )

            else -> null
        }

    fun loadTimelineBitmap(
        path: String,
        positionSeconds: Double,
        targetWidth: Int,
        targetHeight: Int,
    ): Bitmap? =
        loadVideoFrameBitmap(
            path = path,
            positionSeconds = positionSeconds,
            targetWidth = targetWidth,
            targetHeight = targetHeight,
        )

    fun loadTimelineBitmaps(
        path: String,
        timestampsSeconds: List<Double>,
        targetWidth: Int,
        targetHeight: Int,
    ): List<Bitmap?> {
        if (timestampsSeconds.isEmpty()) {
            return emptyList()
        }
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val rotationDegrees = inspectVideoStream(path)?.rotationDegrees ?: 0
            val requestWidth =
                if (rotationDegrees % 180 != 0) targetHeight else targetWidth
            val requestHeight =
                if (rotationDegrees % 180 != 0) targetWidth else targetHeight
            timestampsSeconds.map { positionSeconds ->
                val timeUs = max(0L, (positionSeconds * 1_000_000.0).roundToLong())
                val decoded =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        retriever.getScaledFrameAtTime(
                            timeUs,
                            MediaMetadataRetriever.OPTION_CLOSEST,
                            requestWidth.coerceAtLeast(1),
                            requestHeight.coerceAtLeast(1),
                        )
                    } else {
                        retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                    }
                decoded
                    ?.let { rotateBitmap(it, rotationDegrees) }
                    ?.let { scaleBitmapToFit(it, targetWidth, targetHeight) }
                    ?.let(::normalizeBitmap)
            }
        } finally {
            retriever.release()
        }
    }

    fun inspectVideoStream(path: String): VideoStreamDescriptor? {
        streamDescriptorCache[path]?.let { return it }
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(path)
            val trackIndex =
                (0 until extractor.trackCount).firstOrNull { index ->
                    val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                    mime?.startsWith("video/") == true
                } ?: return null
            val format = extractor.getTrackFormat(trackIndex)
            val retriever = MediaMetadataRetriever()
            val rotationDegrees =
                try {
                    retriever.setDataSource(path)
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                        ?.toIntOrNull() ?: 0
                } finally {
                    retriever.release()
                }
            VideoStreamDescriptor(
                width =
                    if (format.containsKey(MediaFormat.KEY_WIDTH)) {
                        format.getInteger(MediaFormat.KEY_WIDTH)
                    } else {
                        null
                    },
                height =
                    if (format.containsKey(MediaFormat.KEY_HEIGHT)) {
                        format.getInteger(MediaFormat.KEY_HEIGHT)
                    } else {
                        null
                    },
                durationSeconds =
                    if (format.containsKey(MediaFormat.KEY_DURATION)) {
                        format.getLong(MediaFormat.KEY_DURATION) / 1_000_000.0
                    } else {
                        null
                    },
                frameRate =
                    if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                        format.getInteger(MediaFormat.KEY_FRAME_RATE)
                    } else {
                        null
                    },
                rotationDegrees = rotationDegrees,
            ).also { descriptor ->
                streamDescriptorCache[path] = descriptor
            }
        } catch (_: Throwable) {
            null
        } finally {
            extractor.release()
        }
    }

    private fun loadImageBitmap(path: String, targetWidth: Int, targetHeight: Int): Bitmap? {
        val decoded = BitmapFactory.decodeFile(path) ?: return null
        return normalizeBitmap(scaleBitmapToFit(decoded, targetWidth, targetHeight))
    }

    private fun loadVideoFrameBitmap(
        path: String,
        positionSeconds: Double,
        targetWidth: Int,
        targetHeight: Int,
    ): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val rotationDegrees = inspectVideoStream(path)?.rotationDegrees ?: 0
            val requestWidth =
                if (rotationDegrees % 180 != 0) targetHeight else targetWidth
            val requestHeight =
                if (rotationDegrees % 180 != 0) targetWidth else targetHeight
            val timeUs = max(0L, (positionSeconds * 1_000_000.0).roundToLong())
            val decoded =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    retriever.getScaledFrameAtTime(
                        timeUs,
                        MediaMetadataRetriever.OPTION_CLOSEST,
                        requestWidth.coerceAtLeast(1),
                        requestHeight.coerceAtLeast(1),
                    )
                } else {
                    retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                }
            decoded
                ?.let { rotateBitmap(it, rotationDegrees) }
                ?.let { scaleBitmapToFit(it, targetWidth, targetHeight) }
                ?.let(::normalizeBitmap)
        } finally {
            retriever.release()
        }
    }

    private fun scaleBitmapToFit(bitmap: Bitmap, targetWidth: Int, targetHeight: Int): Bitmap {
        if (targetWidth <= 0 || targetHeight <= 0) {
            return bitmap
        }
        val scale =
            min(
                targetWidth.toFloat() / bitmap.width.toFloat().coerceAtLeast(1f),
                targetHeight.toFloat() / bitmap.height.toFloat().coerceAtLeast(1f),
            )
        val fittedWidth =
            (bitmap.width.toFloat() * scale).roundToLong().toInt().coerceAtLeast(1)
        val fittedHeight =
            (bitmap.height.toFloat() * scale).roundToLong().toInt().coerceAtLeast(1)
        if (bitmap.width == fittedWidth && bitmap.height == fittedHeight) {
            return bitmap
        }
        val scaled =
            Bitmap.createScaledBitmap(
                bitmap,
                fittedWidth,
                fittedHeight,
                true,
            )
        if (scaled !== bitmap) {
            bitmap.recycle()
        }
        return scaled
    }

    private fun rotateBitmap(bitmap: Bitmap, rotationDegrees: Int): Bitmap {
        val normalized = ((rotationDegrees % 360) + 360) % 360
        if (normalized == 0) {
            return bitmap
        }
        val matrix =
            Matrix().apply {
                postRotate(normalized.toFloat())
            }
        val rotated =
            Bitmap.createBitmap(
                bitmap,
                0,
                0,
                bitmap.width,
                bitmap.height,
                matrix,
                true,
            )
        if (rotated !== bitmap) {
            bitmap.recycle()
        }
        return rotated
    }

    private fun normalizeBitmap(bitmap: Bitmap): Bitmap {
        if (bitmap.config == Bitmap.Config.ARGB_8888) {
            return bitmap
        }
        val normalized = bitmap.copy(Bitmap.Config.ARGB_8888, false)
        if (normalized !== bitmap) {
            bitmap.recycle()
        }
        return normalized
    }
}
