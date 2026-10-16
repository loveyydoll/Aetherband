//! RouletteStudio Audio Core Library
//!
//! Owns the audio processing pipeline, DSP algorithms, audio driver I/O,
//! and lock-free concurrency queues.

pub mod audio;
pub mod device;
pub mod dsp;
pub mod ringbuf;
pub mod transport;

use audio::AudioProcessor;
use device::{ActiveStream, AudioBackend, CpalBackend, DeviceError, DeviceInfo};
use ringbuf::{create_engine_queues, EngineCommand, TelemetryFrame, UIEndpoints};

/// Core engine version.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// The primary high-level engine controller.
///
/// Manages background stream state, device selection, and lock-free UI communication.
pub struct DAWEngine {
    backend: CpalBackend,
    active_stream: Option<ActiveStream>,
    ui_endpoints: UIEndpoints,
    current_device_index: Option<usize>,
}

impl DAWEngine {
    /// Creates a new DAW engine instance and initializes the default audio stream.
    pub fn new() -> Result<Self, DeviceError> {
        let mut backend = CpalBackend::new()?;
        let (ui_endpoints, audio_endpoints) = create_engine_queues(1024, 2048);

        // Pre-allocate audio processor at standard 48kHz (stream will adapt)
        let processor = AudioProcessor::new(48000.0, audio_endpoints);
        let active_stream = backend.start_output_stream(None, processor)?;

        Ok(Self {
            backend,
            active_stream: Some(active_stream),
            ui_endpoints,
            current_device_index: None,
        })
    }

    /// Enumerates all available output devices.
    pub fn enumerate_devices(&self) -> Result<Vec<DeviceInfo>, DeviceError> {
        self.backend.enumerate_output_devices()
    }

    /// Switches the active output device by index.
    pub fn select_device(&mut self, device_index: usize) -> Result<(), DeviceError> {
        // Stop current stream
        self.active_stream = None;

        let (ui_endpoints, audio_endpoints) = create_engine_queues(1024, 2048);
        let processor = AudioProcessor::new(48000.0, audio_endpoints);
        let active_stream = self
            .backend
            .start_output_stream(Some(device_index), processor)?;

        self.ui_endpoints = ui_endpoints;
        self.active_stream = Some(active_stream);
        self.current_device_index = Some(device_index);
        Ok(())
    }

    /// Sends a Play command to the audio thread.
    pub fn play(&mut self) -> bool {
        self.ui_endpoints.cmd_producer.push(EngineCommand::Play).is_ok()
    }

    /// Sends a Pause command to the audio thread.
    pub fn pause(&mut self) -> bool {
        self.ui_endpoints.cmd_producer.push(EngineCommand::Pause).is_ok()
    }

    /// Sends a Stop command to the audio thread (rewinding playhead to 0).
    pub fn stop(&mut self) -> bool {
        self.ui_endpoints.cmd_producer.push(EngineCommand::Stop).is_ok()
    }

    /// Adjusts the master volume with click-free de-zippering over 256 samples.
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
            .push(EngineCommand::SetTestTone {
                enabled,
                frequency_hz,
            })
            .is_ok()
    }

    /// Polls the latest telemetry frame from the audio thread (Peak, RMS, Playhead).
    pub fn poll_telemetry(&mut self) -> Option<TelemetryFrame> {
        let mut latest = None;
        // Drain to get the most recent frame
        while let Ok(frame) = self.ui_endpoints.telemetry_consumer.pop() {
            latest = Some(frame);
        }
        latest
    }

    /// Returns the active audio device name, if any.
    pub fn active_device_name(&self) -> Option<&str> {
        self.active_stream.as_ref().map(|s| s.device_name())
    }
}
