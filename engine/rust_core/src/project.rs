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
}

impl ClipState {
    pub fn media(id: &str, asset_id: &str, duration_seconds: f64) -> Self {
        Self {
            id: id.to_string(),
            asset_id: Some(asset_id.to_string()),
            source_offset_seconds: 0.0,
            duration_seconds,
            clip_type: ClipType::Media,
            split_group_id: None,
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

        let split_at = current_seconds.clamp(
            location.start_seconds + edge_padding,
            location.end_seconds - edge_padding,
        );
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
        };
        let right_clip = ClipState {
            id: format!("{}_b_{split_stamp}", clip.id),
            asset_id: clip.asset_id.clone(),
            source_offset_seconds: clip.source_offset_seconds + left_duration,
            duration_seconds: right_duration,
            clip_type: clip.clip_type,
            split_group_id: Some(split_group_id),
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
        };

        self.tracks[location.track_index]
            .clips
            .insert(location.clip_index + 1, duplicate);
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
    use super::{ClipType, ProjectState, TrackKind};

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
}
