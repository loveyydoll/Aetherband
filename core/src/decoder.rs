//! Background audio file decoder and disk-streaming worker.
//!
//! Decodes audio files on a non-real-time worker thread and feeds
//! pre-decoded stereo blocks into a lock-free ring buffer that the
//! audio thread consumes without ever touching the disk or allocating memory.

use std::fs::File;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use rubato::{FftFixedIn, Resampler};
use symphonia::core::audio::{AudioBufferRef, Signal};
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use thiserror::Error;

use crate::ringbuf::{create_stream_queue, DecodedBlock};
use rtrb::{Consumer, Producer};

/// Errors that can occur during audio file decoding.
#[derive(Debug, Error)]
pub enum DecoderError {
    #[error("File not found: {0}")]
    FileNotFound(String),
    #[error("Unsupported or unrecognised audio format")]
    UnsupportedFormat,
    #[error("No playable audio track found in file")]
    NoAudioTrack,
    #[error("Decode error: {0}")]
    DecodeError(String),
}

/// Decoded metadata about an audio file, returned before streaming starts.
#[derive(Debug, Clone)]
pub struct AudioFileInfo {
    /// Total number of frames (samples per channel) in the file.
    pub total_frames: u64,
    /// Native sample rate of the file.
    pub sample_rate: u32,
    /// Number of channels in the file (we always convert to stereo output).
    pub channels: u32,
    /// Duration in seconds.
    pub duration_secs: f64,
}

/// Probe an audio file and return its metadata without fully decoding it.
pub fn probe_file(path: &Path) -> Result<AudioFileInfo, DecoderError> {
    let file = File::open(path)
        .map_err(|_| DecoderError::FileNotFound(path.display().to_string()))?;

    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|_| DecoderError::UnsupportedFormat)?;

    let format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .ok_or(DecoderError::NoAudioTrack)?;

    let params = &track.codec_params;
    let sample_rate = params.sample_rate.unwrap_or(48000);
    let channels = params.channels.map(|c| c.count() as u32).unwrap_or(2);
    let total_frames = params.n_frames.unwrap_or(0);
    let duration_secs = if sample_rate > 0 {
        total_frames as f64 / sample_rate as f64
    } else {
        0.0
    };

    Ok(AudioFileInfo {
        total_frames,
        sample_rate,
        channels,
        duration_secs,
    })
}

/// The number of pre-decoded stereo frames in each `DecodedBlock`.
pub const DECODE_BLOCK_FRAMES: usize = 8192;

/// Number of pre-decoded blocks held in the ring buffer.
/// At 8192 frames/block @ 48kHz this gives ~1.4 seconds of look-ahead per track.
pub const STREAM_BUFFER_BLOCKS: usize = 8;

/// A handle to a running stream decoder worker thread.
pub struct StreamDecoder {
    /// Consumer side of the disk-stream ring buffer.
    ///
    /// Wrapped in `Option` so it can be moved out via `take_consumer()`
    /// into the `TrackPlayer` before the decoder handle is stored.
    /// After calling `take_consumer()` this field is `None`.
    consumer: Option<Consumer<DecodedBlock>>,
    /// Atomic flag: set to `true` to request the worker to stop.
    stop_flag: Arc<AtomicBool>,
    /// Join handle ensures the worker is not silently detached on removal.
    worker: Option<std::thread::JoinHandle<()>>,
}

impl StreamDecoder {
    /// Spawn a background decode worker for `path`, targeting `output_sample_rate`.
    ///
    /// The worker pre-decodes the entire file into the ring buffer,
    /// converting sample rate if necessary.
    pub fn spawn(path: &Path, output_sample_rate: u32) -> Result<Self, DecoderError> {
        let path = path.to_path_buf();
        let stop_flag = Arc::new(AtomicBool::new(false));
        let stop_clone = Arc::clone(&stop_flag);

        let (producer, consumer) = create_stream_queue(STREAM_BUFFER_BLOCKS);

        // Probe the file for info we'll need in the thread
        let info = probe_file(&path)?;

        let worker = std::thread::Builder::new()
            .name(format!("stream-decoder({})", path.display()))
            .spawn(move || {
                if let Err(e) = decode_worker(path, info, output_sample_rate, producer, stop_clone)
                {
                    log::error!("Stream decoder error: {}", e);
                }
            })
            .map_err(|e| DecoderError::DecodeError(e.to_string()))?;

        Ok(Self {
            consumer: Some(consumer),
            stop_flag,
            worker: Some(worker),
        })
    }

