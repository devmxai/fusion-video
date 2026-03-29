#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreviewContinuityKind {
    SameSourceContiguous,
    SameSourceNonContiguous,
    DifferentSource,
    VideoToImage,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreviewTransportCommandKind {
    Play,
    Pause,
    Seek,
    ScrubBegin,
    ScrubUpdate,
    ScrubEnd,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PreviewResolvedSource {
    pub clip_id: String,
    pub asset_id: String,
    pub local_path: String,
    pub source_start_seconds: f64,
    pub source_end_seconds: Option<f64>,
    pub clip_start_seconds: f64,
    pub clip_end_seconds: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PreviewTransportCommand {
    pub kind: PreviewTransportCommandKind,
    pub project_time_seconds: f64,
    pub is_playing: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PreviewRuntimeEvent {
    pub project_time_seconds: f64,
    pub is_playing: bool,
    pub is_buffering: bool,
    pub frame_ready: bool,
    pub transport_revision: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ResolvedPreviewPayload {
    pub project_time_seconds: f64,
    pub is_playing: bool,
    pub transport_revision: u64,
    pub continuity: PreviewContinuityKind,
    pub source: Option<PreviewResolvedSource>,
    pub upcoming_source: Option<PreviewResolvedSource>,
    pub active_clip_ids: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct PreviewEngine {
    last_payload: Option<ResolvedPreviewPayload>,
    last_command: Option<PreviewTransportCommand>,
}

impl PreviewEngine {
    pub fn configure(&mut self, payload: ResolvedPreviewPayload) {
        self.last_payload = Some(payload);
    }

    pub fn dispatch(&mut self, command: PreviewTransportCommand) {
        self.last_command = Some(command);
    }

    pub fn last_payload(&self) -> Option<&ResolvedPreviewPayload> {
        self.last_payload.as_ref()
    }

    pub fn last_command(&self) -> Option<&PreviewTransportCommand> {
        self.last_command.as_ref()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preview_engine_keeps_last_payload_and_command() {
        let mut engine = PreviewEngine::default();
        let payload = ResolvedPreviewPayload {
            project_time_seconds: 3.5,
            is_playing: false,
            transport_revision: 7,
            continuity: PreviewContinuityKind::SameSourceContiguous,
            source: Some(PreviewResolvedSource {
                clip_id: "clip-b".to_owned(),
                asset_id: "asset-a".to_owned(),
                local_path: "/tmp/video.mp4".to_owned(),
                source_start_seconds: 2.0,
                source_end_seconds: Some(5.0),
                clip_start_seconds: 1.0,
                clip_end_seconds: Some(4.0),
            }),
            upcoming_source: None,
            active_clip_ids: vec!["clip-b".to_owned(), "clip-c".to_owned()],
        };
        engine.configure(payload.clone());
        engine.dispatch(PreviewTransportCommand {
            kind: PreviewTransportCommandKind::ScrubUpdate,
            project_time_seconds: 3.5,
            is_playing: false,
        });

        assert_eq!(engine.last_payload(), Some(&payload));
        assert_eq!(
            engine.last_command(),
            Some(&PreviewTransportCommand {
                kind: PreviewTransportCommandKind::ScrubUpdate,
                project_time_seconds: 3.5,
                is_playing: false,
            })
        );
    }
}
