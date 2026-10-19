//! Aetherband Audio Core Library
//!
//! Owns the audio processing pipeline, DSP algorithms, audio driver I/O,
//! lock-free concurrency queues, and multi-track playback.

pub mod audio;
pub mod decoder;
pub mod device;
pub mod dsp;
mod envelope;
pub mod graph;
pub mod hypnosynth;
mod offline_export;
pub mod ringbuf;
pub mod spatial;
pub mod track;
pub mod transport;

use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicU32, Ordering};

use audio::AudioProcessor;
use decoder::{probe_file, AudioFileInfo, DecoderError, StreamDecoder};
use device::{
    ActiveRecording, ActiveStream, AudioBackend, CpalBackend, DeviceError, DeviceInfo,
    RecordingStats,
};
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
    Recording(String),
}

impl From<DeviceError> for EngineError {
    fn from(e: DeviceError) -> Self {
        EngineError::Device(e)
    }
}

impl From<DecoderError> for EngineError {
    fn from(e: DecoderError) -> Self {
        EngineError::Decoder(e)
    }
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EngineError::Device(e) => write!(f, "Audio device error: {}", e),
            EngineError::Decoder(e) => write!(f, "Decode error: {}", e),
            EngineError::TrackLimitReached => write!(f, "Maximum track count reached"),
            EngineError::TrackNotFound(id) => write!(f, "Track {:?} not found", id),
            EngineError::Recording(message) => write!(f, "Recording error: {message}"),
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
    /// Arrangement start position in output-rate frames.
    pub start_frame: i64,
    pub gain: f32,
    pub pan: f32,
    pub muted: bool,
    pub solo: bool,
}

// ─────────────────────────────────────────────────────────────────────────────
// DAW Engine
// ─────────────────────────────────────────────────────────────────────────────

/// Global monotonic track ID counter.
static NEXT_TRACK_ID: AtomicU32 = AtomicU32::new(1);

fn next_track_id() -> TrackId {
    TrackId(NEXT_TRACK_ID.fetch_add(1, Ordering::Relaxed))
}

fn rescale_frame(frame: i64, from_rate: u32, to_rate: u32) -> i64 {
    if frame <= 0 {
        return frame;
    }
    (frame as f64 * to_rate as f64 / from_rate.max(1) as f64).round() as i64
}

/// The primary high-level engine controller.
///
/// Lives on the control/UI thread. Communicates with the audio thread
/// exclusively through lock-free ring buffers.
pub struct DAWEngine {
    backend: CpalBackend,
    active_stream: Option<ActiveStream>,
    recording: Option<ActiveRecording>,
    ui_endpoints: UIEndpoints,
    current_device_index: Option<usize>,
    output_sample_rate: u32,

    /// Live decoder workers, one per track. Kept alive here so the OS thread
    /// keeps running. Dropped when a track is removed.
    decoders: HashMap<u32, StreamDecoder>,

    /// Metadata about each loaded track.
    tracks: Vec<TrackInfo>,
    master_gain: f32,
    bpm: f32,
    metronome: bool,
    sequence: bool,
    preset: u8,
    macros: [f32; 5],
}

impl DAWEngine {
    /// Creates a new DAW engine and opens the default audio output stream.
    pub fn new() -> Result<Self, EngineError> {
        let mut backend = CpalBackend::new()?;
        let (ui_endpoints, audio_endpoints) = create_engine_queues(1024, 2048);

        let sample_rate = backend.output_sample_rate(None)?;
        let processor = AudioProcessor::new(sample_rate as f32, audio_endpoints);
        let active_stream = backend.start_output_stream(None, processor)?;
        let output_sample_rate = active_stream.sample_rate();

        Ok(Self {
            backend,
            active_stream: Some(active_stream),
            recording: None,
            ui_endpoints,
            current_device_index: None,
            output_sample_rate,
            decoders: HashMap::new(),
            tracks: Vec::new(),
            master_gain: 0.8,
            bpm: 92.0,
            metronome: false,
            sequence: false,
            preset: 0,
            macros: [0.42, 0.38, 0.55, 0.36, 0.7],
        })
    }

