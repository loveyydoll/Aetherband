//! Lock-free Single-Producer Single-Consumer (SPSC) command and telemetry queues.
//!
//! Provides wait-free, non-blocking communication between the UI control thread
//! and the hard real-time audio thread.

use crate::track::TrackPlayer;
use rtrb::{Consumer, Producer, RingBuffer};

// ─────────────────────────────────────────────────────────────────────────────
// Track identifier
// ─────────────────────────────────────────────────────────────────────────────

/// Unique identifier for an audio track, stable across the entire session.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TrackId(pub u32);

// ─────────────────────────────────────────────────────────────────────────────
// Commands (UI/Control thread → Audio thread)
// ─────────────────────────────────────────────────────────────────────────────

/// Commands sent from the UI/Control thread to the real-time Audio thread.
///
/// # Note on derives
/// This enum cannot be `Copy` or `Clone` because `AddTrack` and `RestartTrack`
/// carry raw pointers (a `Box` smuggled as `usize`). Cloning that value would
/// create two owners of the same heap block and cause a double-free.
/// We implement `Debug` manually for the pointer-carrying variants where needed.
#[derive(Debug)]
pub enum EngineCommand {
    SynthEvent {
        event: u32,
        key: u32,
        value: f32,
    },
    ConfigureTransport {
        bpm: f32,
        metronome: bool,
        sequence: bool,
    },
    // --- Transport ---
    /// Start audio playback.
    Play,
    /// Pause audio playback without resetting the playhead.
    Pause,
    /// Stop audio playback and rewind playhead to 0.
    Stop,
    /// Seek playhead to an absolute sample index.
    Seek(i64),

    // --- Master ---
    /// Set master volume target gain with de-zippering frame duration.
    SetMasterVolume {
        target_gain: f32,
        ramp_frames: usize,
    },

    // --- Test tone (diagnostic) ---
    /// Enable or disable the diagnostic test tone oscillator.
    SetTestTone {
        enabled: bool,
        frequency_hz: f32,
    },

    // --- Track mixing ---
    /// Set per-track volume with de-zippering over ramp_frames.
    SetTrackVolume {
        track_id: TrackId,
        target_gain: f32,
        ramp_frames: usize,
    },
    /// Set per-track pan position (0.0 = full left, 0.5 = centre, 1.0 = full right).
    SetTrackPan {
        track_id: TrackId,
        pan: f32,
    },
    /// Schedule a track at an absolute session frame.
    SetTrackStartFrame {
        track_id: TrackId,
        start_frame: i64,
    },
    /// Mute or unmute a track.
    MuteTrack {
        track_id: TrackId,
        muted: bool,
    },
    /// Solo one track; the mixer applies implicit solo to every other track.
    SoloTrack {
        track_id: TrackId,
        solo: bool,
    },

    // --- Track lifecycle ---
    /// Install a new `TrackPlayer` on the audio thread.
    ///
    /// `player_ptr` is a `Box<TrackPlayer>` cast to `usize` via `Box::into_raw`.
    /// The audio thread is the **sole** receiver and immediately re-boxes it with
    /// `Box::from_raw`. No aliasing occurs. This is documented in ADR-004.
    AddTrack {
        player_ptr: usize,
    },

    /// Remove a track from the audio thread by ID.
    RemoveTrack {
        track_id: TrackId,
    },

    /// Replace the stream consumer of an existing track and reset its playback
    /// cursor. Used by the control thread after restarting a StreamDecoder so
    /// that Stop → Play restarts audio from the beginning of the file.
    ///
    /// `player_ptr` owns a complete replacement player; the old player is retired off-thread.
    RestartTrack {
        track_id: TrackId,
        player_ptr: usize,
    },
}

// ─────────────────────────────────────────────────────────────────────────────
// Telemetry (Audio thread → UI/Control thread)
// ─────────────────────────────────────────────────────────────────────────────

/// Telemetry and metering frame sent from the real-time Audio thread to the UI thread.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct TelemetryFrame {
    /// Linear peak amplitude on Left channel [0.0, 1.0+].
    pub peak_left: f32,
    /// Linear peak amplitude on Right channel [0.0, 1.0+].
    pub peak_right: f32,
    /// Root-Mean-Square level on Left channel.
    pub rms_left: f32,
    /// Root-Mean-Square level on Right channel.
    pub rms_right: f32,
    /// Current playhead position in absolute audio samples.
    pub playhead_frame: i64,
    /// Total length of the longest track in samples (0 if no tracks loaded).
    pub total_duration_frames: i64,
    /// Whether the transport is currently playing.
    pub is_playing: bool,
    /// Non-zero if an audio device error occurred.
    pub device_error_flag: u8,
}

