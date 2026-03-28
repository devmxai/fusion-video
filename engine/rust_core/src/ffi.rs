use std::{
    collections::HashMap,
    ffi::{CStr, CString},
    sync::{
        atomic::{AtomicI64, Ordering},
        Mutex, OnceLock,
    },
};

use crate::{
    project::{ProjectState, TrackKind},
    timeline::{PlaybackState, TransportState},
};

static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);
static RUNTIMES: OnceLock<Mutex<HashMap<i64, EngineRuntime>>> = OnceLock::new();

#[derive(Debug)]
struct EngineRuntime {
    project: ProjectState,
    transport: TransportState,
}

impl EngineRuntime {
    fn new(project: ProjectState) -> Self {
        Self {
            project,
            transport: TransportState::default(),
        }
    }
}

fn runtimes() -> &'static Mutex<HashMap<i64, EngineRuntime>> {
    RUNTIMES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn with_runtime<T>(handle: i64, f: impl FnOnce(&mut EngineRuntime) -> T) -> Option<T> {
    let mut guard = runtimes().lock().ok()?;
    let runtime = guard.get_mut(&handle)?;
    Some(f(runtime))
}

fn track_kind_from_u8(value: u8) -> Option<TrackKind> {
    match value {
        0 => Some(TrackKind::Video),
        1 => Some(TrackKind::Image),
        2 => Some(TrackKind::Audio),
        3 => Some(TrackKind::Text),
        4 => Some(TrackKind::LipSync),
        _ => None,
    }
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_version() -> u32 {
    1
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_create_project(
    _width: u32,
    _height: u32,
    _fps: f64,
    _sample_rate: u32,
    _duration_seconds: f64,
) -> i64 {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    let project = ProjectState::new(_width, _height, _fps, _sample_rate, _duration_seconds);
    if let Ok(mut guard) = runtimes().lock() {
        guard.insert(handle, EngineRuntime::new(project));
        handle
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_dispose_project(handle: i64) -> u8 {
    if handle <= 0 {
        return 0;
    }

    if let Ok(mut guard) = runtimes().lock() {
        if guard.remove(&handle).is_some() {
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_play(handle: i64) -> u8 {
    with_runtime(handle, |runtime| {
        runtime.transport.play(runtime.project.duration_seconds);
        1
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_pause(handle: i64) -> u8 {
    with_runtime(handle, |runtime| {
        runtime.transport.pause(runtime.project.duration_seconds);
        1
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_seek(handle: i64, seconds: f64, _frame: i64) -> u8 {
    with_runtime(handle, |runtime| {
        runtime
            .transport
            .seek(seconds, runtime.project.duration_seconds);
        1
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_get_playback_state(handle: i64) -> u8 {
    with_runtime(handle, |runtime| {
        runtime
            .transport
            .snapshot(runtime.project.fps, runtime.project.duration_seconds)
            .playback_state as u8
    })
    .unwrap_or(PlaybackState::Stopped as u8)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_get_position_seconds(handle: i64) -> f64 {
    with_runtime(handle, |runtime| {
        runtime
            .transport
            .snapshot(runtime.project.fps, runtime.project.duration_seconds)
            .position_seconds
    })
    .unwrap_or(0.0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_get_position_frame(handle: i64) -> i64 {
    with_runtime(handle, |runtime| {
        runtime
            .transport
            .snapshot(runtime.project.fps, runtime.project.duration_seconds)
            .frame
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_is_buffering(handle: i64) -> u8 {
    with_runtime(handle, |runtime| {
        let snapshot = runtime
            .transport
            .snapshot(runtime.project.fps, runtime.project.duration_seconds);
        if snapshot.is_buffering {
            1
        } else {
            0
        }
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_split_selected_clip(
    handle: i64,
    clip_id: *const std::os::raw::c_char,
    seconds: f64,
    _frame: i64,
) -> u8 {
    if clip_id.is_null() {
        return 0;
    }

    let Ok(clip_id) = unsafe { CStr::from_ptr(clip_id) }.to_str() else {
        return 0;
    };

    with_runtime(handle, |runtime| {
        if runtime.project.split_clip(clip_id, seconds) {
            1
        } else {
            0
        }
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_trim_clip_left(
    handle: i64,
    clip_id: *const std::os::raw::c_char,
    seconds: f64,
    _frame: i64,
) -> u8 {
    if clip_id.is_null() {
        return 0;
    }

    let Ok(clip_id) = unsafe { CStr::from_ptr(clip_id) }.to_str() else {
        return 0;
    };

    with_runtime(handle, |runtime| {
        if runtime.project.trim_clip_left(clip_id, seconds) {
            1
        } else {
            0
        }
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_trim_clip_right(
    handle: i64,
    clip_id: *const std::os::raw::c_char,
    seconds: f64,
    _frame: i64,
) -> u8 {
    if clip_id.is_null() {
        return 0;
    }

    let Ok(clip_id) = unsafe { CStr::from_ptr(clip_id) }.to_str() else {
        return 0;
    };

    with_runtime(handle, |runtime| {
        if runtime.project.trim_clip_right(clip_id, seconds) {
            1
        } else {
            0
        }
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_delete_clip(
    handle: i64,
    clip_id: *const std::os::raw::c_char,
) -> u8 {
    if clip_id.is_null() {
        return 0;
    }

    let Ok(clip_id) = unsafe { CStr::from_ptr(clip_id) }.to_str() else {
        return 0;
    };

    with_runtime(handle, |runtime| {
        if runtime.project.delete_clip(clip_id) {
            1
        } else {
            0
        }
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_duplicate_clip(
    handle: i64,
    clip_id: *const std::os::raw::c_char,
) -> u8 {
    if clip_id.is_null() {
        return 0;
    }

    let Ok(clip_id) = unsafe { CStr::from_ptr(clip_id) }.to_str() else {
        return 0;
    };

    with_runtime(handle, |runtime| {
        if runtime.project.duplicate_clip(clip_id) {
            1
        } else {
            0
        }
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_insert_clip(
    handle: i64,
    track_kind: u8,
    clip_id: *const std::os::raw::c_char,
    duration_seconds: f64,
    is_media: u8,
) -> u8 {
    if clip_id.is_null() {
        return 0;
    }

    let Some(kind) = track_kind_from_u8(track_kind) else {
        return 0;
    };

    let Ok(clip_id) = unsafe { CStr::from_ptr(clip_id) }.to_str() else {
        return 0;
    };

    with_runtime(handle, |runtime| {
        if runtime
            .project
            .insert_clip(kind, clip_id, duration_seconds, is_media != 0)
        {
            1
        } else {
            0
        }
    })
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_get_timeline_json(handle: i64) -> *mut std::os::raw::c_char {
    let Some(json) = with_runtime(handle, |runtime| {
        serde_json::to_string(&runtime.project.tracks).ok()
    })
    .flatten() else {
        return std::ptr::null_mut();
    };

    match CString::new(json) {
        Ok(value) => value.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn fusion_video_engine_free_string(value: *mut std::os::raw::c_char) {
    if value.is_null() {
        return;
    }

    unsafe {
        let _ = CString::from_raw(value);
    }
}