    // ── Device management ─────────────────────────────────────────────────

    /// Enumerates all available output devices.
    pub fn enumerate_devices(&self) -> Result<Vec<DeviceInfo>, DeviceError> {
        self.backend.enumerate_output_devices()
    }

    /// Switches the active output device by index, restarting the audio stream.
    pub fn select_device(&mut self, device_index: usize) -> Result<(), EngineError> {
        // Prepare all decoders and players before starting the replacement stream.
        // This means a device/configuration/decoder error leaves the old stream
        // and its queues untouched.
        let sample_rate = self.backend.output_sample_rate(Some(device_index))?;
        let (mut new_ui_endpoints, audio_endpoints) = create_engine_queues(1024, 2048);
        let mut new_decoders = HashMap::new();
        let mut new_track_infos = Vec::with_capacity(self.tracks.len());
        let mut new_players = Vec::with_capacity(self.tracks.len());

        for track in &self.tracks {
            let mut decoder = StreamDecoder::spawn(Path::new(&track.file_path), sample_rate)?;
            let consumer = decoder.take_consumer();
            let output_frames = if track.info.sample_rate > 0 {
                (track.info.total_frames as f64 * sample_rate as f64
                    / track.info.sample_rate as f64) as i64
            } else {
                0
            };
            let mut player = TrackPlayer::new(track.id, consumer, track.gain, output_frames);
            player.pan = track.pan;
            player.muted = track.muted;
            // Arrangement positions are stored in output-rate frames. Preserve
            // their time when the newly selected device uses another rate.
            let start_frame =
                rescale_frame(track.start_frame, self.output_sample_rate, sample_rate);
            player.start_frame = start_frame;
            player.solo = track.solo;
            new_players.push(player);
            new_decoders.insert(track.id.0, decoder);
            let mut updated = track.clone();
            updated.output_frames = output_frames;
            updated.start_frame = start_frame;
            new_track_infos.push(updated);
        }

        // Recreate processor state before the stream starts. A device switch
        // must preserve session performance settings instead of reverting to
        // AudioProcessor defaults.
        let commands = &mut new_ui_endpoints.cmd_producer;
        commands
            .push(EngineCommand::ConfigureTransport {
                bpm: self.bpm,
                metronome: self.metronome,
                sequence: self.sequence,
            })
            .expect("fresh device command queue has capacity");
        commands
            .push(EngineCommand::SynthEvent {
                event: 2,
                key: self.preset as u32,
                value: 0.0,
            })
            .expect("fresh device command queue has capacity");
        for (key, value) in self.macros.iter().copied().enumerate() {
            commands
                .push(EngineCommand::SynthEvent {
                    event: 3,
                    key: key as u32,
                    value,
                })
                .expect("fresh device command queue has capacity");
        }
        commands
            .push(EngineCommand::SetMasterVolume {
                target_gain: self.master_gain,
                ramp_frames: 0,
            })
            .expect("fresh device command queue has capacity");

        // Start the replacement stream only after decoder setup succeeds. It may
        // output silence briefly while the pre-built track players are installed.
        let processor = AudioProcessor::new(sample_rate as f32, audio_endpoints);
        let new_stream = self
            .backend
            .start_output_stream(Some(device_index), processor)?;

        for player in new_players {
            let raw = Box::into_raw(Box::new(player)) as usize;
            if new_ui_endpoints
                .cmd_producer
                .push(EngineCommand::AddTrack { player_ptr: raw })
                .is_err()
            {
                // The queue capacity is far above the supported track limit; this
                // can only indicate an internal invariant failure. Do not attempt
                // to reclaim raw pointers here because the running callback may
                // already have taken ownership of them.
                drop(new_stream);
                return Err(EngineError::TrackLimitReached);
            }
        }

        // Commit the new graph/queues together. Replacing the old stream stops its
        // callback before the old queue endpoints and decoder workers are dropped.
        let new_sample_rate = new_stream.sample_rate();
        self.active_stream = Some(new_stream);
        self.ui_endpoints = new_ui_endpoints;
        self.decoders = new_decoders;
        self.tracks = new_track_infos;
        self.output_sample_rate = new_sample_rate;
        self.current_device_index = Some(device_index);

        Ok(())
    }
    /// Returns the active output stream's sample rate in Hz.
    pub fn output_sample_rate(&self) -> u32 {
        self.output_sample_rate
    }

