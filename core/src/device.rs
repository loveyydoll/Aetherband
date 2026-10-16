//! Audio hardware device discovery and backend abstractions.
//!
//! Encapsulates OS audio APIs (WASAPI on Windows, CoreAudio on macOS) via `cpal`.

use crate::audio::AudioProcessor;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Device, Host, OutputCallbackInfo, Stream, StreamConfig, SupportedStreamConfig};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use thiserror::Error;

/// Device and audio stream errors.
#[derive(Debug, Error)]
pub enum DeviceError {
    #[error("No audio host available on platform")]
    NoHostAvailable,
    #[error("No default audio output device found")]
    NoDefaultDevice,
    #[error("Audio device with index {0} was not found")]
    DeviceNotFound(usize),
    #[error("Device does not support required audio stream format: {0}")]
    FormatNotSupported(String),
    #[error("Failed to build output audio stream: {0}")]
    StreamBuildError(String),
    #[error("Failed to start audio stream: {0}")]
    StreamPlayError(String),
}

/// Metadata describing an audio output hardware device.
#[derive(Debug, Clone, PartialEq)]
pub struct DeviceInfo {
    pub index: usize,
    pub name: String,
    pub default_sample_rate: u32,
    pub channels: u16,
    pub is_default: bool,
}

/// Common trait for audio I/O backends.
pub trait AudioBackend {
    /// Enumerates all available physical and virtual audio output devices.
    fn enumerate_output_devices(&self) -> Result<Vec<DeviceInfo>, DeviceError>;

    /// Starts an active real-time output stream using the provided `AudioProcessor`.
    fn start_output_stream(
        &mut self,
        device_index: Option<usize>,
        processor: AudioProcessor,
    ) -> Result<ActiveStream, DeviceError>;
}

/// An active hardware audio output stream handle.
///
/// Keeps the underlying audio stream running until explicitly dropped or stopped.
pub struct ActiveStream {
    _stream: Stream,
    is_running: Arc<AtomicBool>,
    device_name: String,
    sample_rate: u32,
    channels: u16,
}

impl ActiveStream {
    /// Returns the name of the active audio device.
    pub fn device_name(&self) -> &str {
        &self.device_name
    }

    /// Returns the active sample rate.
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    /// Returns the active channel count.
    pub fn channels(&self) -> u16 {
        self.channels
    }

    /// Returns true if the hardware stream is actively running.
    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::Relaxed)
    }
}

/// Primary cross-platform audio backend using `cpal`.
pub struct CpalBackend {
    host: Host,
}

impl CpalBackend {
    /// Initializes the default audio host for the current operating system.
    pub fn new() -> Result<Self, DeviceError> {
        let host = cpal::default_host();
        Ok(Self { host })
    }

    fn get_device_by_index(&self, index: usize) -> Result<Device, DeviceError> {
        let mut devices = self
            .host
            .output_devices()
            .map_err(|e| DeviceError::StreamBuildError(e.to_string()))?;
        devices
            .nth(index)
            .ok_or(DeviceError::DeviceNotFound(index))
    }
}

impl AudioBackend for CpalBackend {
    fn enumerate_output_devices(&self) -> Result<Vec<DeviceInfo>, DeviceError> {
        let mut result = Vec::new();
        let default_device_name = self
            .host
            .default_output_device()
            .and_then(|d| d.name().ok());

        let devices = self
            .host
            .output_devices()
            .map_err(|e| DeviceError::StreamBuildError(e.to_string()))?;

        for (idx, device) in devices.enumerate() {
            let name = device.name().unwrap_or_else(|_| format!("Device {}", idx));
            let is_default = default_device_name.as_ref() == Some(&name);

            // Query supported config or fallback to defaults
            let (default_sample_rate, channels) = device
                .default_output_config()
                .map(|cfg| (cfg.sample_rate().0, cfg.channels()))
                .unwrap_or((48000, 2));

            result.push(DeviceInfo {
                index: idx,
                name,
                default_sample_rate,
                channels,
                is_default,
            });
        }

        Ok(result)
    }

    fn start_output_stream(
        &mut self,
        device_index: Option<usize>,
        mut processor: AudioProcessor,
    ) -> Result<ActiveStream, DeviceError> {
        let device = match device_index {
            Some(idx) => self.get_device_by_index(idx)?,
            None => self
                .host
                .default_output_device()
                .ok_or(DeviceError::NoDefaultDevice)?,
        };

        let device_name = device.name().unwrap_or_else(|_| "Unknown Device".into());
        let default_config: SupportedStreamConfig = device
            .default_output_config()
            .map_err(|e| DeviceError::FormatNotSupported(e.to_string()))?;

        let sample_rate = default_config.sample_rate().0;
        let channels = default_config.channels();

        let stream_config: StreamConfig = default_config.into();

        let is_running = Arc::new(AtomicBool::new(true));
        let running_flag = Arc::clone(&is_running);

        let err_callback = move |err: cpal::StreamError| {
            log::error!("Hardware audio stream error: {}", err);
            running_flag.store(false, Ordering::Relaxed);
        };

        let ch_count = channels as usize;
        let stream = device
            .build_output_stream(
                &stream_config,
                move |data: &mut [f32], _: &OutputCallbackInfo| {
                    processor.process_interleaved(data, ch_count);
                },
                err_callback,
                None, // Dynamic buffer latency
            )
            .map_err(|e| DeviceError::StreamBuildError(e.to_string()))?;

        stream
            .play()
            .map_err(|e| DeviceError::StreamPlayError(e.to_string()))?;

        Ok(ActiveStream {
            _stream: stream,
            is_running,
            device_name,
            sample_rate,
            channels,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_enumerate_devices() {
        let backend = CpalBackend::new();
        assert!(backend.is_ok());
        let backend = backend.unwrap();
        let devices = backend.enumerate_output_devices();
        assert!(devices.is_ok());
        let list = devices.unwrap();
        // Machine should have at least one audio output or zero in CI headless
        println!("Discovered {} audio output device(s)", list.len());
        for dev in list {
            println!("  [{}] {} (default: {})", dev.index, dev.name, dev.is_default);
        }
    }
}