// ─────────────────────────────────────────────────────────────────────────────
// Disk-stream buffer shared between decoder worker and audio thread
// ─────────────────────────────────────────────────────────────────────────────

/// A pre-decoded stereo audio block ready to be consumed by the audio thread.
///
/// Carries exactly `capacity` stereo frames stored as **interleaved** L/R samples
/// in a heap-allocated backing buffer that is allocated **once** at startup.
#[derive(Clone)]
pub struct DecodedBlock {
    /// Interleaved stereo samples [L0, R0, L1, R1, …]
    pub samples: Vec<f32>,
    /// The playhead position (in samples) of the first frame in this block.
    pub start_frame: i64,
    /// Actual number of valid stereo frames in `samples` (may be < capacity on EOF).
    pub valid_frames: usize,
    /// True when this block contains the final frames of the file.
    pub is_last: bool,
}

impl DecodedBlock {
    /// Creates a silent block with capacity for `frames` stereo frames.
    pub fn silent(frames: usize) -> Self {
        Self {
            samples: vec![0.0f32; frames * 2],
            start_frame: 0,
            valid_frames: frames,
            is_last: false,
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Endpoint bundles
// ─────────────────────────────────────────────────────────────────────────────

/// UI-thread side of the engine communication queues.
pub struct UIEndpoints {
    pub cmd_producer: Producer<EngineCommand>,
    pub telemetry_consumer: Consumer<TelemetryFrame>,
    /// Track players retired by the audio thread; drop them on the control thread.
    pub retired_tracks: Consumer<Box<TrackPlayer>>,
    pub retired_blocks: Consumer<DecodedBlock>,
}

/// Audio-thread side of the engine communication queues.
pub struct AudioEndpoints {
    pub cmd_consumer: Consumer<EngineCommand>,
    pub telemetry_producer: Producer<TelemetryFrame>,
    /// Returns retired players to the control thread without freeing memory in the callback.
    pub retired_tracks: Producer<Box<TrackPlayer>>,
    pub retired_blocks: Producer<DecodedBlock>,
}

/// Creates the lock-free ring buffer communication endpoints.
pub fn create_engine_queues(
    cmd_capacity: usize,
    telemetry_capacity: usize,
) -> (UIEndpoints, AudioEndpoints) {
    let (retired_blocks_tx, retired_blocks_rx) = RingBuffer::new(2048);
    let (cmd_producer, cmd_consumer) = RingBuffer::new(cmd_capacity);
    let (telemetry_producer, telemetry_consumer) = RingBuffer::new(telemetry_capacity);
    // Capacity exceeds the command queue and active-track limit. If it ever fills,
    // the audio processor keeps retired players in a fixed-size deferred array and
    // pauses command consumption until the control thread reclaims them.
    let (retired_producer, retired_consumer) = RingBuffer::new(cmd_capacity * 2);

    (
        UIEndpoints {
            cmd_producer,
            telemetry_consumer,
            retired_tracks: retired_consumer,
            retired_blocks: retired_blocks_rx,
        },
        AudioEndpoints {
            cmd_consumer,
            telemetry_producer,
            retired_tracks: retired_producer,
            retired_blocks: retired_blocks_tx,
        },
    )
}

/// Creates a disk-stream SPSC ring buffer pair for a single track.
///
/// `block_count` is the number of `DecodedBlock` slots in the ring.
pub fn create_stream_queue(block_count: usize) -> (Producer<DecodedBlock>, Consumer<DecodedBlock>) {
    RingBuffer::new(block_count)
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_queue_push_and_pop() {
        let (mut ui, mut audio) = create_engine_queues(16, 16);

        // UI pushes command
        assert!(ui.cmd_producer.push(EngineCommand::Play).is_ok());

        // Audio pops command
        let cmd = audio.cmd_consumer.pop();
        assert!(matches!(cmd, Ok(EngineCommand::Play)));

        // Audio pushes telemetry
        let frame = TelemetryFrame {
            peak_left: 0.8,
            peak_right: 0.75,
            playhead_frame: 1024,
            is_playing: true,
            ..Default::default()
        };
        assert!(audio.telemetry_producer.push(frame).is_ok());

        // UI pops telemetry
        let received = ui.telemetry_consumer.pop();
        assert_eq!(received, Ok(frame));
    }

    #[test]
    fn test_track_id_equality() {
        let a = TrackId(1);
        let b = TrackId(1);
        let c = TrackId(2);
        assert_eq!(a, b);
        assert_ne!(a, c);
    }
}