    /// Moves the ring buffer consumer out of this decoder handle.
    ///
    /// Must be called exactly once, before passing the consumer to `TrackPlayer::new`.
    /// Panics if called twice (indicates a programming error — the consumer was
    /// already taken and the decoder is in an invalid state).
    pub fn take_consumer(&mut self) -> Consumer<DecodedBlock> {
        self.consumer
            .take()
            .expect("StreamDecoder: take_consumer() called more than once")
    }

    /// Request the worker thread to stop and wait for it to exit.
    ///
    /// This is a control-thread operation and must never be called from the
    /// real-time audio callback.
    pub fn stop(&mut self) {
        self.stop_flag.store(true, Ordering::Release);
        if let Some(worker) = self.worker.take() {
            if worker.thread().id() != std::thread::current().id() {
                if worker.join().is_err() {
                    log::error!("Stream decoder worker panicked while shutting down");
                }
            }
        }
    }
}

impl Drop for StreamDecoder {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Internal decode loop executed on the background worker thread.
fn decode_worker(
    path: std::path::PathBuf,
    info: AudioFileInfo,
    output_sample_rate: u32,
    mut producer: Producer<DecodedBlock>,
    stop_flag: Arc<AtomicBool>,
) -> Result<(), DecoderError> {
    // ── Open file and set up Symphonia ──────────────────────────────────────
    let file = File::open(&path)
        .map_err(|_| DecoderError::FileNotFound(path.display().to_string()))?;

    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|_| DecoderError::UnsupportedFormat)?;

    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .ok_or(DecoderError::NoAudioTrack)?
        .clone();

