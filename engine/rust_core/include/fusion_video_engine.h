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
uint8_t fusion_video_engine_insert_clip(
    int64_t handle,
    uint8_t track_kind,
    const char* clip_id,
    double duration_seconds,
    uint8_t is_media
);
uint8_t fusion_video_engine_get_playback_state(int64_t handle);
double fusion_video_engine_get_position_seconds(int64_t handle);
int64_t fusion_video_engine_get_position_frame(int64_t handle);
uint8_t fusion_video_engine_is_buffering(int64_t handle);
char* fusion_video_engine_get_timeline_json(int64_t handle);
void fusion_video_engine_free_string(char* value);

#ifdef __cplusplus
}
#endif

#endif
