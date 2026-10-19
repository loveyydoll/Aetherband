//! Audio hardware device discovery and backend abstractions.
//!
//! Encapsulates OS audio APIs (WASAPI on Windows, CoreAudio on macOS) via `cpal`.

use crate::audio::AudioProcessor;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{
    Device, Host, InputCallbackInfo, OutputCallbackInfo, Stream, StreamConfig,
    SupportedStreamConfig,
};
use rtrb::RingBuffer;
use std::fs::{File, OpenOptions};
use std::io::{self, Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;
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
    #[error("Failed to start audio recording: {0}")]
    RecordingError(String),
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

/// Summary returned after the input writer has flushed and finalized its WAV.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RecordingStats {
    pub sample_rate: u32,
    pub frames_written: u64,
    pub frames_dropped: u64,
}

/// Input stream and non-realtime WAV writer owned by the engine control thread.
pub struct ActiveRecording {
    stream: Option<Stream>,
    running: Arc<AtomicBool>,
    failed: Arc<AtomicBool>,
    dropped_frames: Arc<AtomicU64>,
    writer: Option<JoinHandle<io::Result<u64>>>,
    sample_rate: u32,
    path: std::path::PathBuf,
}

impl ActiveRecording {
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    pub fn finish(mut self) -> Result<RecordingStats, String> {
        self.running.store(false, Ordering::Release);
        self.stream.take();
        let frames_written = self
            .writer
            .take()
            .ok_or_else(|| "recording writer was already stopped".to_owned())?
            .join()
            .map_err(|_| "recording writer thread panicked".to_owned())?
            .map_err(|error| error.to_string())?;
        if frames_written == 0 {
            let _ = std::fs::remove_file(&self.path);
            return Err("no audio frames were captured".into());
        }
        if self.failed.load(Ordering::Acquire) {
            return Err("Windows audio input stream stopped unexpectedly".into());
        }
        Ok(RecordingStats {
            sample_rate: self.sample_rate,
            frames_written,
            frames_dropped: self.dropped_frames.load(Ordering::Relaxed),
        })
    }
}

impl Drop for ActiveRecording {
    fn drop(&mut self) {
        self.running.store(false, Ordering::Release);
        self.stream.take();
        if let Some(writer) = self.writer.take() {
            let _ = writer.join();
        }
    }
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
        devices.nth(index).ok_or(DeviceError::DeviceNotFound(index))
    }

    /// Queries the sample rate that will be used by the selected output.
    ///
    /// Call this before constructing the processor so its oscillator and any
    /// sample-rate-dependent DSP are initialized for the actual device rate.
    pub fn output_sample_rate(&self, device_index: Option<usize>) -> Result<u32, DeviceError> {
        let device = match device_index {
            Some(index) => self.get_device_by_index(index)?,
            None => self
                .host
                .default_output_device()
                .ok_or(DeviceError::NoDefaultDevice)?,
        };
        device
            .default_output_config()
            .map(|config| config.sample_rate())
            .map_err(|e| DeviceError::FormatNotSupported(e.to_string()))
    }

    /// Starts recording the default Windows input device to a stereo PCM24 WAV.
    /// The input callback only converts and pushes samples into a bounded ring;
    /// the writer thread performs all filesystem work.
    pub fn start_recording(&self, path: &Path) -> Result<ActiveRecording, DeviceError> {
        let device = self
            .host
            .default_input_device()
            .ok_or_else(|| DeviceError::RecordingError("no default input device".into()))?;
        let config = device
            .default_input_config()
            .map_err(|error| DeviceError::RecordingError(error.to_string()))?;
        let sample_rate = config.sample_rate();
        let channels = config.channels() as usize;
        if channels == 0 {
            return Err(DeviceError::RecordingError("input has no channels".into()));
        }
        let sample_format = config.sample_format();
        let stream_config: StreamConfig = config.into();
        let file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .map_err(|error| DeviceError::RecordingError(error.to_string()))?;
        let (producer, consumer) = RingBuffer::<f32>::new((sample_rate as usize * 2).max(4096));
        let running = Arc::new(AtomicBool::new(true));
        let failed = Arc::new(AtomicBool::new(false));
        let dropped_frames = Arc::new(AtomicU64::new(0));
        let writer_running = Arc::clone(&running);
        let writer = match thread::Builder::new()
            .name("aetherband-wav-recorder".into())
            .spawn(move || write_recording(file, consumer, writer_running, sample_rate))
        {
            Ok(writer) => writer,
            Err(error) => {
                let _ = std::fs::remove_file(path);
                return Err(DeviceError::RecordingError(error.to_string()));
            }
        };
        let stream_running = Arc::clone(&running);
        let stream_failed = Arc::clone(&failed);
        let stream_dropped = Arc::clone(&dropped_frames);
        let stream = match sample_format {
            cpal::SampleFormat::I8 => build_input::<i8>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::I24 => build_input::<cpal::I24>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::I64 => build_input::<i64>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::U8 => build_input::<u8>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::U24 => build_input::<cpal::U24>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::U32 => build_input::<u32>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::U64 => build_input::<u64>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::F32 => build_input::<f32>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::F64 => build_input::<f64>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::I16 => build_input::<i16>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::I32 => build_input::<i32>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            cpal::SampleFormat::U16 => build_input::<u16>(
                &device,
                &stream_config,
                channels,
                producer,
                stream_running,
                stream_failed.clone(),
                stream_dropped.clone(),
            ),
            format => Err(cpal::Error::with_message(
                cpal::ErrorKind::UnsupportedConfig,
                format!("unsupported input format {format:?}"),
            )),
        };
        let stream = match stream {
            Ok(stream) => stream,
            Err(error) => {
                running.store(false, Ordering::Release);
                let _ = writer.join();
                let _ = std::fs::remove_file(path);
                return Err(DeviceError::RecordingError(error.to_string()));
            }
        };
        if let Err(error) = stream.play() {
            running.store(false, Ordering::Release);
            drop(stream);
            let _ = writer.join();
            let _ = std::fs::remove_file(path);
            return Err(DeviceError::RecordingError(error.to_string()));
        }
        Ok(ActiveRecording {
            stream: Some(stream),
            running,
            failed,
            dropped_frames,
            writer: Some(writer),
            sample_rate,
            path: path.to_owned(),
        })
    }
}