    /// Starts stereo recording from the default Windows input to a new WAV file.
    pub fn start_recording(&mut self, path: &Path) -> Result<u32, EngineError> {
        if self.recording.is_some() {
            return Err(EngineError::Recording(
                "a recording is already active".into(),
            ));
        }
        let recording = self.backend.start_recording(path)?;
        let sample_rate = recording.sample_rate();
        self.recording = Some(recording);
        Ok(sample_rate)
    }

    /// Stops capture, drains the writer queue and finalizes the WAV header.
    pub fn stop_recording(&mut self) -> Result<RecordingStats, EngineError> {
        self.recording
            .take()
            .ok_or_else(|| EngineError::Recording("no recording is active".into()))?
            .finish()
            .map_err(EngineError::Recording)
    }

    /// Returns the active audio device name, if any.
    pub fn active_device_name(&self) -> Option<&str> {
        self.active_stream.as_ref().map(|s| s.device_name())
    }

    // ── Transport controls ────────────────────────────────────────────────

    pub fn play(&mut self) -> bool {
        self.ui_endpoints
            .cmd_producer
            .push(EngineCommand::Play)
            .is_ok()
    }

    pub fn pause(&mut self) -> bool {
        self.ui_endpoints
            .cmd_producer
            .push(EngineCommand::Pause)
            .is_ok()
    }

    /// Stops playback, resets the playhead to zero, and restarts every track's
    /// background decoder from the beginning of its file.
    ///
    /// This is the control-thread half of the Stop protocol required by issue #5:
    /// - Audio thread receives `EngineCommand::Stop` → sets `is_playing = false`,
    ///   playhead = 0, drains track consumers.
    /// - Control thread stops the old StreamDecoders and spawns fresh ones so
    ///   the next Play consumes audio from frame 0 again.
    pub fn stop(&mut self) -> bool {
        if self.ui_endpoints.cmd_producer.slots() < self.tracks.len() + 1 {
            return false;
        }
        if self
            .ui_endpoints
            .cmd_producer
            .push(EngineCommand::Stop)
            .is_err()
        {
            return false;
        }
        let mut replacements = Vec::with_capacity(self.tracks.len());
        for track in &self.tracks {
            let Ok(mut decoder) =
                StreamDecoder::spawn(Path::new(&track.file_path), self.output_sample_rate)
            else {
                return false;
            };
            let mut player = Box::new(TrackPlayer::new(
                track.id,
                decoder.take_consumer(),
                track.gain,
                track.output_frames,
            ));
            player.pan = track.pan;
            player.muted = track.muted;
            replacements.push((track.id, decoder, player));
        }
        // Single producer: slots reserved above cannot be consumed by another sender.
        for (track_id, decoder, player) in replacements {
            let player_ptr = Box::into_raw(player) as usize;
            if self
                .ui_endpoints
                .cmd_producer
                .push(EngineCommand::RestartTrack {
                    track_id,
                    player_ptr,
                })
                .is_err()
            {
                // SAFETY: rejection leaves ownership on this control thread.
                drop(unsafe { Box::from_raw(player_ptr as *mut TrackPlayer) });
                return false;
            }
            self.decoders.insert(track_id.0, decoder);
        }
        true
    }

