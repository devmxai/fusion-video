package com.example.fx_flutter_editor.previewengine

data class ResolvedPreviewConfiguration(
    val projectId: Int,
    val positionSeconds: Double,
    val isPlaying: Boolean,
    val transportRevision: Int,
    val sourceId: String?,
    val sourcePath: String?,
    val sourceKind: String?,
    val upcomingSourceId: String?,
    val upcomingSourcePath: String?,
    val upcomingSourceKind: String?,
    val clipStartSeconds: Double?,
    val clipEndSeconds: Double?,
    val sourceStartSeconds: Double?,
    val sourceEndSeconds: Double?,
    val upcomingSourceStartSeconds: Double?,
    val upcomingSourceEndSeconds: Double?,
    val projectWidth: Int?,
    val projectHeight: Int?,
    val baseClipId: String?,
    val baseClipIds: List<String>,
    val selectedClipId: String?,
    val continuityKind: String?,
    val sceneNodes: List<Map<String, Any?>>,
    val audioNodes: List<Map<String, Any?>>,
)

data class PreviewTransportCommandEnvelope(
    val projectId: Int,
    val transportRevision: Int,
    val kind: String,
    val positionSeconds: Double?,
    val isPlaying: Boolean?,
)

class FusionAndroidPreviewEngine(
    val mediaIo: AndroidMediaIo = AndroidMediaIo(),
    val decodeScheduler: AndroidDecodeScheduler = AndroidDecodeScheduler(),
    val renderer: AndroidPreviewRenderer = AndroidPreviewRenderer(),
    val audioEngine: AndroidAudioEngine = AndroidAudioEngine(),
    val exportPipeline: AndroidExportPipeline = AndroidExportPipeline(),
) {
    val isScaffoldReady: Boolean = true
    var lastConfiguration: ResolvedPreviewConfiguration? = null
        private set
    var lastCommand: PreviewTransportCommandEnvelope? = null
        private set

    fun configure(configuration: ResolvedPreviewConfiguration) {
        lastConfiguration = configuration
    }

    fun dispatch(command: PreviewTransportCommandEnvelope) {
        lastCommand = command
    }
}
