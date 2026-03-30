#ifndef FUSION_VIDEO_ENGINE_H
#define FUSION_VIDEO_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t fusion_video_engine_version(void);

int64_t fusion_video_engine_create_project(
    uint32_t width,
    uint32_t height,
    double fps,
    uint32_t sample_rate,
    double duration_seconds
);

uint8_t fusion_video_engine_dispose_project(int64_t handle);
uint8_t fusion_video_engine_play(int64_t handle);
uint8_t fusion_video_engine_pause(int64_t handle);
uint8_t fusion_video_engine_seek(
    int64_t handle,
    double seconds,
    int64_t frame
);
uint8_t fusion_video_engine_split_selected_clip(
    int64_t handle,
    const char* clip_id,
    double seconds,
    int64_t frame
);
uint8_t fusion_video_engine_trim_clip_left(
    int64_t handle,
    const char* clip_id,
    double seconds,
    int64_t frame
);
uint8_t fusion_video_engine_trim_clip_right(
    int64_t handle,
    const char* clip_id,
    double seconds,
    int64_t frame
);
uint8_t fusion_video_engine_delete_clip(
    int64_t handle,
    const char* clip_id
);
uint8_t fusion_video_engine_duplicate_clip(
    int64_t handle,
    const char* clip_id
);
uint8_t fusion_video_engine_reorder_clip(
    int64_t handle,
    const char* clip_id,
    int64_t insertion_index
);
uint8_t fusion_video_engine_set_clip_gain(
    int64_t handle,
    const char* clip_id,
    double gain
);
uint8_t fusion_video_engine_set_clip_muted(
    int64_t handle,
    const char* clip_id,
    uint8_t is_muted
);
uint8_t fusion_video_engine_set_clip_transform(
    int64_t handle,
    const char* clip_id,
    double x,
    double y,
    double width,
    double height,
    double opacity,
    double rotation_degrees,
    int32_t z_index
);
uint8_t fusion_video_engine_import_asset(
    int64_t handle,
    const char* asset_id,
    const char* uri,
    const char* label,
    uint8_t track_kind,
    double duration_seconds,
    int32_t width,
    int32_t height
);
uint8_t fusion_video_engine_insert_clip(
    int64_t handle,
    uint8_t track_kind,
    const char* clip_id,
    const char* asset_id,
    double duration_seconds,
    uint8_t is_media
);
uint8_t fusion_video_engine_get_playback_state(int64_t handle);
double fusion_video_engine_get_position_seconds(int64_t handle);
int64_t fusion_video_engine_get_position_frame(int64_t handle);
uint8_t fusion_video_engine_is_buffering(int64_t handle);
char* fusion_video_engine_get_timeline_json(int64_t handle);
char* fusion_video_engine_get_composition_json(
    int64_t handle,
    double seconds,
    int64_t frame
);
char* fusion_video_engine_get_audio_json(
    int64_t handle,
    double seconds,
    int64_t frame
);
void fusion_video_engine_free_string(char* value);

#ifdef __cplusplus
}
#endif

#endif