    pub fn seek(&mut self, frame: i64) -> bool {
        self.ui_endpoints
            .cmd_producer
            .push(EngineCommand::Seek(frame))
            .is_ok()
    }

    // ── Master ────────────────────────────────────────────────────────────

    /// Sets master volume with 256-sample de-zippering ramp.
    pub fn set_master_volume(&mut self, target_gain: f32) -> bool {
        if !target_gain.is_finite() {
            return false;
        }
        let gain = target_gain.clamp(0.0, 2.0);
        let accepted = self
            .ui_endpoints
            .cmd_producer
            .push(EngineCommand::SetMasterVolume {
                target_gain: gain,
                ramp_frames: 256,
            })
            .is_ok();
        if accepted {
            self.master_gain = gain;
        }
        accepted
    }

    /// Enables or disables the diagnostic test tone.
    pub fn set_test_tone(&mut self, enabled: bool, frequency_hz: f32) -> bool {
        self.ui_endpoints
            .cmd_producer
            .push(EngineCommand::SetTestTone {
                enabled,
                frequency_hz,
            })
            .is_ok()
    }

    // ── Track management ──────────────────────────────────────────────────

    /// Bounded instrument events: note on/off, preset, macro, and panic.
    pub fn synth_event(&mut self, event: u32, key: u32, value: f32) -> bool {
        let valid = value.is_finite()
            && match event {
                0 => key <= 127 && (0.0..=1.0).contains(&value),
                1 => key <= 127,
                2 => key < 3,
                3 => key < 5 && (0.0..=1.0).contains(&value),
                4 => true,
                _ => false,
            };
        if !valid {
            return false;
        }
        let accepted = self
            .ui_endpoints
            .cmd_producer
            .push(EngineCommand::SynthEvent { event, key, value })
            .is_ok();
        if accepted {
            match event {
                2 => self.preset = key as u8,
                3 => self.macros[key as usize] = value,
                _ => {}
            }
        }
        accepted
    }

    pub fn configure_transport(&mut self, bpm: f32, metronome: bool, sequence: bool) -> bool {
        let accepted = bpm.is_finite()
            && (30.0..=300.0).contains(&bpm)
            && self
                .ui_endpoints
                .cmd_producer
                .push(EngineCommand::ConfigureTransport {
                    bpm,
                    metronome,
                    sequence,
                })
                .is_ok();
        if accepted {
            self.bpm = bpm;
            self.metronome = metronome;
            self.sequence = sequence;
        }
        accepted
    }

    /// Export a fresh offline stereo mix without seeking or interrupting live playback.
    pub fn export_mixdown(&self, path: &Path) -> Result<(), offline_export::ExportError> {
        let tracks = self
            .tracks
            .iter()
            .map(|track| offline_export::ExportTrack {
                path: Path::new(&track.file_path).to_owned(),
                start_frame: track.start_frame.max(0) as u64,
                total_frames: track.output_frames.max(0) as u64,
                gain: track.gain,
                pan: track.pan,
                muted: track.muted,
                solo: track.solo,
            })
            .collect::<Vec<_>>();
        offline_export::render_stereo_wav(
            path,
            &tracks,
            offline_export::ExportSettings {
                sample_rate: self.output_sample_rate,
                master: self.master_gain,
                bpm: self.bpm,
                metronome: self.metronome,
                sequence: self.sequence,
                preset: self.preset,
                macros: self.macros,
            },
        )
    }