    let track_id = track.id;
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| DecoderError::DecodeError(e.to_string()))?;

    let source_rate = info.sample_rate;
    let source_channels = info.channels as usize;
    let needs_resample = source_rate != output_sample_rate;

    // ── Set up Rubato resampler if sample rates differ ───────────────────────
    let mut resampler: Option<FftFixedIn<f32>> = if needs_resample {
        Some(
            FftFixedIn::<f32>::new(
                source_rate as usize,
                output_sample_rate as usize,
                DECODE_BLOCK_FRAMES,
                2, // sub-chunks
                2, // always output stereo
            )
            .map_err(|e| DecoderError::DecodeError(e.to_string()))?,
        )
    } else {
        None
    };

    // ── Decode loop ──────────────────────────────────────────────────────────
    let mut playhead: i64 = 0;
    let mut pending_l: Vec<f32> = Vec::with_capacity(DECODE_BLOCK_FRAMES);
    let mut pending_r: Vec<f32> = Vec::with_capacity(DECODE_BLOCK_FRAMES);

    loop {
        if stop_flag.load(Ordering::Relaxed) {
            break;
        }

        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(symphonia::core::errors::Error::IoError(_)) => break,
            Err(symphonia::core::errors::Error::ResetRequired) => {
                decoder.reset();
                continue;
            }
            Err(e) => return Err(DecoderError::DecodeError(e.to_string())),
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(buf) => buf,
            Err(symphonia::core::errors::Error::DecodeError(_)) => continue,
            Err(e) => return Err(DecoderError::DecodeError(e.to_string())),
        };

        // Convert the Symphonia AudioBuffer to interleaved f32 vectors
        let _frames = decoded.frames();

        match decoded {
            AudioBufferRef::F32(ref buf) => {
                let ch_l = buf.chan(0);
                let ch_r = if source_channels > 1 { buf.chan(1) } else { buf.chan(0) };
                pending_l.extend_from_slice(ch_l);
                pending_r.extend_from_slice(ch_r);
            }
            AudioBufferRef::S32(ref buf) => {
                let scale = 1.0 / i32::MAX as f32;
                for &s in buf.chan(0) {
                    pending_l.push(s as f32 * scale);
                }
                let src_r = if source_channels > 1 { buf.chan(1) } else { buf.chan(0) };
                for &s in src_r {
                    pending_r.push(s as f32 * scale);
                }
            }
            AudioBufferRef::S16(ref buf) => {
                let scale = 1.0 / i16::MAX as f32;
                for &s in buf.chan(0) {
                    pending_l.push(s as f32 * scale);
                }
                let src_r = if source_channels > 1 { buf.chan(1) } else { buf.chan(0) };
                for &s in src_r {
                    pending_r.push(s as f32 * scale);
                }
            }
            _ => {
                // Convert any remaining format generically via Symphonia's built-in converter
                let mut conv_buf = decoded.make_equivalent::<f32>();
                decoded.convert(&mut conv_buf);
                pending_l.extend_from_slice(conv_buf.chan(0));
                let src_r = if source_channels > 1 { conv_buf.chan(1) } else { conv_buf.chan(0) };
                pending_r.extend_from_slice(src_r);
            }
        }

        // When we have accumulated enough samples, flush to the ring buffer
        while pending_l.len() >= DECODE_BLOCK_FRAMES {
            let l_chunk: Vec<f32> = pending_l.drain(..DECODE_BLOCK_FRAMES).collect();
            let r_chunk: Vec<f32> = pending_r.drain(..DECODE_BLOCK_FRAMES).collect();

            let (out_l, out_r) = if let Some(ref mut rs) = resampler {
                let resampled = rs
                    .process(&[&l_chunk, &r_chunk], None)
                    .map_err(|e| DecoderError::DecodeError(e.to_string()))?;
                (resampled[0].clone(), resampled[1].clone())
            } else {
                (l_chunk, r_chunk)
            };

            let n = out_l.len();
            let mut block = DecodedBlock::silent(n);
            block.start_frame = playhead;
            block.valid_frames = n;
            for i in 0..n {
                block.samples[i * 2] = out_l[i];
                block.samples[i * 2 + 1] = out_r[i];
            }
            playhead += n as i64;

            // Back-pressure: spin-wait if consumer is slow
            loop {
                if stop_flag.load(Ordering::Relaxed) {
                    return Ok(());
                }
                match producer.push(block.clone()) {
                    Ok(_) => break,
                    Err(_) => std::thread::sleep(std::time::Duration::from_millis(1)),
                }
            }
        }
    }

    // Flush any remaining samples as a final block
    if !pending_l.is_empty() {
        let n = pending_l.len();
        let (out_l, out_r) = if let Some(ref mut rs) = resampler {
            let padded_l = {
                let mut v = pending_l.clone();
                v.resize(DECODE_BLOCK_FRAMES, 0.0);
                v
            };
            let padded_r = {
                let mut v = pending_r.clone();
                v.resize(DECODE_BLOCK_FRAMES, 0.0);
                v
            };
            let resampled = rs
                .process(&[&padded_l, &padded_r], None)
                .map_err(|e| DecoderError::DecodeError(e.to_string()))?;
            (resampled[0][..n].to_vec(), resampled[1][..n].to_vec())
        } else {
            (pending_l, pending_r)
        };

        let n = out_l.len();
        let mut block = DecodedBlock::silent(n);
        block.start_frame = playhead;
        block.valid_frames = n;
        block.is_last = true;
        for i in 0..n {
            block.samples[i * 2] = out_l[i];
            block.samples[i * 2 + 1] = out_r[i];
        }

        loop {
            if stop_flag.load(Ordering::Relaxed) {
                return Ok(());
            }
            match producer.push(block.clone()) {
                Ok(_) => break,
                Err(_) => std::thread::sleep(std::time::Duration::from_millis(1)),
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decode_block_silent_layout() {
        let block = DecodedBlock::silent(512);
        // Interleaved layout: 512 frames × 2 channels = 1024 samples
        assert_eq!(block.samples.len(), 1024);
        assert_eq!(block.valid_frames, 512);
        assert!(block.samples.iter().all(|&s| s == 0.0));
    }
}
