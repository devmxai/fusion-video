use std::time::Instant;

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackState {
    Stopped,
    Playing,
    Paused,
    Scrubbing,
}

#[derive(Debug, Clone, Copy)]
pub struct TransportSnapshot {
    pub playback_state: PlaybackState,
    pub position_seconds: f64,
    pub frame: i64,
    pub is_buffering: bool,
}

#[derive(Debug)]
pub struct TransportState {
    playback_state: PlaybackState,
    position_seconds: f64,
    last_tick_at: Option<Instant>,
}

impl Default for TransportState {
    fn default() -> Self {
        Self {
            playback_state: PlaybackState::Stopped,
            position_seconds: 0.0,
            last_tick_at: None,
        }
    }
}

impl TransportState {
    fn tick(&mut self, duration_seconds: f64) {
        if self.playback_state != PlaybackState::Playing {
            return;
        }

        let now = Instant::now();
        let last_tick = self.last_tick_at.unwrap_or(now);
        self.last_tick_at = Some(now);
        let delta = now.duration_since(last_tick).as_secs_f64();
        if delta <= 0.0 {
            return;
        }

        self.position_seconds = (self.position_seconds + delta).clamp(0.0, duration_seconds);
        if self.position_seconds >= duration_seconds {
            self.position_seconds = duration_seconds;
            self.playback_state = PlaybackState::Paused;
            self.last_tick_at = None;
        }
    }

    pub fn play(&mut self, duration_seconds: f64) {
        self.tick(duration_seconds);
        if self.playback_state == PlaybackState::Playing {
            return;
        }
        self.playback_state = PlaybackState::Playing;
        self.last_tick_at = Some(Instant::now());
    }

    pub fn pause(&mut self, duration_seconds: f64) {
        self.tick(duration_seconds);
        self.last_tick_at = None;
        self.playback_state = if self.position_seconds <= 0.0 {
            PlaybackState::Stopped
        } else {
            PlaybackState::Paused
        };
    }

    pub fn seek(&mut self, seconds: f64, duration_seconds: f64) {
        self.position_seconds = seconds.clamp(0.0, duration_seconds);
        self.last_tick_at = if self.playback_state == PlaybackState::Playing {
            Some(Instant::now())
        } else {
            None
        };

        if self.playback_state != PlaybackState::Playing {
            self.playback_state = if self.position_seconds <= 0.0 {
                PlaybackState::Stopped
            } else {
                PlaybackState::Paused
            };
        }
    }

    pub fn snapshot(&mut self, fps: f64, duration_seconds: f64) -> TransportSnapshot {
        self.tick(duration_seconds);
        TransportSnapshot {
            playback_state: self.playback_state,
            position_seconds: self.position_seconds,
            frame: (self.position_seconds * fps).round() as i64,
            is_buffering: false,
        }
    }
}