    /// Loads an audio file, spawns a background decoder, and returns the new `TrackId`.
    ///
    /// The decoder immediately starts streaming decoded blocks into the audio thread.
    pub fn load_track(&mut self, path: &Path) -> Result<TrackId, EngineError> {
        if self.tracks.len() >= track::MAX_TRACKS {
            return Err(EngineError::TrackLimitReached);
        }
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

        // Take the consumer out of the decoder *before* we move decoder into the map.
        let consumer = decoder.take_consumer();

        let player = Box::new(TrackPlayer::new(
            id,
            consumer,
            0.8, // initial gain
            output_frames,
        ));

        // Store decoder (consumer already taken) and metadata
        self.decoders.insert(id.0, decoder);
        self.tracks.push(TrackInfo {
            id,
            file_path: path.display().to_string(),
            info,
            output_frames,
            start_frame: 0,
            gain: 0.8,
            pan: 0.5,
            muted: false,
            solo: false,
        });

        // Smuggle the player as a raw pointer through the command queue.
        // The audio thread reconstructs the Box without moving out of it, so the
        // allocation remains owned by TrackSlots and is not freed in the callback.
        let raw = Box::into_raw(player) as usize;
        if self
            .ui_endpoints
            .cmd_producer
            .push(EngineCommand::AddTrack { player_ptr: raw })
            .is_err()
        {
            // Queue full: reclaim and drop the player on this control thread.
            drop(unsafe { Box::from_raw(raw as *mut TrackPlayer) });
            self.decoders.remove(&id.0);
            self.tracks.pop();
            return Err(EngineError::TrackLimitReached);
        }

        Ok(id)
    }

    /// Removes a track by ID.
    pub fn remove_track(&mut self, id: TrackId) -> bool {
        if let Some(pos) = self.tracks.iter().position(|t| t.id == id) {
            // Commit control-side removal only after the audio callback can
            // receive it. On saturation the UI can retry without losing its
            // metadata or stopping a still-installed player's decoder.
            if self
                .ui_endpoints
                .cmd_producer
                .push(EngineCommand::RemoveTrack { track_id: id })
                .is_err()
            {
                return false;
            }
            self.tracks.remove(pos);
            if let Some(mut decoder) = self.decoders.remove(&id.0) {
                decoder.stop();
            }
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
        if !gain.is_finite() {
            return false;
        }
        let gain = gain.clamp(0.0, 2.0);
        let Some(track) = self.tracks.iter_mut().find(|track| track.id == track_id) else {
            return false;
        };
        if self
            .ui_endpoints
            .cmd_producer
            .push(EngineCommand::SetTrackVolume {
                track_id,
                target_gain: gain,
                ramp_frames: 256,
            })
            .is_err()
        {
            return false;
        }
        track.gain = gain;
        true
    }

    pub fn set_track_pan(&mut self, track_id: TrackId, pan: f32) -> bool {
        if !pan.is_finite() {
            return false;
        }
        let pan = pan.clamp(0.0, 1.0);
        let Some(track) = self.tracks.iter_mut().find(|track| track.id == track_id) else {
            return false;
        };
        if self
            .ui_endpoints
            .cmd_producer
            .push(EngineCommand::SetTrackPan { track_id, pan })
            .is_err()
        {
            return false;
        }
        track.pan = pan;
        true
    }

    /// Moves a track's clip to an absolute session time in seconds.
    pub fn set_track_start_seconds(&mut self, track_id: TrackId, seconds: f64) -> bool {
        if !seconds.is_finite() || !(0.0..=86_400.0).contains(&seconds) {
            return false;
        }
        let Some(track) = self.tracks.iter_mut().find(|track| track.id == track_id) else {
            return false;
        };
        let start_frame = (seconds * self.output_sample_rate as f64).round() as i64;
        if self
            .ui_endpoints
            .cmd_producer
            .push(EngineCommand::SetTrackStartFrame {
                track_id,
                start_frame,
            })
            .is_err()
        {
            return false;
        }
        track.start_frame = start_frame;
        true
    }

    pub fn mute_track(&mut self, track_id: TrackId, muted: bool) -> bool {
        let Some(track) = self.tracks.iter_mut().find(|track| track.id == track_id) else {
            return false;
        };
        if self
            .ui_endpoints
            .cmd_producer
            .push(EngineCommand::MuteTrack { track_id, muted })
            .is_err()
        {
            return false;
        }
        track.muted = muted;
        true
    }

    pub fn solo_track(&mut self, track_id: TrackId, solo: bool) -> bool {
        let Some(track) = self.tracks.iter_mut().find(|track| track.id == track_id) else {
            return false;
        };
        if self
            .ui_endpoints
            .cmd_producer
            .push(EngineCommand::SoloTrack { track_id, solo })
            .is_err()
        {
            return false;
        }
        track.solo = solo;
        true
    }

    // ── Telemetry ─────────────────────────────────────────────────────────

    /// Polls the latest telemetry frame from the audio thread.
    pub fn poll_telemetry(&mut self) -> Option<TelemetryFrame> {
        // Reclaim removed/rejected players on the control thread, never in the
        // real-time callback. Drain all available retired ownership each poll.
        while let Ok(player) = self.ui_endpoints.retired_tracks.pop() {
            drop(player);
        }

        while let Ok(block) = self.ui_endpoints.retired_blocks.pop() {
            drop(block);
        }
        let mut latest = None;
        while let Ok(frame) = self.ui_endpoints.telemetry_consumer.pop() {
            latest = Some(frame);
        }
        if self
            .active_stream
            .as_ref()
            .is_some_and(|stream| !stream.is_running())
        {
            let frame = latest.get_or_insert_with(TelemetryFrame::default);
            frame.device_error_flag = 1;
            frame.is_playing = false;
        }
        latest
    }
}

#[cfg(test)]
mod engine_tests {
    use super::*;

