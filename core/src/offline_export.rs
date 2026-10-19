//! Offline stereo PCM export. All decoding and file I/O runs on the engine
//! control worker; this module is never called by the device callback.
use crate::decoder::StreamDecoder;
use crate::hypnosynth::HypnoSynth;
use crate::ringbuf::DecodedBlock;
use rtrb::Consumer;
use std::fs::{self, File};
use std::io::{Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use thiserror::Error;

const OUTPUT_BLOCK_FRAMES: usize = 1024;
const MAX_WAV_DATA_BYTES: u64 = u32::MAX as u64 - 36;
const DECODER_WAIT_LIMIT: Duration = Duration::from_secs(30);

#[derive(Debug, Error)]
pub enum ExportError {
    #[error("Cannot export an empty audio session")]
    EmptySession,
    #[error("The session is too long for a standard stereo WAV file")]
    TooLong,
    #[error("Invalid export settings")]
    InvalidSettings,
    #[error("Mixdown export needs clips with known duration or the generated phrase enabled")]
    UnknownDuration,
    #[error("Choose an export destination that is different from every source recording")]
    OutputMatchesInput,
    #[error("The export destination must be a file path")]
    InvalidDestination,
    #[error("Audio decode failed: {0}")]
    Decode(String),
    #[error("Audio decoder did not provide data in time")]
    DecoderTimeout,
    #[error("Could not write the mixdown: {0}")]
    Io(#[from] std::io::Error),
}

#[derive(Debug, Clone)]
pub struct ExportTrack {
    pub path: PathBuf,
    pub start_frame: u64,
    pub total_frames: u64,
    pub gain: f32,
    pub pan: f32,
    pub muted: bool,
    pub solo: bool,
}

#[derive(Debug, Clone, Copy)]
pub struct ExportSettings {
    pub sample_rate: u32,
    pub master: f32,
    pub bpm: f32,
    pub metronome: bool,
    pub sequence: bool,
    pub preset: u8,
    pub macros: [f32; 5],
}

struct TrackReader {
    consumer: Consumer<DecodedBlock>,
    block: Option<DecodedBlock>,
    cursor: usize,
    expected_frames: Option<u64>,
    frames_read: u64,
    finished: bool,
}

impl TrackReader {
    fn new(decoder: &mut StreamDecoder, expected_frames: u64) -> Self {
        Self {
            consumer: decoder.take_consumer(),
            block: None,
            cursor: 0,
            expected_frames: (expected_frames > 0).then_some(expected_frames),
            frames_read: 0,
            finished: false,
        }
    }

    fn next_frame(&mut self) -> Result<Option<[f32; 2]>, ExportError> {
        if self.finished {
            return Ok(None);
        }
        if self
            .expected_frames
            .is_some_and(|limit| self.frames_read >= limit)
        {
            self.finished = true;
            return Ok(None);
        }

        let wait_started = Instant::now();
        loop {
            if let Some(block) = self.block.as_ref() {
                let valid = block.valid_frames.min(block.samples.len() / 2);
                if self.cursor < valid {
                    let index = self.cursor * 2;
                    self.cursor += 1;
                    self.frames_read += 1;
                    let frame = [block.samples[index], block.samples[index + 1]];
                    if block.is_last && self.cursor >= valid {
                        self.finished = true;
                    }
                    return Ok(Some(frame));
                }
                if block.is_last {
                    self.finished = true;
                    return Ok(None);
                }
                self.block = None;
                self.cursor = 0;
            }

            match self.consumer.pop() {
                Ok(block) => self.block = Some(block),
                Err(_) if wait_started.elapsed() < DECODER_WAIT_LIMIT => {
                    thread::sleep(Duration::from_millis(1));
                }
                Err(_) => return Err(ExportError::DecoderTimeout),
            }
        }
    }
}

/// Render the session to interleaved signed 16-bit PCM WAV, using fresh
/// decoders so export does not seek, pause, or otherwise change live playback.
pub fn render_stereo_wav(
    path: &Path,
    tracks: &[ExportTrack],
    settings: ExportSettings,
) -> Result<(), ExportError> {
    if tracks.is_empty() && !settings.sequence {
        return Err(ExportError::EmptySession);
    }
    if !(8_000..=192_000).contains(&settings.sample_rate)
        || !settings.master.is_finite()
        || !(0.0..=2.0).contains(&settings.master)
        || !settings.bpm.is_finite()
        || !(30.0..=300.0).contains(&settings.bpm)
        || settings.preset > 2
        || settings
            .macros
            .iter()
            .any(|v| !v.is_finite() || !(0.0..=1.0).contains(v))
        || tracks.iter().any(|track| {
            !track.gain.is_finite()
                || !(0.0..=2.0).contains(&track.gain)
                || !track.pan.is_finite()
                || !(0.0..=1.0).contains(&track.pan)
        })
    {
        return Err(ExportError::InvalidSettings);
    }
    if tracks.iter().any(|track| track.total_frames == 0) {
        return Err(ExportError::UnknownDuration);
    }
    if path.exists() && !path.is_file() {
        return Err(ExportError::InvalidDestination);
    }
    let destination = if path.exists() {
        Some(path.canonicalize()?)
    } else {
        None
    };
    if tracks.iter().any(|track| {
        destination.as_ref().is_some_and(|destination| {
            track
                .path
                .canonicalize()
                .is_ok_and(|source| source == *destination)
        })
    }) {
        return Err(ExportError::OutputMatchesInput);
    }

    let mut readers = Vec::with_capacity(tracks.len());
    let mut decoders = Vec::with_capacity(tracks.len());
    for track in tracks {
        let mut decoder = StreamDecoder::spawn(&track.path, settings.sample_rate)
            .map_err(|error| ExportError::Decode(error.to_string()))?;
        readers.push(TrackReader::new(&mut decoder, track.total_frames));
        decoders.push(decoder);
    }

    let audio_end_frame = tracks
        .iter()
        .filter(|track| track.total_frames > 0)
        .map(|track| track.start_frame.saturating_add(track.total_frames))
        .max()
        .unwrap_or(0);
    // A sequence-only mix renders eight bars, then includes a short release tail.
    let sequence_frames = if settings.sequence && audio_end_frame == 0 {
        (settings.sample_rate as f64 * 60.0 / settings.bpm as f64 * 32.0) as u64
    } else {
        0
    };
    let end_frame = audio_end_frame.max(sequence_frames);
    if end_frame == 0 {
        return Err(ExportError::InvalidSettings);
    }
    let tail_frames = if settings.sequence {
        settings.sample_rate as u64 * 2
    } else {
        0
    };
    if end_frame.saturating_add(tail_frames) > MAX_WAV_DATA_BYTES / 4 {
        return Err(ExportError::TooLong);
    }

    let temporary = temporary_path(path);
    let result = render_to_temporary(
        &temporary,
        tracks,
        &mut readers,
        settings,
        end_frame,
        end_frame.saturating_add(tail_frames),
    );
    // Ensure decoder workers are cancelled and joined before returning.
    drop(readers);
    drop(decoders);
    if let Err(error) = result {
        let _ = fs::remove_file(&temporary);
        return Err(error);
    }
    if let Err(error) = replace_destination(&temporary, path) {
        let _ = fs::remove_file(&temporary);
        return Err(error);
    }
    Ok(())
}

fn render_to_temporary(
    path: &Path,
    tracks: &[ExportTrack],
    readers: &mut [TrackReader],
    settings: ExportSettings,
    musical_end_frame: u64,
    known_end_frame: u64,
) -> Result<(), ExportError> {
    let mut file = File::create(path)?;
    file.write_all(&[0; 44])?;
    let mut synth = HypnoSynth::new(settings.sample_rate as f32);
    synth.preset(settings.preset);
    for (index, value) in settings.macros.iter().enumerate() {
        synth.parameter(index as u8, *value);
    }
    let solo_active = tracks.iter().any(|track| track.solo);
    let mut beat_phase = 0.0_f64;
    let mut sequence_note = None;
    let mut click_remaining = 0_u32;
    let mut written_frames = 0_u64;
    let mut bytes = Vec::with_capacity(OUTPUT_BLOCK_FRAMES * 4);
    let mut left = [0.0_f32; OUTPUT_BLOCK_FRAMES];
    let mut right = [0.0_f32; OUTPUT_BLOCK_FRAMES];
    let mut block_start = 0_u64;

    while block_start < known_end_frame {
        let frames = OUTPUT_BLOCK_FRAMES.min((known_end_frame - block_start) as usize);
        left[..frames].fill(0.0);
        right[..frames].fill(0.0);
        for (track_index, track) in tracks.iter().enumerate() {
            if track.muted || (solo_active && !track.solo) {
                // Muted tracks do not need to advance here; the independent
                // decoder is cancelled when the render completes.
                continue;
            }
            let pan_angle = track.pan * std::f32::consts::FRAC_PI_2;
            let pan_left = pan_angle.cos() * track.gain;
            let pan_right = pan_angle.sin() * track.gain;
            for frame in 0..frames {
                let timeline_frame = block_start + frame as u64;
                if timeline_frame < track.start_frame {
                    continue;
                }
                match readers[track_index].next_frame()? {
                    Some(sample) => {
                        left[frame] += sample[0] * pan_left;
                        right[frame] += sample[1] * pan_right;
                    }
                    None => break,
                }
            }
        }

        for frame in 0..frames {
            let timeline_frame = block_start + frame as u64;
            let previous_beat = beat_phase;
            beat_phase += settings.bpm as f64 / (60.0 * settings.sample_rate as f64);
            if settings.sequence
                && timeline_frame < musical_end_frame
                && (previous_beat == 0.0
                    || (previous_beat * 2.0).floor() != (beat_phase * 2.0).floor())
            {
                const NOTES: [u8; 16] = [
                    50, 57, 60, 57, 53, 60, 65, 60, 48, 55, 60, 62, 45, 52, 57, 64,
                ];
                if let Some(note) = sequence_note.take() {
                    synth.note_off(note);
                }
                let note = NOTES[(beat_phase * 2.0) as usize % NOTES.len()];
                synth.note_on(note, 0.72);
                sequence_note = Some(note);
            }
            if settings.metronome && timeline_frame < musical_end_frame {
                if previous_beat == 0.0 || previous_beat.floor() != beat_phase.floor() {
                    click_remaining = (settings.sample_rate as f32 * 0.025) as u32;
                }
                if click_remaining > 0 {
                    let time = click_remaining as f32 / settings.sample_rate as f32;
                    let click = (time * 1500.0 * std::f32::consts::TAU).sin() * time * 3.0;
                    left[frame] += click;
                    right[frame] += click;
                    click_remaining -= 1;
                }
            }
            let synth_frame = synth.next_frame();
            left[frame] = (left[frame] + synth_frame[0]) * settings.master;
            right[frame] = (right[frame] + synth_frame[1]) * settings.master;
            let l = (left[frame].clamp(-1.0, 1.0) * i16::MAX as f32).round() as i16;
            let r = (right[frame].clamp(-1.0, 1.0) * i16::MAX as f32).round() as i16;
            bytes.extend_from_slice(&l.to_le_bytes());
            bytes.extend_from_slice(&r.to_le_bytes());
        }
        if bytes.len() as u64 > MAX_WAV_DATA_BYTES {
            return Err(ExportError::TooLong);
        }
        file.write_all(&bytes)?;
        written_frames += frames as u64;
        bytes.clear();
        block_start += frames as u64;
    }

    let data_bytes = written_frames.saturating_mul(4);
    file.seek(SeekFrom::Start(0))?;
    write_wav_header(&mut file, settings.sample_rate, data_bytes as u32)?;
    file.sync_all()?;
    Ok(())
}

fn write_wav_header(
    file: &mut File,
    sample_rate: u32,
    data_bytes: u32,
) -> Result<(), std::io::Error> {
    file.write_all(b"RIFF")?;
    file.write_all(&(36_u32.saturating_add(data_bytes)).to_le_bytes())?;
    file.write_all(b"WAVEfmt ")?;
    file.write_all(&16_u32.to_le_bytes())?;
    file.write_all(&1_u16.to_le_bytes())?;
    file.write_all(&2_u16.to_le_bytes())?;
    file.write_all(&sample_rate.to_le_bytes())?;
    file.write_all(&sample_rate.saturating_mul(4).to_le_bytes())?;
    file.write_all(&4_u16.to_le_bytes())?;
    file.write_all(&16_u16.to_le_bytes())?;
    file.write_all(b"data")?;
    file.write_all(&data_bytes.to_le_bytes())?;
    Ok(())
}

fn temporary_path(path: &Path) -> PathBuf {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_nanos());
    let mut name = path.as_os_str().to_os_string();
    name.push(format!(".tmp.{stamp}"));
    PathBuf::from(name)
}

fn replace_destination(temporary: &Path, destination: &Path) -> Result<(), ExportError> {
    if !destination.exists() {
        fs::rename(temporary, destination)?;
        return Ok(());
    }
    let backup = temporary_path(destination);
    fs::rename(destination, &backup)?;
    match fs::rename(temporary, destination) {
        Ok(()) => {
            let _ = fs::remove_file(backup);
            Ok(())
        }
        Err(error) => {
            let _ = fs::rename(backup, destination);
            Err(ExportError::Io(error))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_path(label: &str) -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |duration| duration.as_nanos());
        let directory = std::env::current_dir()
            .unwrap()
            .join("target")
            .join("aetherband-test-files");
        fs::create_dir_all(&directory).unwrap();
        directory.join(format!("aetherband-export-{label}-{stamp}.wav"))
    }

    fn write_source(path: &Path) {
        let frames = 2048_u32;
        let mut file = File::create(path).unwrap();
        write_wav_header(&mut file, 48_000, frames * 4).unwrap();
        for index in 0..frames {
            let sample =
                ((index as f32 * 440.0 * std::f32::consts::TAU / 48_000.0).sin() * 12_000.0) as i16;
            file.write_all(&sample.to_le_bytes()).unwrap();
            file.write_all(&sample.to_le_bytes()).unwrap();
        }
    }

    #[test]
    fn exports_stereo_pcm_with_mixed_audio_and_valid_lengths() {
        let input = temp_path("input");
        let output = temp_path("output");
        write_source(&input);
        let settings = ExportSettings {
            sample_rate: 48_000,
            master: 0.8,
            bpm: 92.0,
            metronome: false,
            sequence: false,
            preset: 0,
            macros: [0.42, 0.38, 0.55, 0.36, 0.7],
        };
        render_stereo_wav(
            &output,
            &[ExportTrack {
                path: input.clone(),
                start_frame: 0,
                total_frames: 2048,
                gain: 0.8,
                pan: 0.5,
                muted: false,
                solo: false,
            }],
            settings,
        )
        .unwrap_or_else(|error| panic!("render failed for {}: {error:?}", output.display()));

        let mut file = File::open(&output).unwrap();
        let mut header = [0_u8; 44];
        file.read_exact(&mut header).unwrap();
        assert_eq!(&header[0..4], b"RIFF");
        assert_eq!(&header[8..16], b"WAVEfmt ");
        assert_eq!(u16::from_le_bytes([header[22], header[23]]), 2);
        assert_eq!(
            u32::from_le_bytes(header[24..28].try_into().unwrap()),
            48_000
        );
        assert_eq!(u16::from_le_bytes([header[34], header[35]]), 16);
        assert_eq!(u32::from_le_bytes(header[40..44].try_into().unwrap()), 8192);
        let mut data = Vec::new();
        file.read_to_end(&mut data).unwrap();
        assert_eq!(data.len(), 8192);
        assert!(data.iter().any(|sample| *sample != 0));
        let _ = fs::remove_file(input);
        let _ = fs::remove_file(output);
    }

    #[test]
    fn sequence_only_session_exports_audible_stereo_phrase() {
        let output = temp_path("sequence-only");
        let settings = ExportSettings {
            sample_rate: 8_000,
            master: 0.8,
            bpm: 120.0,
            metronome: true,
            sequence: true,
            preset: 0,
            macros: [0.42, 0.38, 0.55, 0.36, 0.7],
        };
        render_stereo_wav(&output, &[], settings).unwrap();
        let data = fs::read(&output).unwrap();
        assert_eq!(u16::from_le_bytes([data[22], data[23]]), 2);
        assert_eq!(u32::from_le_bytes(data[24..28].try_into().unwrap()), 8_000);
        assert!(data[44..].iter().any(|sample| *sample != 0));
        let _ = fs::remove_file(output);
    }

    #[test]
    fn rejects_tracks_without_a_known_duration() {
        let output = temp_path("unknown-duration");
        let result = render_stereo_wav(
            &output,
            &[ExportTrack {
                path: PathBuf::new(),
                start_frame: 0,
                total_frames: 0,
                gain: 0.8,
                pan: 0.5,
                muted: false,
                solo: false,
            }],
            ExportSettings {
                sample_rate: 48_000,
                master: 0.8,
                bpm: 92.0,
                metronome: false,
                sequence: false,
                preset: 0,
                macros: [0.42, 0.38, 0.55, 0.36, 0.7],
            },
        );
        assert!(matches!(result, Err(ExportError::UnknownDuration)));
    }

    #[test]
    fn refuses_to_replace_a_source_recording() {
        let source = temp_path("same-file");
        write_source(&source);
        let result = render_stereo_wav(
            &source,
            &[ExportTrack {
                path: source.clone(),
                start_frame: 0,
                total_frames: 2048,
                gain: 0.8,
                pan: 0.5,
                muted: false,
                solo: false,
            }],
            ExportSettings {
                sample_rate: 48_000,
                master: 0.8,
                bpm: 92.0,
                metronome: false,
                sequence: false,
                preset: 0,
                macros: [0.42, 0.38, 0.55, 0.36, 0.7],
            },
        );
        assert!(matches!(result, Err(ExportError::OutputMatchesInput)));
        assert_eq!(fs::metadata(&source).unwrap().len(), 44 + 2048 * 4);
        let _ = fs::remove_file(source);
    }
}
