use std::collections::HashMap;

use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum TrackKind {
    Video,
    Image,
    Audio,
    Text,
    LipSync,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum ClipType {
    Media,
    Placeholder,
}

#[derive(Debug, Clone, Serialize)]
pub struct AssetState {
    pub id: String,
    pub uri: String,
    pub kind: TrackKind,
    pub label: Option<String>,
    pub duration_seconds: Option<f64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ClipState {
    pub id: String,
    pub asset_id: Option<String>,
    pub source_offset_seconds: f64,
    pub duration_seconds: f64,
    pub clip_type: ClipType,
    pub split_group_id: Option<String>,
    pub audio_gain: f64,
    pub is_muted: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct VisualTransformState {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub opacity: f64,
    pub rotation_degrees: f64,
    pub z_index: i32,
}

#[derive(Debug, Clone, Serialize)]
pub struct CompositionNodeState {
    pub clip_id: String,
    pub asset_id: String,
    pub track_kind: TrackKind,
    pub asset_uri: String,
    pub display_label: Option<String>,
    pub clip_start_seconds: f64,
    pub clip_end_seconds: f64,
    pub clip_duration_seconds: f64,
    pub source_start_seconds: f64,
    pub source_end_seconds: f64,
    pub source_position_seconds: f64,
    pub transform: VisualTransformState,
}

#[derive(Debug, Clone, Serialize)]
pub struct AudioNodeState {
    pub clip_id: String,
    pub asset_id: String,
    pub track_kind: TrackKind,
    pub asset_uri: String,
    pub display_label: Option<String>,
    pub clip_start_seconds: f64,
    pub clip_end_seconds: f64,
    pub clip_duration_seconds: f64,
    pub source_start_seconds: f64,
    pub source_end_seconds: f64,
    pub source_position_seconds: f64,
    pub gain: f64,
    pub fade_duration_seconds: f64,
    pub gain_envelope: f64,
    pub is_muted: bool,
}

const AUDIO_FADE_DURATION_SECONDS: f64 = 0.005;

impl ClipState {
    pub fn media(id: &str, asset_id: &str, duration_seconds: f64) -> Self {
        Self {
            id: id.to_string(),
            asset_id: Some(asset_id.to_string()),
            source_offset_seconds: 0.0,
            duration_seconds,
            clip_type: ClipType::Media,
            split_group_id: None,
            audio_gain: 1.0,
            is_muted: false,
        }
    }

    pub fn placeholder(id: &str, duration_seconds: f64) -> Self {
        Self {
            id: id.to_string(),
            asset_id: None,
            source_offset_seconds: 0.0,
            duration_seconds,
            clip_type: ClipType::Placeholder,
            split_group_id: None,
            audio_gain: 1.0,
            is_muted: false,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct TrackState {
    pub kind: TrackKind,
    pub clips: Vec<ClipState>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProjectState {
    pub width: u32,
    pub height: u32,
    pub fps: f64,
    pub sample_rate: u32,
    pub base_duration_seconds: f64,
    pub duration_seconds: f64,
    pub assets: HashMap<String, AssetState>,
    pub tracks: Vec<TrackState>,
    edit_counter: u64,
}

#[derive(Debug, Clone, Copy)]
struct ClipLocation {
    track_index: usize,
    clip_index: usize,
    start_seconds: f64,
    end_seconds: f64,
}

impl ProjectState {
    pub fn new(width: u32, height: u32, fps: f64, sample_rate: u32, duration_seconds: f64) -> Self {
        Self {
            width,
            height,
            fps,
            sample_rate,
            base_duration_seconds: duration_seconds,
            duration_seconds,
            assets: HashMap::new(),
            tracks: build_default_tracks(),
            edit_counter: 0,
        }
    }

    pub fn import_asset(&mut self, asset: AssetState) {
        self.assets.insert(asset.id.clone(), asset);
    }

    pub fn split_clip(&mut self, clip_id: &str, current_seconds: f64) -> bool {
        let Some(location) = self.find_clip(clip_id) else {
            return false;
        };

        let clip = self.tracks[location.track_index].clips[location.clip_index].clone();
        if clip.clip_type != ClipType::Media {
            return false;
        }

        let edge_padding = 0.05;
        if location.end_seconds - location.start_seconds <= edge_padding * 2.0 {
            return false;
        }

        if current_seconds <= location.start_seconds + edge_padding
            || current_seconds >= location.end_seconds - edge_padding
        {
            return false;
        }

        let split_at = current_seconds;
        let left_duration = split_at - location.start_seconds;
        let right_duration = location.end_seconds - split_at;

        self.edit_counter += 1;
        let split_stamp = self.edit_counter.to_string();
        let split_group_id = format!("bridge_{split_stamp}");

        let left_clip = ClipState {
            id: format!("{}_a_{split_stamp}", clip.id),
            asset_id: clip.asset_id.clone(),
            source_offset_seconds: clip.source_offset_seconds,
            duration_seconds: left_duration,
            clip_type: clip.clip_type,
            split_group_id: Some(split_group_id.clone()),
            audio_gain: clip.audio_gain,
            is_muted: clip.is_muted,
        };
        let right_clip = ClipState {
            id: format!("{}_b_{split_stamp}", clip.id),
            asset_id: clip.asset_id.clone(),
            source_offset_seconds: clip.source_offset_seconds + left_duration,
            duration_seconds: right_duration,
            clip_type: clip.clip_type,
            split_group_id: Some(split_group_id),
            audio_gain: clip.audio_gain,
            is_muted: clip.is_muted,
        };

        let clips = &mut self.tracks[location.track_index].clips;
        clips.remove(location.clip_index);
        clips.insert(location.clip_index, right_clip);
        clips.insert(location.clip_index, left_clip);
        self.recompute_duration_seconds();
        true
    }

    pub fn trim_clip_left(&mut self, clip_id: &str, current_seconds: f64) -> bool {
        let Some(location) = self.find_clip(clip_id) else {
            return false;
        };

        let clip = &mut self.tracks[location.track_index].clips[location.clip_index];
        if clip.clip_type != ClipType::Media {
            return false;
        }

        let min_duration = 0.2;
        let new_start =
            current_seconds.clamp(location.start_seconds, location.end_seconds - min_duration);
        let delta = new_start - location.start_seconds;
        if delta <= 0.01 {
            return false;
        }

        clip.source_offset_seconds += delta;
        clip.duration_seconds -= delta;
        self.recompute_duration_seconds();
        true
    }

    pub fn trim_clip_right(&mut self, clip_id: &str, current_seconds: f64) -> bool {
        let Some(location) = self.find_clip(clip_id) else {
            return false;
        };

        let clip = &mut self.tracks[location.track_index].clips[location.clip_index];
        if clip.clip_type != ClipType::Media {
            return false;
        }

        let min_duration = 0.2;
        let new_end =
            current_seconds.clamp(location.start_seconds + min_duration, location.end_seconds);
        let new_duration = new_end - location.start_seconds;
        if (new_duration - clip.duration_seconds).abs() <= 0.01
            || new_duration >= clip.duration_seconds
        {
            return false;
        }

        clip.duration_seconds = new_duration;
        self.recompute_duration_seconds();
        true
    }

    pub fn delete_clip(&mut self, clip_id: &str) -> bool {
        let Some(location) = self.find_clip(clip_id) else {
            return false;
        };

        self.tracks[location.track_index]
            .clips
            .remove(location.clip_index);
        self.recompute_duration_seconds();
        true
    }

    pub fn duplicate_clip(&mut self, clip_id: &str) -> bool {
        let Some(location) = self.find_clip(clip_id) else {
            return false;
        };

        self.edit_counter += 1;
        let original = self.tracks[location.track_index].clips[location.clip_index].clone();
        let duplicate = ClipState {
            id: format!("{}_copy_{}", original.id, self.edit_counter),
            asset_id: original.asset_id.clone(),
            source_offset_seconds: original.source_offset_seconds,
            duration_seconds: original.duration_seconds,
            clip_type: original.clip_type,
            split_group_id: None,
            audio_gain: original.audio_gain,
            is_muted: original.is_muted,
        };

        self.tracks[location.track_index]
            .clips
            .insert(location.clip_index + 1, duplicate);
        self.recompute_duration_seconds();
        true
    }

    pub fn reorder_clip(&mut self, clip_id: &str, insertion_index: usize) -> bool {
        let Some(location) = self.find_clip(clip_id) else {
            return false;
        };

        let clips = &mut self.tracks[location.track_index].clips;
        if clips.len() <= 1 {
            return true;
        }

        let moved_clip = clips.remove(location.clip_index);
        let normalized_index = insertion_index.min(clips.len());
        clips.insert(normalized_index, moved_clip);
        self.recompute_duration_seconds();
        true
    }

    pub fn insert_clip(
        &mut self,
        kind: TrackKind,
        clip_id: &str,
        asset_id: &str,
        duration_seconds: f64,
        is_media: bool,
    ) -> bool {
        let resolved_duration = if duration_seconds > 0.0 {
            duration_seconds
        } else if is_media {
            self.assets
                .get(asset_id)
                .and_then(|asset| asset.duration_seconds)
                .unwrap_or(0.0)
        } else {
            0.0
        };

        if resolved_duration <= 0.0 {
            return false;
        }

        let clip = ClipState {
            id: clip_id.to_string(),
            asset_id: if is_media {
                Some(asset_id.to_string())
            } else {
                None
            },
            source_offset_seconds: 0.0,
            duration_seconds: resolved_duration,
            clip_type: if is_media {
                ClipType::Media
            } else {
                ClipType::Placeholder
            },
            split_group_id: None,
            audio_gain: 1.0,
            is_muted: false,
        };

        if let Some(track) = self.tracks.iter_mut().find(|track| track.kind == kind) {
            track.clips.push(clip);
            self.recompute_duration_seconds();
            return true;
        }

        self.tracks.push(TrackState {
            kind,
            clips: vec![clip],
        });
        self.tracks.sort_by_key(|track| track_sort_key(track.kind));
        self.recompute_duration_seconds();
        true
    }

    pub fn composition_nodes_at(&self, seconds: f64) -> Vec<CompositionNodeState> {
        let mut nodes = Vec::new();

        for track in &self.tracks {
            if !is_visual_track(track.kind) {
                continue;
            }

            let mut elapsed = 0.0;
            for clip in &track.clips {
                let start_seconds = elapsed;
                let end_seconds = start_seconds + clip.duration_seconds;
                elapsed = end_seconds;

                if clip.clip_type != ClipType::Media {
                    continue;
                }
                if seconds < start_seconds || seconds > end_seconds + 0.0001 {
                    continue;
                }

                let Some(asset_id) = clip.asset_id.as_ref() else {
                    continue;
                };
                let Some(asset) = self.assets.get(asset_id) else {
                    continue;
                };

                let source_start_seconds = clip.source_offset_seconds;
                let source_position_seconds = source_start_seconds
                    + (seconds - start_seconds).clamp(0.0, clip.duration_seconds);

                nodes.push(CompositionNodeState {
                    clip_id: clip.id.clone(),
                    asset_id: asset_id.clone(),
                    track_kind: track.kind,
                    asset_uri: asset.uri.clone(),
                    display_label: asset.label.clone(),
                    clip_start_seconds: start_seconds,
                    clip_end_seconds: end_seconds,
                    clip_duration_seconds: clip.duration_seconds,
                    source_start_seconds,
                    source_end_seconds: source_start_seconds + clip.duration_seconds,
                    source_position_seconds,
                    transform: default_transform_for_track(self.width, self.height, track.kind),
                });
            }
        }

        nodes.sort_by_key(|node| node.transform.z_index);
        nodes
    }

    pub fn set_clip_gain(&mut self, clip_id: &str, gain: f64) -> bool {
        let Some(location) = self.find_clip(clip_id) else {
            return false;
        };

        let clip = &mut self.tracks[location.track_index].clips[location.clip_index];
        if clip.clip_type != ClipType::Media {
            return false;
        }

        let clamped_gain = gain.clamp(0.0, 1.0);
        clip.audio_gain = clamped_gain;
        true
    }

    pub fn set_clip_muted(&mut self, clip_id: &str, is_muted: bool) -> bool {
        let Some(location) = self.find_clip(clip_id) else {
            return false;
        };

        let clip = &mut self.tracks[location.track_index].clips[location.clip_index];
        if clip.clip_type != ClipType::Media {
            return false;
        }

        clip.is_muted = is_muted;
        true
    }

    pub fn audio_nodes_at(&self, seconds: f64) -> Vec<AudioNodeState> {
        let mut nodes = Vec::new();

        for track in &self.tracks {
            if track.kind != TrackKind::Audio && track.kind != TrackKind::Video {
                continue;
            }

            let mut elapsed = 0.0;
            for clip in &track.clips {
                let start_seconds = elapsed;
                let end_seconds = start_seconds + clip.duration_seconds;
                elapsed = end_seconds;

                if clip.clip_type != ClipType::Media {
                    continue;
                }
                if seconds < start_seconds || seconds > end_seconds + 0.0001 {
                    continue;
                }

                let Some(asset_id) = clip.asset_id.as_ref() else {
                    continue;
                };
                let Some(asset) = self.assets.get(asset_id) else {
                    continue;
                };

                let source_start_seconds = clip.source_offset_seconds;
                let source_position_seconds = source_start_seconds
                    + (seconds - start_seconds).clamp(0.0, clip.duration_seconds);
                let fade_duration_seconds = AUDIO_FADE_DURATION_SECONDS
                    .min((end_seconds - start_seconds) / 2.0)
                    .max(0.0);
                let gain_envelope =
                    audio_envelope_at(seconds, start_seconds, end_seconds, fade_duration_seconds);

                nodes.push(AudioNodeState {
                    clip_id: clip.id.clone(),
                    asset_id: asset_id.clone(),
                    track_kind: track.kind,
                    asset_uri: asset.uri.clone(),
                    display_label: asset.label.clone(),
                    clip_start_seconds: start_seconds,
                    clip_end_seconds: end_seconds,
                    clip_duration_seconds: clip.duration_seconds,
                    source_start_seconds,
                    source_end_seconds: source_start_seconds + clip.duration_seconds,
                    source_position_seconds,
                    gain: clip.audio_gain,
                    fade_duration_seconds,
                    gain_envelope,
                    is_muted: clip.is_muted,
                });
            }
        }

        nodes
    }

    fn recompute_duration_seconds(&mut self) {
        let timeline_duration = self
            .tracks
            .iter()
            .map(|track| {
                track
                    .clips
                    .iter()
                    .map(|clip| clip.duration_seconds)
                    .sum::<f64>()
            })
            .fold(0.0, f64::max);
        self.duration_seconds = self.base_duration_seconds.max(timeline_duration);
    }

    fn find_clip(&self, clip_id: &str) -> Option<ClipLocation> {
        for (track_index, track) in self.tracks.iter().enumerate() {
            let mut elapsed = 0.0;
            for (clip_index, clip) in track.clips.iter().enumerate() {
                let start_seconds = elapsed;
                let end_seconds = start_seconds + clip.duration_seconds;
                if clip.id == clip_id {
                    return Some(ClipLocation {
                        track_index,
                        clip_index,
                        start_seconds,
                        end_seconds,
                    });
                }
                elapsed = end_seconds;
            }
        }
        None
    }
}

fn audio_envelope_at(
    seconds: f64,
    clip_start_seconds: f64,
    clip_end_seconds: f64,
    fade_duration_seconds: f64,
) -> f64 {
    if fade_duration_seconds <= 0.0 || clip_end_seconds <= clip_start_seconds {
        return 1.0;
    }

    let distance_from_start = (seconds - clip_start_seconds).max(0.0);
    let distance_to_end = (clip_end_seconds - seconds).max(0.0);
    let fade_in = (distance_from_start / fade_duration_seconds).clamp(0.0, 1.0);
    let fade_out = (distance_to_end / fade_duration_seconds).clamp(0.0, 1.0);
    fade_in.min(fade_out)
}

impl Default for ProjectState {
    fn default() -> Self {
        Self {
            width: 0,
            height: 0,
            fps: 30.0,
            sample_rate: 48_000,
            base_duration_seconds: 0.0,
            duration_seconds: 0.0,
            assets: HashMap::new(),
            tracks: build_default_tracks(),
            edit_counter: 0,
        }
    }
}

fn build_default_tracks() -> Vec<TrackState> {
    vec![]
}

fn is_visual_track(kind: TrackKind) -> bool {
    matches!(
        kind,
        TrackKind::Video | TrackKind::Image | TrackKind::Text | TrackKind::LipSync
    )
}

fn default_transform_for_track(width: u32, height: u32, kind: TrackKind) -> VisualTransformState {
    match kind {
        TrackKind::Video => VisualTransformState {
            x: 0.0,
            y: 0.0,
            width: width as f64,
            height: height as f64,
            opacity: 1.0,
            rotation_degrees: 0.0,
            z_index: 0,
        },
        TrackKind::Image => VisualTransformState {
            x: 0.0,
            y: 0.0,
            width: width as f64,
            height: height as f64,
            opacity: 1.0,
            rotation_degrees: 0.0,
            z_index: 10,
        },
        TrackKind::Text => VisualTransformState {
            x: width as f64 * 0.111,
            y: height as f64 * 0.77,
            width: width as f64 * 0.777,
            height: height as f64 * 0.114,
            opacity: 1.0,
            rotation_degrees: 0.0,
            z_index: 20,
        },
        TrackKind::LipSync => VisualTransformState {
            x: width as f64 * 0.231,
            y: height as f64 * 0.656,
            width: width as f64 * 0.537,
            height: height as f64 * 0.114,
            opacity: 1.0,
            rotation_degrees: 0.0,
            z_index: 30,
        },
        TrackKind::Audio => VisualTransformState {
            x: 0.0,
            y: 0.0,
            width: 0.0,
            height: 0.0,
            opacity: 1.0,
            rotation_degrees: 0.0,
            z_index: -1,
        },
    }
}

fn track_sort_key(kind: TrackKind) -> u8 {
    match kind {
        TrackKind::Video => 0,
        TrackKind::Image => 1,
        TrackKind::Audio => 2,
        TrackKind::Text => 3,
        TrackKind::LipSync => 4,
    }
}

#[cfg(test)]
mod tests {
    use super::{AssetState, ClipType, ProjectState, TrackKind};

    fn project() -> ProjectState {
        ProjectState::new(1080, 1920, 30.0, 48_000, 5.0)
    }

    #[test]
    fn inserts_tracks_in_expected_order() {
        let mut project = project();

        assert!(project.insert_clip(TrackKind::Audio, "audio-1", "audio-1", 1.2, true));
        assert!(project.insert_clip(TrackKind::Video, "video-1", "video-1", 3.0, true));
        assert!(project.insert_clip(TrackKind::Text, "text-1", "text-1", 1.0, false));

        assert_eq!(project.tracks.len(), 3);
        assert_eq!(project.tracks[0].kind, TrackKind::Video);
        assert_eq!(project.tracks[1].kind, TrackKind::Audio);
        assert_eq!(project.tracks[2].kind, TrackKind::Text);
    }

    #[test]
    fn project_duration_tracks_longest_timeline_and_resets_to_base() {
        let mut project = project();

        assert!(project.insert_clip(TrackKind::Video, "video-1", "video-1", 19.0, true));
        assert_eq!(project.duration_seconds, 19.0);

        assert!(project.delete_clip("video-1"));
        assert_eq!(project.duration_seconds, 5.0);
    }

    #[test]
    fn composition_snapshot_resolves_clip_source_offsets() {
        let mut project = project();
        project.import_asset(AssetState {
            id: "video-1".into(),
            uri: "/tmp/video-1.mp4".into(),
            kind: TrackKind::Video,
            label: Some("video-1.mp4".into()),
            duration_seconds: Some(4.0),
            width: Some(1080),
            height: Some(1920),
        });

        assert!(project.insert_clip(TrackKind::Video, "video-1", "video-1", 4.0, true));
        assert!(project.split_clip("video-1", 1.5));

        let nodes = project.composition_nodes_at(2.0);
        assert_eq!(nodes.len(), 1);
        let node = &nodes[0];
        assert_eq!(node.asset_id, "video-1");
        assert_eq!(node.clip_id, "video-1_b_1");
        assert!((node.source_start_seconds - 1.5).abs() < 0.001);
        assert!((node.source_position_seconds - 2.0).abs() < 0.001);
        assert!((node.source_end_seconds - 4.0).abs() < 0.001);
    }

    #[test]
    fn audio_snapshot_resolves_clip_source_offsets() {
        let mut project = project();
        project.import_asset(AssetState {
            id: "audio-1".into(),
            uri: "/tmp/audio-1.m4a".into(),
            kind: TrackKind::Audio,
            label: Some("audio-1.m4a".into()),
            duration_seconds: Some(6.0),
            width: None,
            height: None,
        });

        assert!(project.insert_clip(TrackKind::Audio, "audio-1", "audio-1", 6.0, true));
        assert!(project.split_clip("audio-1", 2.0));

        let nodes = project.audio_nodes_at(3.5);
        assert_eq!(nodes.len(), 1);
        let node = &nodes[0];
        assert_eq!(node.asset_id, "audio-1");
        assert_eq!(node.track_kind, TrackKind::Audio);
        assert_eq!(node.display_label.as_deref(), Some("audio-1.m4a"));
        assert_eq!(node.clip_id, "audio-1_b_1");
        assert!((node.source_start_seconds - 2.0).abs() < 0.001);
        assert!((node.source_position_seconds - 3.5).abs() < 0.001);
        assert!((node.source_end_seconds - 6.0).abs() < 0.001);
    }

    #[test]
    fn video_clip_exposes_audio_snapshot_for_mixer_foundation() {
        let mut project = project();
        project.import_asset(AssetState {
            id: "video-audio-1".into(),
            uri: "/tmp/video-audio-1.mp4".into(),
            kind: TrackKind::Video,
            label: Some("video-audio-1.mp4".into()),
            duration_seconds: Some(5.0),
            width: Some(1080),
            height: Some(1920),
        });

        assert!(project.insert_clip(
            TrackKind::Video,
            "video-audio-1",
            "video-audio-1",
            5.0,
            true
        ));

        let nodes = project.audio_nodes_at(1.25);
        assert_eq!(nodes.len(), 1);
        let node = &nodes[0];
        assert_eq!(node.asset_id, "video-audio-1");
        assert_eq!(node.track_kind, TrackKind::Video);
        assert_eq!(node.display_label.as_deref(), Some("video-audio-1.mp4"));
        assert!((node.source_position_seconds - 1.25).abs() < 0.001);
    }

    #[test]
    fn clip_audio_controls_propagate_to_audio_snapshot() {
        let mut project = project();
        project.import_asset(AssetState {
            id: "video-1".into(),
            uri: "/tmp/video-1.mp4".into(),
            kind: TrackKind::Video,
            label: Some("video-1.mp4".into()),
            duration_seconds: Some(4.0),
            width: Some(1080),
            height: Some(1920),
        });

        assert!(project.insert_clip(TrackKind::Video, "video-1", "video-1", 4.0, true));
        assert!(project.set_clip_gain("video-1", 0.35));
        assert!(project.set_clip_muted("video-1", true));

        let nodes = project.audio_nodes_at(1.0);
        assert_eq!(nodes.len(), 1);
        let node = &nodes[0];
        assert!((node.gain - 0.35).abs() < 0.001);
        assert!(node.is_muted);
    }

    #[test]
    fn splits_video_clip_into_two_segments() {
        let mut project = project();
        assert!(project.insert_clip(TrackKind::Video, "video-1", "video-1", 3.15, true));

        assert!(project.split_clip("video-1", 1.4));

        let video_track = project
            .tracks
            .iter()
            .find(|track| track.kind == TrackKind::Video)
            .unwrap();

        assert_eq!(video_track.clips.len(), 2);
        assert_eq!(video_track.clips[0].clip_type, ClipType::Media);
        assert_eq!(video_track.clips[1].clip_type, ClipType::Media);
        assert!(video_track.clips[0].split_group_id.is_some());
        assert_eq!(
            video_track.clips[0].split_group_id,
            video_track.clips[1].split_group_id
        );
    }

    #[test]
    fn split_rejects_positions_outside_selected_clip_body() {
        let mut project = project();
        assert!(project.insert_clip(TrackKind::Video, "video-1", "video-1", 3.0, true));
        assert!(project.insert_clip(TrackKind::Video, "video-2", "video-2", 2.0, true));

        assert!(!project.split_clip("video-2", 1.0));

        let video_track = project
            .tracks
            .iter()
            .find(|track| track.kind == TrackKind::Video)
            .unwrap();
        let ids = video_track
            .clips
            .iter()
            .map(|clip| clip.id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(ids, vec!["video-1", "video-2"]);
    }

    #[test]
    fn trims_delete_and_duplicate_work() {
        let mut project = project();
        assert!(project.insert_clip(TrackKind::Video, "video-1", "video-1", 3.15, true));
        assert!(project.insert_clip(TrackKind::Video, "video-2", "video-2", 0.72, true));

        assert!(project.trim_clip_left("video-1", 0.9));
        assert!(project.trim_clip_right("video-1", 1.5));
        assert!(project.duplicate_clip("video-1"));
        assert!(project.delete_clip("video-2"));

        let video_track = project
            .tracks
            .iter()
            .find(|track| track.kind == TrackKind::Video)
            .unwrap();

        assert_eq!(video_track.clips.len(), 2);
        assert!(video_track.clips[1].id.contains("_copy_"));
        assert!((video_track.clips[0].duration_seconds - 1.5).abs() < 0.001);
    }

    #[test]
    fn reorders_clips_using_insertion_slots() {
        let mut project = project();
        assert!(project.insert_clip(TrackKind::Video, "video-1", "video-1", 1.0, true));
        assert!(project.insert_clip(TrackKind::Video, "video-2", "video-2", 1.0, true));
        assert!(project.insert_clip(TrackKind::Video, "video-3", "video-3", 1.0, true));

        assert!(project.reorder_clip("video-1", 2));

        let video_track = project
            .tracks
            .iter()
            .find(|track| track.kind == TrackKind::Video)
            .unwrap();
        let ids = video_track
            .clips
            .iter()
            .map(|clip| clip.id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(ids, vec!["video-2", "video-3", "video-1"]);
    }
}