    #[test]
    fn output_frame_positions_keep_the_same_time_across_rates() {
        assert_eq!(rescale_frame(48_000, 48_000, 96_000), 96_000);
        assert_eq!(rescale_frame(44_100, 44_100, 48_000), 48_000);
        assert_eq!(rescale_frame(0, 48_000, 96_000), 0);
        assert_eq!(rescale_frame(-1, 48_000, 96_000), -1);
    }

    #[test]
    fn removal_retains_track_on_queue_saturation_and_can_be_retried() {
        let (ui_endpoints, mut audio_endpoints) = create_engine_queues(1, 1);
        // No stream or device is opened: this exercises the control protocol
        // deterministically while the audio consumer is deliberately stalled.
        let mut engine = DAWEngine {
            backend: CpalBackend::new().unwrap(),
            active_stream: None,
            recording: None,
            ui_endpoints,
            current_device_index: None,
            output_sample_rate: 48000,
            decoders: HashMap::new(),
            tracks: vec![TrackInfo {
                id: TrackId(1),
                file_path: String::new(),
                info: AudioFileInfo {
                    total_frames: 44100,
                    sample_rate: 44100,
                    channels: 2,
                    duration_secs: 1.0,
                },
                output_frames: 48000,
                start_frame: 0,
                gain: 0.8,
                pan: 0.5,
                muted: false,
                solo: false,
            }],
            master_gain: 0.8,
            bpm: 92.0,
            metronome: false,
            sequence: false,
            preset: 0,
            macros: [0.42, 0.38, 0.55, 0.36, 0.7],
        };
        assert!(engine.play());
        assert!(!engine.remove_track(TrackId(1)));
        assert_eq!(engine.tracks().len(), 1);
        assert!(matches!(
            audio_endpoints.cmd_consumer.pop(),
            Ok(EngineCommand::Play)
        ));
        assert!(engine.remove_track(TrackId(1)));
        assert!(engine.tracks().is_empty());
        assert!(matches!(
            audio_endpoints.cmd_consumer.pop(),
            Ok(EngineCommand::RemoveTrack {
                track_id: TrackId(1)
            })
        ));
        assert!(!engine.remove_track(TrackId(1)));
        assert!(audio_endpoints.cmd_consumer.pop().is_err());
    }
}
