//! RouletteStudio Audio Core Library
//!
//! Owns the audio processing pipeline, DSP algorithms, audio driver I/O,
//! lock-free concurrency queues, and multi-track playback.

pub mod audio;
pub mod decoder;
pub mod device;
pub mod dsp;
pub mod ringbuf;
pub mod track;
pub mod transport;

use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicU32, Ordering};

use audio::AudioProcessor;
use decoder::{probe_file, AudioFileInfo, DecoderError, StreamDecoder};
use device::{ActiveStream, AudioBackend, CpalBackend, DeviceError, DeviceInfo};
use ringbuf::{create_engine_queues, EngineCommand, TelemetryFrame, TrackId, UIEndpoints};
use track::TrackPlayer;

/// Core engine version.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

// ─────────────────────────────────────────────────────────────────────────────
// Error types
// ─────────────────────────────────────────────────────────────────────────────

/// Errors that can originate from the DAW engine layer.
#[derive(Debug)]
pub enum EngineError {
    Device(DeviceError),
    Decoder(DecoderError),
    TrackLimitReached,
    TrackNotFound(TrackId),
}

impl From<DeviceError> for EngineError {
    fn from(e: DeviceError) -> Self { EngineError::Device(e) }
}

impl From<DecoderError> for EngineError {
    fn from(e: DecoderError) -> Self { EngineError::Decoder(e) }
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EngineError::Device(e) => write!(f, "Audio device error: {}", e),
            EngineError::Decoder(e) => write!(f, "Decode error: {}", e),
            EngineError::TrackLimitReached => write!(f, "Maximum track count reached"),
            EngineError::TrackNotFound(id) => write!(f, "Track {:?} not found", id),
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Track metadata held on the control thread
// ─────────────────────────────────────────────────────────────────────────────

/// Metadata about a loaded audio track, kept on the control thread.
#[derive(Debug, Clone)]
pub struct TrackInfo {
    pub id: TrackId,
    pub file_path: String,
    pub info: AudioFileInfo,
    /// Duration converted to output sample-rate frames.
    pub output_frames: i64,
}

// ─────────────────────────────────────────────────────────────────────────────
// DAW Engine
// ─────────────────────────────────────────────────────────────────────────────

/// Global monotonic track ID counter.
static NEXT_TRACK_ID: AtomicU32 = AtomicU32::new(1);

fn next_track_id() -> TrackId {
    TrackId(NEXT_TRACK_ID.fetch_add(1, Ordering::Relaxed))
}

/// The primary high-level engine controller.
///
/// Lives on the control/UI thread. Communicates with the audio thread
/// exclusively through lock-free ring buffers.
pub struct DAWEngine {
    backend: CpalBackend,
    active_stream: Option<ActiveStream>,
    ui_endpoints: UIEndpoints,
    current_device_index: Option<usize>,
    output_sample_rate: u32,

    /// Live decoder workers, one per track. Kept alive here so the OS thread
    /// keeps running. Dropped when a track is removed.
    decoders: HashMap<u32, StreamDecoder>,

    /// Metadata about each loaded track.
    tracks: Vec<TrackInfo>,
}

impl DAWEngine {
    /// Creates a new DAW engine and opens the default audio output stream.
    pub fn new() -> Result<Self, EngineError> {
        let mut backend = CpalBackend::new()?;
        let (ui_endpoints, audio_endpoints) = create_engine_queues(1024, 2048);

        let processor = AudioProcessor::new(48000.0, audio_endpoints);
        let active_stream = backend.start_output_stream(None, processor)?;
        let output_sample_rate = active_stream.sample_rate();

        Ok(Self {
            backend,
            active_stream: Some(active_stream),
            ui_endpoints,
            current_device_index: None,
            output_sample_rate,
            decoders: HashMap::new(),
            tracks: Vec::new(),
        })
    }

    // ── Device management ─────────────────────────────────────────────────

    /// Enumerates all available output devices.
    pub fn enumerate_devices(&self) -> Result<Vec<DeviceInfo>, DeviceError> {
        self.backend.enumerate_output_devices()
    }

    /// Switches the active output device by index, restarting the audio stream.
    pub fn select_device(&mut self, device_index: usize) -> Result<(), EngineError> {
        self.active_stream = None; // Drop old stream first

        let (ui_endpoints, audio_endpoints) = create_engine_queues(1024, 2048);
        let processor = AudioProcessor::new(48000.0, audio_endpoints);
        let active_stream = self.backend.start_output_stream(Some(device_index), processor)?;

        self.output_sample_rate = active_stream.sample_rate();
        self.ui_endpoints = ui_endpoints;
        self.active_stream = Some(active_stream);
        self.current_device_index = Some(device_index);

        Ok(())
    }

    /// Returns the active audio device name, if any.
    pub fn active_device_name(&self) -> Option<&str> {
        self.active_stream.as_ref().map(|s| s.device_name())
    }

    // ── Transport controls ────────────────────────────────────────────────

    pub fn play(&mut self) -> bool {
        self.ui_endpoints.cmd_producer.push(EngineCommand::Play).is_ok()
    }

    pub fn pause(&mut self) -> bool {
        self.ui_endpoints.cmd_producer.push(EngineCommand::Pause).is_ok()
    }

    pub fn stop(&mut self) -> bool {
        self.ui_endpoints.cmd_producer.push(EngineCommand::Stop).is_ok()
    }

    pub fn seek(&mut self, frame: i64) -> bool {
        self.ui_endpoints.cmd_producer.push(EngineCommand::Seek(frame)).is_ok()
    }

