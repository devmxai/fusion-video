package com.example.fx_flutter_editor.previewengine

internal object PlaybackContinuityPlanner {
    fun usesContinuousStreamSession(frameRequest: ResolvedPreviewFrameRequest): Boolean {
        return frameRequest.sourceKind == "video" &&
            frameRequest.continuityKind == "sameSourceContiguous"
    }

    fun buildPlaybackSessionKey(frameRequest: ResolvedPreviewFrameRequest): String {
        return if (usesContinuousStreamSession(frameRequest)) {
            buildString {
                append(frameRequest.sourcePath)
                append("|video|continuous|")
                append(frameRequest.transportRevision)
            }
        } else {
            buildString {
                append(frameRequest.sourcePath)
                append('|')
                append(frameRequest.sourceStartSeconds)
                append('|')
                append(frameRequest.sourceEndSeconds ?: -1.0)
                append('|')
                append(frameRequest.transportRevision)
            }
        }
    }

    fun shouldEnforceSourceWindow(frameRequest: ResolvedPreviewFrameRequest): Boolean {
        return !usesContinuousStreamSession(frameRequest)
    }
}