fn build_input<T: cpal::SizedSample + cpal::Sample>(
    device: &Device,
    config: &StreamConfig,
    channels: usize,
    mut producer: rtrb::Producer<f32>,
    running: Arc<AtomicBool>,
    failed: Arc<AtomicBool>,
    dropped: Arc<AtomicU64>,
) -> Result<Stream, cpal::Error>
where
    f32: cpal::FromSample<T>,
{
    let callback_running = Arc::clone(&running);
    device.build_input_stream(
        *config,
        move |data: &[T], _: &InputCallbackInfo| {
            for frame in data.chunks_exact(channels) {
                if !callback_running.load(Ordering::Relaxed) {
                    break;
                }
                if producer.slots() < 2 {
                    dropped.fetch_add(1, Ordering::Relaxed);
                    continue;
                }
                let left: f32 = frame[0].to_sample();
                let right: f32 = frame.get(1).copied().unwrap_or(frame[0]).to_sample();
                // The capacity check above reserves both samples because this
                // is the ring's only producer and the consumer only frees slots.
                if producer.push(left).is_err() || producer.push(right).is_err() {
                    dropped.fetch_add(1, Ordering::Relaxed);
                }
            }
        },
        move |_| {
            failed.store(true, Ordering::Release);
            running.store(false, Ordering::Release);
        },
        None,
    )
}

fn write_recording(
    mut file: File,
    mut consumer: rtrb::Consumer<f32>,
    running: Arc<AtomicBool>,
    sample_rate: u32,
) -> io::Result<u64> {
    file.write_all(&wav_header(sample_rate, 0))?;
    let mut samples = [0.0_f32; 4096];
    let mut bytes = [0_u8; 4096 * 3];
    let mut total_samples = 0_u64;
    loop {
        let mut count = 0;
        while count < samples.len() {
            match consumer.pop() {
                Ok(sample) => {
                    samples[count] = sample;
                    count += 1;
                }
                Err(_) => break,
            }
        }
        if count == 0 {
            if !running.load(Ordering::Acquire) {
                break;
            }
            thread::sleep(Duration::from_millis(2));
            continue;
        }
        let max_samples = ((u32::MAX as u64 - 36) / 3) as usize;
        let writable = count.min(max_samples.saturating_sub(total_samples as usize));
        for index in 0..writable {
            const PCM24_MAX: f32 = 8_388_607.0;
            let pcm = (samples[index].clamp(-1.0, 1.0) * PCM24_MAX).round() as i32;
            bytes[index * 3..index * 3 + 3].copy_from_slice(&pcm.to_le_bytes()[..3]);
        }
        file.write_all(&bytes[..writable * 3])?;
        total_samples += writable as u64;
        if writable < count {
            running.store(false, Ordering::Release);
            break;
        }
    }
    file.seek(SeekFrom::Start(0))?;
    file.write_all(&wav_header(sample_rate, total_samples as u32 * 3))?;
    file.sync_all()?;
    Ok(total_samples / 2)
}

fn wav_header(sample_rate: u32, data_bytes: u32) -> [u8; 44] {
    let mut header = [0_u8; 44];
    header[0..4].copy_from_slice(b"RIFF");
    header[4..8].copy_from_slice(&(36_u32.saturating_add(data_bytes)).to_le_bytes());
    header[8..16].copy_from_slice(b"WAVEfmt ");
    header[16..20].copy_from_slice(&16_u32.to_le_bytes());
    header[20..22].copy_from_slice(&1_u16.to_le_bytes());
    header[22..24].copy_from_slice(&2_u16.to_le_bytes());
    header[24..28].copy_from_slice(&sample_rate.to_le_bytes());
    header[28..32].copy_from_slice(&sample_rate.saturating_mul(6).to_le_bytes());
    header[32..34].copy_from_slice(&6_u16.to_le_bytes());
    header[34..36].copy_from_slice(&24_u16.to_le_bytes());
    header[36..40].copy_from_slice(b"data");
    header[40..44].copy_from_slice(&data_bytes.to_le_bytes());
    header
}