    // ── Master ────────────────────────────────────────────────────────────

    /// Sets master volume with 256-sample de-zippering ramp.
    pub fn set_master_volume(&mut self, target_gain: f32) -> bool {
        self.ui_endpoints
            .cmd_producer
            .push(EngineCommand::SetMasterVolume {
                target_gain: target_gain.clamp(0.0, 2.0),
                ramp_frames: 256,
            })
            .is_ok()
    }

    /// Enables or disables the diagnostic test tone.
    pub fn set_test_tone(&mut self, enabled: bool, frequency_hz: f32) -> bool {
        self.ui_endpoints
            .cmd_producer
            .push(EngineCommand::SetTestTone { enabled, frequency_hz })
            .is_ok()
    }

    // ── Track management ──────────────────────────────────────────────────

    /// Loads an audio file, spawns a background decoder, and returns the new `TrackId`.
    ///
    /// The decoder immediately starts streaming decoded blocks into the audio thread.
    pub fn load_track(&mut self, path: &Path) -> Result<TrackId, EngineError> {
        let info = probe_file(path)?;
        let id = next_track_id();

        // Compute total duration in output sample-rate frames
        let output_frames = if info.sample_rate > 0 {
            (info.total_frames as f64 * self.output_sample_rate as f64 / info.sample_rate as f64)
                as i64
        } else {
            0
        };

        // Spawn background decoder
        let mut decoder = StreamDecoder::spawn(path, self.output_sample_rate)?;

        // NOTE: Because `AudioProcessor` owns the audio thread exclusively,
        // we cannot push a TrackPlayer into it at runtime without a lock.
        // The architectural solution is a setup queue — a one-time SPSC channel
        // for installing new TrackPlayers before they start playing.
        //
        // For Phase 2, we use a simpler approach: the TrackPlayer and its
        // Consumer are created here; a `AddTrack` command carries the boxed
        // TrackPlayer across the boundary. The audio thread installs it via
        // the existing command queue.
        //
        // Because the TrackPlayer is not Copy, we smuggle it as a raw pointer
        // wrapped in a usize (pointer integer). This is safe because:
        //  - The pointer is created here, sent once through the queue, and
        //    immediately re-boxed on the audio side.
        //  - The audio thread is the sole receiver so no aliasing occurs.
        //
        // This is an explicit, documented unsafe boundary consistent with ADR-004.

        // Take the consumer out of the decoder *before* we move decoder into the map.
        // The decoder is then stored with consumer = None; it lives only for
        // its stop_flag so the background thread can be cancelled later.
        let consumer = decoder.take_consumer();

        let player = Box::new(TrackPlayer::new(
            id,
            consumer,
            0.8,           // initial gain
            output_frames,
        ));

        // Store decoder (consumer already taken) and metadata
        self.decoders.insert(id.0, decoder);
        self.tracks.push(TrackInfo {
            id,
            file_path: path.display().to_string(),
            info,
            output_frames,
        });

        // Smuggle the player as a raw pointer through the command queue.
        // The audio thread re-boxes it in the AddTrack handler (see audio.rs).
        let raw = Box::into_raw(player) as usize;
        if self.ui_endpoints.cmd_producer
            .push(EngineCommand::AddTrack { player_ptr: raw })
            .is_err()
        {
            // Queue full: reclaim and drop the player to avoid leak
            let _ = unsafe { Box::from_raw(raw as *mut TrackPlayer) };
            self.decoders.remove(&id.0);
            self.tracks.pop();
            return Err(EngineError::TrackLimitReached);
        }

        Ok(id)
    }

    /// Removes a track by ID.
    pub fn remove_track(&mut self, id: TrackId) -> bool {
        if let Some(pos) = self.tracks.iter().position(|t| t.id == id) {
            self.tracks.remove(pos);
            if let Some(decoder) = self.decoders.remove(&id.0) {
                decoder.stop();
            }
            let _ = self.ui_endpoints.cmd_producer
                .push(EngineCommand::RemoveTrack { track_id: id });
            true
        } else {
            false
        }
    }

    /// Returns metadata for all loaded tracks.
    pub fn tracks(&self) -> &[TrackInfo] {
        &self.tracks
    }

    // ── Per-track mixing controls ─────────────────────────────────────────

    pub fn set_track_volume(&mut self, track_id: TrackId, gain: f32) -> bool {
        self.ui_endpoints.cmd_producer.push(EngineCommand::SetTrackVolume {
            track_id,
            target_gain: gain.clamp(0.0, 2.0),
            ramp_frames: 256,
        }).is_ok()
    }

    pub fn set_track_pan(&mut self, track_id: TrackId, pan: f32) -> bool {
        self.ui_endpoints.cmd_producer.push(EngineCommand::SetTrackPan {
            track_id,
            pan: pan.clamp(0.0, 1.0),
        }).is_ok()
    }

    pub fn mute_track(&mut self, track_id: TrackId, muted: bool) -> bool {
        self.ui_endpoints.cmd_producer.push(EngineCommand::MuteTrack {
            track_id,
            muted,
        }).is_ok()
    }

    // ── Telemetry ─────────────────────────────────────────────────────────

    /// Polls the latest telemetry frame from the audio thread.
    pub fn poll_telemetry(&mut self) -> Option<TelemetryFrame> {
        let mut latest = None;
        while let Ok(frame) = self.ui_endpoints.telemetry_consumer.pop() {
            latest = Some(frame);
        }
        latest
    }
}
