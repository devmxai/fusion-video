package com.example.fx_flutter_editor

import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "fusion_video/preview_surface",
                FusionPreviewViewFactory(),
            )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fusion_video/preview_session",
        ).setMethodCallHandler { call, result ->
            if (call.method != "updatePreview") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val args = call.arguments as? Map<*, *>
            val projectId = (args?.get("projectId") as? Number)?.toInt()
            val positionSeconds = (args?.get("positionSeconds") as? Number)?.toDouble()
            val isPlaying = args?.get("isPlaying") as? Boolean

            if (projectId == null || positionSeconds == null || isPlaying == null) {
                result.error("invalid_args", "Missing preview session arguments", null)
                return@setMethodCallHandler
            }

            FusionPreviewRegistry.update(projectId, positionSeconds, isPlaying)
            result.success(null)
        }
    }
}

private object FusionPreviewRegistry {
    private val views = mutableMapOf<Int, MutableList<FusionPreviewNativeView>>()

    fun attach(projectId: Int, view: FusionPreviewNativeView) {
        val bucket = views.getOrPut(projectId) { mutableListOf() }
        bucket.add(view)
    }

    fun detach(projectId: Int, view: FusionPreviewNativeView) {
        views[projectId]?.remove(view)
    }

    fun update(projectId: Int, positionSeconds: Double, isPlaying: Boolean) {
        views[projectId]?.forEach { it.update(positionSeconds, isPlaying) }
    }
}

private class FusionPreviewViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val projectId = ((args as? Map<*, *>)?.get("projectId") as? Number)?.toInt() ?: viewId
        return FusionPreviewPlatformView(context, projectId)
    }
}

private class FusionPreviewPlatformView(
    context: Context,
    projectId: Int,
) : PlatformView {
    private val nativeView = FusionPreviewNativeView(context, projectId)

    override fun getView(): View = nativeView

    override fun dispose() {
        nativeView.dispose()
    }
}

private class FusionPreviewNativeView(
    context: Context,
    private val projectId: Int,
) : FrameLayout(context) {
    private val titleLabel = TextView(context)
    private val statusLabel = TextView(context)
    private val progressTrack = FrameLayout(context)
    private val progressFill = View(context)

    init {
        setBackgroundColor(Color.parseColor("#111113"))

        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), dp(18), dp(18), dp(18))
            layoutParams =
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        }

        titleLabel.apply {
            text = "Fusion Native Preview"
            setTextColor(Color.parseColor("#F1F1F1"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        }

        statusLabel.apply {
            setTextColor(Color.parseColor("#A7A7AB"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        }

        progressTrack.apply {
            setBackgroundColor(Color.parseColor("#1E1E23"))
            layoutParams = LinearLayout.LayoutParams(
                LayoutParams.MATCH_PARENT,
                dp(6),
            ).apply {
                topMargin = dp(16)
            }
            clipToOutline = true
        }

        progressFill.setBackgroundColor(Color.parseColor("#5BDE57"))
        progressTrack.addView(
            progressFill,
            LayoutParams(0, LayoutParams.MATCH_PARENT),
        )

        content.addView(titleLabel)
        content.addView(statusLabel)
        content.addView(progressTrack)
        addView(content)

        FusionPreviewRegistry.attach(projectId, this)
        update(0.0, false)
    }

    fun update(positionSeconds: Double, isPlaying: Boolean) {
        statusLabel.text = "${if (isPlaying) "Playing" else "Paused"}  ${"%.2f".format(positionSeconds)}s"

        post {
            val width = progressTrack.width
            if (width <= 0) return@post
            val progress = (positionSeconds / 5.0).coerceIn(0.0, 1.0)
            progressFill.layoutParams = LayoutParams(
                (width * progress).toInt(),
                LayoutParams.MATCH_PARENT,
            )
            progressFill.requestLayout()
        }
    }

    fun dispose() {
        FusionPreviewRegistry.detach(projectId, this)
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()
    }
}