impl AudioBackend for CpalBackend {
    fn enumerate_output_devices(&self) -> Result<Vec<DeviceInfo>, DeviceError> {
        let mut result = Vec::new();
        let default_device_name = self.host.default_output_device().and_then(|d| {
            d.description()
                .ok()
                .map(|description| description.name().to_owned())
        });

        let devices = self
            .host
            .output_devices()
            .map_err(|e| DeviceError::StreamBuildError(e.to_string()))?;

        for (idx, device) in devices.enumerate() {
            let name = device
                .description()
                .map(|description| description.name().to_owned())
                .unwrap_or_else(|_| format!("Device {}", idx));
            let is_default = default_device_name.as_ref() == Some(&name);

            // Query supported config or fallback to defaults
            let (default_sample_rate, channels) = device
                .default_output_config()
                .map(|cfg| (cfg.sample_rate(), cfg.channels()))
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
        processor: AudioProcessor,
    ) -> Result<ActiveStream, DeviceError> {
        let device = match device_index {
            Some(idx) => self.get_device_by_index(idx)?,
            None => self
                .host
                .default_output_device()
                .ok_or(DeviceError::NoDefaultDevice)?,
        };

        let device_name = device
            .description()
            .map(|description| description.name().to_owned())
            .unwrap_or_else(|_| "Unknown Device".into());
        let default_config: SupportedStreamConfig = device
            .default_output_config()
            .map_err(|e| DeviceError::FormatNotSupported(e.to_string()))?;

        let sample_rate = default_config.sample_rate();
        let channels = default_config.channels();

        let sample_format = default_config.sample_format();
        let stream_config: StreamConfig = default_config.into();

        let is_running = Arc::new(AtomicBool::new(true));
        let ch_count = channels as usize;
        let stream = match sample_format {
            cpal::SampleFormat::F32 => {
                build_stream::<f32>(&device, &stream_config, processor, ch_count, &is_running)
            }
            cpal::SampleFormat::F64 => {
                build_stream::<f64>(&device, &stream_config, processor, ch_count, &is_running)
            }
            cpal::SampleFormat::I16 => {
                build_stream::<i16>(&device, &stream_config, processor, ch_count, &is_running)
            }
            cpal::SampleFormat::I32 => {
                build_stream::<i32>(&device, &stream_config, processor, ch_count, &is_running)
            }
            cpal::SampleFormat::U16 => {
                build_stream::<u16>(&device, &stream_config, processor, ch_count, &is_running)
            }
            format => return Err(DeviceError::FormatNotSupported(format!("{format:?}"))),
        }
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

fn build_stream<T: cpal::SizedSample + cpal::FromSample<f32>>(
    device: &Device,
    config: &StreamConfig,
    mut processor: AudioProcessor,
    channels: usize,
    running: &Arc<AtomicBool>,
) -> Result<Stream, cpal::Error> {
    let running = Arc::clone(running);
    device.build_output_stream(
        *config,
        move |data: &mut [T], _: &OutputCallbackInfo| processor.process_samples(data, channels),
        move |_| {
            running.store(false, Ordering::Relaxed);
        },
        None,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;

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
            println!(
                "  [{}] {} (default: {})",
                dev.index, dev.name, dev.is_default
            );
        }
    }

    #[test]
    fn recorder_writes_stereo_pcm24_and_finalizes_wav_header() {
        let path = std::env::temp_dir().join(format!(
            "aetherband-recorder-{}.wav",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .unwrap();
        let (mut producer, consumer) = RingBuffer::<f32>::new(8);
        for sample in [0.5, -0.5, 0.0, 1.0] {
            producer.push(sample).unwrap();
        }
        let running = Arc::new(AtomicBool::new(false));
        assert_eq!(write_recording(file, consumer, running, 48_000).unwrap(), 2);

        let mut recorded = Vec::new();
        File::open(&path)
            .unwrap()
            .read_to_end(&mut recorded)
            .unwrap();
        assert_eq!(&recorded[0..4], b"RIFF");
        assert_eq!(&recorded[8..12], b"WAVE");
        assert_eq!(
            u32::from_le_bytes(recorded[28..32].try_into().unwrap()),
            288_000
        );
        assert_eq!(u16::from_le_bytes(recorded[32..34].try_into().unwrap()), 6);
        assert_eq!(u16::from_le_bytes(recorded[34..36].try_into().unwrap()), 24);
        assert_eq!(u32::from_le_bytes(recorded[40..44].try_into().unwrap()), 12);
        assert_eq!(decode_pcm24(&recorded[44..47]), 4_194_304);
        assert_eq!(decode_pcm24(&recorded[47..50]), -4_194_304);
        std::fs::remove_file(path).unwrap();
    }

    fn decode_pcm24(bytes: &[u8]) -> i32 {
        let sign = if bytes[2] & 0x80 == 0 { 0 } else { 0xff };
        i32::from_le_bytes([bytes[0], bytes[1], bytes[2], sign])
    }
}
