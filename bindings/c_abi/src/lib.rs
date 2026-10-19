//! Aetherband C-ABI Foreign Function Interface
//!
//! Exposes a flat, C-compatible interface for desktop frontends through Dart FFI.

use daw_core::ringbuf::TelemetryFrame;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

mod threaded_engine;
use threaded_engine::EngineHandle;

pub const DAW_OK: i32 = 0;
pub const DAW_ERROR_INVALID_ARGUMENT: i32 = -1;
pub const DAW_ERROR_COMMAND_REJECTED: i32 = -3;
pub const DAW_ERROR_TRACK_NOT_FOUND: i32 = -4;
pub const DAW_ERROR_EXPORT_FAILED: i32 = -5;
pub const DAW_ERROR_RECORDING_FAILED: i32 = -6;

/// Opaque handle representing a DAW engine instance.
#[repr(C)]
pub struct DAWEngine {
    _unused: [u8; 0],
}

unsafe fn to_core_mut<'a>(engine: *mut DAWEngine) -> Option<&'a mut EngineHandle> {
    if engine.is_null() {
        None
    } else {
        Some(&mut *(engine as *mut EngineHandle))
    }
}

unsafe fn to_core_ref<'a>(engine: *mut DAWEngine) -> Option<&'a EngineHandle> {
    if engine.is_null() {
        None
    } else {
        Some(&*(engine as *mut EngineHandle))
    }
}

/// C-compatible representation of audio telemetry.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct DAWMeteringFrame {
    pub peak_left: f32,
    pub peak_right: f32,
    pub rms_left: f32,
    pub rms_right: f32,
    pub playhead_frame: i64,
    pub total_duration_frames: i64,
    pub is_playing: u8,
    pub device_error_flag: u8,
}

/// Source-file metadata. A zero frame count means duration is not known.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct DAWTrackInfo {
    pub total_frames: u64,
    pub sample_rate: u32,
    pub channels: u32,
}

/// Summary of a finalized input recording.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct DAWRecordingStats {
    pub sample_rate: u32,
    pub frames_written: u64,
    pub frames_dropped: u64,
}

impl From<daw_core::device::RecordingStats> for DAWRecordingStats {
    fn from(stats: daw_core::device::RecordingStats) -> Self {
        Self {
            sample_rate: stats.sample_rate,
            frames_written: stats.frames_written,
            frames_dropped: stats.frames_dropped,
        }
    }
}

impl From<&daw_core::TrackInfo> for DAWTrackInfo {
    fn from(track: &daw_core::TrackInfo) -> Self {
        Self {
            total_frames: track.info.total_frames,
            sample_rate: track.info.sample_rate,
            channels: track.info.channels,
        }
    }
}

impl From<TelemetryFrame> for DAWMeteringFrame {
    fn from(f: TelemetryFrame) -> Self {
        Self {
            peak_left: f.peak_left,
            peak_right: f.peak_right,
            rms_left: f.rms_left,
            rms_right: f.rms_right,
            playhead_frame: f.playhead_frame,
            total_duration_frames: f.total_duration_frames,
            is_playing: if f.is_playing { 1 } else { 0 },
            device_error_flag: f.device_error_flag,
        }
    }
}

/// C-compatible representation of an audio output device.
#[repr(C)]
pub struct DAWDeviceInfo {
    pub index: u32,
    pub name: [c_char; 256],
    pub default_sample_rate: u32,
    pub channels: u16,
    pub is_default: u8,
}

impl Default for DAWDeviceInfo {
    fn default() -> Self {
        Self {
            index: 0,
            name: [0; 256],
            default_sample_rate: 0,
            channels: 0,
            is_default: 0,
        }
    }
}

/// Returns the API version (major << 16 | minor << 8 | patch).
#[no_mangle]
pub extern "C" fn daw_get_api_version() -> u32 {
    11 << 8
}

/// Starts recording from the default Windows input device to a new WAV path.
/// Existing files are never overwritten.
///
/// # Safety
/// `engine` must be a live engine handle with serialized calls; `path` must
/// point to a NUL-terminated UTF-8 path for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_start_recording(
    engine: *mut DAWEngine,
    path: *const c_char,
) -> i32 {
    if engine.is_null() || path.is_null() {
        return DAW_ERROR_INVALID_ARGUMENT;
    }
    let Some(eng) = to_core_mut(engine) else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    let Ok(path) = CStr::from_ptr(path).to_str() else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    match eng.start_recording(std::path::Path::new(path)) {
        Ok(_) => DAW_OK,
        Err(_) => DAW_ERROR_RECORDING_FAILED,
    }
}

/// Stops input recording, drains the writer and finalizes the WAV header.
///
/// # Safety
/// `engine` must be a live engine handle; `out_stats` must be writable for one
/// `DAWRecordingStats`. Calls must be serialized and not race with destroy.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_stop_recording(
    engine: *mut DAWEngine,
    out_stats: *mut DAWRecordingStats,
) -> i32 {
    if engine.is_null() || out_stats.is_null() {
        return DAW_ERROR_INVALID_ARGUMENT;
    }
    let Some(eng) = to_core_mut(engine) else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    match eng.stop_recording() {
        Ok(stats) => {
            out_stats.write(stats.into());
            DAW_OK
        }
        Err(_) => DAW_ERROR_RECORDING_FAILED,
    }
}

/// Render the loaded audio session to stereo 16-bit PCM WAV without changing playback.
///
/// # Safety
/// `engine` must be a live engine handle with serialized calls; `path` must point to a
/// readable NUL-terminated UTF-8 path for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_export_wav(engine: *mut DAWEngine, path: *const c_char) -> i32 {
    if engine.is_null() || path.is_null() {
        return DAW_ERROR_INVALID_ARGUMENT;
    }
    let Some(eng) = to_core_mut(engine) else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    let Ok(path) = CStr::from_ptr(path).to_str() else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    if eng.export_wav(std::path::Path::new(path)).is_ok() {
        DAW_OK
    } else {
        DAW_ERROR_EXPORT_FAILED
    }
}

/// HypnoSynth events: 0 note-on (key 0..127, velocity 0..1), 1 note-off,
/// 2 preset (0..2), 3 macro (key 0..4, value 0..1), 4 all-sounds-off,
/// 5 set an eight-note-per-bar sequencer step (step 0..15, note 0..127 or -1 for rest);
/// 6-9 set HypnoSynth track gain (0..1), pan (0..1), mute (0/1), and solo (0/1), key 0.
///
/// # Safety
/// `engine` must be a live handle returned by `daw_engine_create`, with calls
/// serialized on its owner thread and no concurrent destroy.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_synth_event(
    engine: *mut DAWEngine,
    event: u32,
    key: u32,
    value: f32,
) -> i32 {
    let Some(eng) = to_core_mut(engine) else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    if eng.synth_event(event, key, value) {
        DAW_OK
    } else {
        DAW_ERROR_COMMAND_REJECTED
    }
}

/// Install or update a 16-step HypnoSynth arrangement region. Each note is
/// -1 for a rest or a MIDI note in 0..=127. Start time is timeline seconds.
///
/// # Safety
/// `engine` must be a live serialized handle and `notes` must point to 16
/// readable `i32` values for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_set_sequence_region(
    engine: *mut DAWEngine,
    region_id: u32,
    start_seconds: f64,
    notes: *const i32,
) -> i32 {
    if engine.is_null() || notes.is_null() || region_id == 0 {
        return DAW_ERROR_INVALID_ARGUMENT;
    }
    let Some(eng) = to_core_mut(engine) else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    if !start_seconds.is_finite() || !(0.0..=86_400.0).contains(&start_seconds) {
        return DAW_ERROR_INVALID_ARGUMENT;
    }
    let values = std::slice::from_raw_parts(notes, 16);
    let mut pattern = [None; 16];
    for (slot, value) in pattern.iter_mut().zip(values.iter().copied()) {
        if !(-1..=127).contains(&value) {
            return DAW_ERROR_INVALID_ARGUMENT;
        }
        *slot = (value >= 0).then_some(value as u8);
    }
    if eng.set_sequence_region(region_id, start_seconds, pattern) {
        DAW_OK
    } else {
        DAW_ERROR_COMMAND_REJECTED
    }
}

/// Remove a HypnoSynth arrangement region by its nonzero session-local ID.
///
/// # Safety
/// `engine` must be a live serialized handle.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_remove_sequence_region(
    engine: *mut DAWEngine,
    region_id: u32,
) -> i32 {
    let Some(eng) = to_core_mut(engine) else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    if region_id == 0 {
        return DAW_ERROR_INVALID_ARGUMENT;
    }
    if eng.remove_sequence_region(region_id) {
        DAW_OK
    } else {
        DAW_ERROR_COMMAND_REJECTED
    }
}

/// Set implicit track solo. Other tracks stay muted until the final solo clears.
///
/// # Safety
/// `engine` must be a live handle returned by `daw_engine_create`, with calls
/// serialized on its owner thread and no concurrent destroy.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_solo_track(
    engine: *mut DAWEngine,
    track_id: u32,
    solo: u8,
) -> i32 {
    let Some(eng) = to_core_mut(engine) else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    if eng.solo_track(daw_core::ringbuf::TrackId(track_id), solo != 0) {
        DAW_OK
    } else {
        DAW_ERROR_TRACK_NOT_FOUND
    }
}

/// Configure the sample-clock tempo, metronome and original HypnoSynth phrase.
///
/// # Safety
/// `engine` must be a live handle returned by `daw_engine_create`, with calls
/// serialized on its owner thread and no concurrent destroy.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_configure_transport(
    engine: *mut DAWEngine,
    bpm: f32,
    metronome: u8,
    sequence: u8,
) -> i32 {
    let Some(eng) = to_core_mut(engine) else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    if eng.configure_transport(bpm, metronome != 0, sequence != 0) {
        DAW_OK
    } else {
        DAW_ERROR_COMMAND_REJECTED
    }
}

/// Creates a new DAW engine instance and initializes the default audio stream.
///
/// Returns 0 on success, negative error code on failure.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_create(out_engine: *mut *mut DAWEngine) -> i32 {
    if out_engine.is_null() {
        return -1;
    }

    match EngineHandle::new() {
        Ok(engine) => {
            let boxed = Box::new(engine);
            *out_engine = Box::into_raw(boxed) as *mut DAWEngine;
            0
        }
        Err(_) => -2,
    }
}

/// Destroys a DAW engine instance and releases all hardware audio resources.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_destroy(engine: *mut DAWEngine) -> i32 {
    if engine.is_null() {
        return -1;
    }

    drop(Box::from_raw(engine as *mut EngineHandle));
    0
}

/// Starts audio playback.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_play(engine: *mut DAWEngine) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        if eng.play() {
            0
        } else {
            -3
        }
    } else {
        -1
    }
}

/// Pauses audio playback.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_pause(engine: *mut DAWEngine) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        if eng.pause() {
            0
        } else {
            -3
        }
    } else {
        -1
    }
}

/// Stops audio playback and rewinds playhead.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_stop(engine: *mut DAWEngine) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        if eng.stop() {
            0
        } else {
            -3
        }
    } else {
        -1
    }
}

/// Seeks the transport to an absolute position in seconds.
///
/// # Safety
/// `engine` must be null or a valid handle returned by `daw_engine_create` that
/// has not been destroyed. Calls for one handle must be serialized.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_seek_seconds(engine: *mut DAWEngine, seconds: f64) -> i32 {
    if !seconds.is_finite() || seconds < 0.0 || seconds > 86_400.0 {
        return DAW_ERROR_INVALID_ARGUMENT;
    }
    if let Some(eng) = to_core_ref(engine) {
        if eng.seek_seconds(seconds) {
            DAW_OK
        } else {
            DAW_ERROR_COMMAND_REJECTED
        }
    } else {
        DAW_ERROR_INVALID_ARGUMENT
    }
}

/// Sets the master volume gain (with de-zipper smoothing).
#[no_mangle]
pub unsafe extern "C" fn daw_engine_set_master_volume(engine: *mut DAWEngine, gain: f32) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        if eng.set_master_volume(gain) {
            0
        } else {
            -3
        }
    } else {
        -1
    }
}

/// Enables or disables the diagnostic test tone oscillator.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_set_test_tone(
    engine: *mut DAWEngine,
    enabled: u8,
    freq_hz: f32,
) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        if eng.set_test_tone(enabled != 0, freq_hz) {
            0
        } else {
            -3
        }
    } else {
        -1
    }
}

/// Polls the latest telemetry frame from the audio thread.
///
/// Returns 0 if a new frame was populated, 1 if no new frame is available, negative on error.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_poll_telemetry(
    engine: *mut DAWEngine,
    out_frame: *mut DAWMeteringFrame,
) -> i32 {
    if out_frame.is_null() {
        return -1;
    }

    if let Some(eng) = to_core_mut(engine) {
        match eng.poll_telemetry() {
            Ok(Some(frame)) => {
                *out_frame = frame.into();
                0
            }
            Ok(None) => 1, // Queue empty, keep previous frame.
            Err(()) => -2,
        }
    } else {
        -1
    }
}

/// Queries the number of available audio output devices.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_get_device_count(engine: *mut DAWEngine) -> i32 {
    if let Some(eng) = to_core_ref(engine) {
        match eng.enumerate_devices() {
            Ok(devices) => devices.len() as i32,
            Err(_) => -2,
        }
    } else {
        -1
    }
}

/// Gets device metadata for a given device index.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_get_device_info(
    engine: *mut DAWEngine,
    index: u32,
    out_info: *mut DAWDeviceInfo,
) -> i32 {
    if out_info.is_null() {
        return -1;
    }

    if let Some(eng) = to_core_ref(engine) {
        match eng.enumerate_devices() {
            Ok(devices) => {
                if let Some(dev) = devices.get(index as usize) {
                    let info = &mut *out_info;
                    info.index = index;
                    info.default_sample_rate = dev.default_sample_rate;
                    info.channels = dev.channels;
                    info.is_default = if dev.is_default { 1 } else { 0 };

                    // Copy name string safely into fixed buffer
                    ptr::write_bytes(info.name.as_mut_ptr(), 0, 256);
                    let c_str = CString::new(dev.name.clone()).unwrap_or_default();
                    let bytes = c_str.as_bytes_with_nul();
                    let copy_len = bytes.len().min(255);
                    ptr::copy_nonoverlapping(
                        bytes.as_ptr() as *const c_char,
                        info.name.as_mut_ptr(),
                        copy_len,
                    );

                    0
                } else {
                    -4 // Device index out of bounds
                }
            }
            Err(_) => -2,
        }
    } else {
        -1
    }
}

/// Writes the active output sample rate in Hz to `out_sample_rate`.
///
/// Returns 0 on success, -1 for an invalid handle or output pointer.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_get_sample_rate(
    engine: *mut DAWEngine,
    out_sample_rate: *mut u32,
) -> i32 {
    if out_sample_rate.is_null() {
        return -1;
    }
    if let Some(eng) = to_core_ref(engine) {
        match eng.output_sample_rate() {
            Ok(rate) => {
                *out_sample_rate = rate;
                0
            }
            Err(()) => -2,
        }
    } else {
        -1
    }
}

/// Selects an audio output device by index.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_select_device(engine: *mut DAWEngine, index: u32) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        match eng.select_device(index as usize) {
            Ok(()) => 0,
            Err(_) => -2,
        }
    } else {
        -1
    }
}

// ── Multi-track playback and mixing FFI ───────────────────────────────────────

/// Reads source metadata for an already loaded track without accessing disk.
///
/// Returns 0 on success, -1 for null arguments, or -4 for an unknown track ID.
/// On failure the caller's output is unchanged.
///
/// # Safety
/// `engine` must be a live handle, with calls serialized against destruction.
/// `out_info` must be writable and aligned for one `DAWTrackInfo`.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_get_track_info(
    engine: *mut DAWEngine,
    track_id: u32,
    out_info: *mut DAWTrackInfo,
) -> i32 {
    if out_info.is_null() {
        return DAW_ERROR_INVALID_ARGUMENT;
    }
    let Some(eng) = to_core_ref(engine) else {
        return DAW_ERROR_INVALID_ARGUMENT;
    };
    let Ok(tracks) = eng.tracks() else {
        return -2;
    };
    match tracks.iter().find(|track| track.id.0 == track_id) {
        Some(track) => {
            *out_info = track.into();
            DAW_OK
        }
        None => DAW_ERROR_TRACK_NOT_FOUND,
    }
}

/// Loads an audio file into a new track, spawning a background stream decoder.
///
/// On success, writes the allocated track ID to `out_track_id` and returns 0.
/// Returns negative error code on failure.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_load_track(
    engine: *mut DAWEngine,
    path_utf8: *const c_char,
    out_track_id: *mut u32,
) -> i32 {
    if engine.is_null() || path_utf8.is_null() || out_track_id.is_null() {
        return -1;
    }

    let c_str = match std::ffi::CStr::from_ptr(path_utf8).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    if let Some(eng) = to_core_mut(engine) {
        match eng.load_track(std::path::Path::new(c_str)) {
            Ok(track_id) => {
                *out_track_id = track_id.0;
                0
            }
            Err(_) => -2,
        }
    } else {
        -1
    }
}

/// Removes a track by ID.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_remove_track(engine: *mut DAWEngine, track_id: u32) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        let Ok(tracks) = eng.tracks() else {
            return -2;
        };
        if !tracks.iter().any(|track| track.id.0 == track_id) {
            return DAW_ERROR_TRACK_NOT_FOUND;
        }
        if eng.remove_track(daw_core::ringbuf::TrackId(track_id)) {
            DAW_OK
        } else {
            DAW_ERROR_COMMAND_REJECTED
        }
    } else {
        DAW_ERROR_INVALID_ARGUMENT
    }
}

/// Sets track volume (linear gain).
#[no_mangle]
pub unsafe extern "C" fn daw_engine_set_track_volume(
    engine: *mut DAWEngine,
    track_id: u32,
    gain: f32,
) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        if eng.set_track_volume(daw_core::ringbuf::TrackId(track_id), gain) {
            0
        } else {
            -3
        }
    } else {
        -1
    }
}

/// Sets track pan position (0.0 = full left, 0.5 = center, 1.0 = full right).
#[no_mangle]
pub unsafe extern "C" fn daw_engine_set_track_pan(
    engine: *mut DAWEngine,
    track_id: u32,
    pan: f32,
) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        if eng.set_track_pan(daw_core::ringbuf::TrackId(track_id), pan) {
            0
        } else {
            -3
        }
    } else {
        -1
    }
}

/// Sets an audio clip's absolute start time in session seconds.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_set_track_start_seconds(
    engine: *mut DAWEngine,
    track_id: u32,
    seconds: f64,
) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        if eng.set_track_start_seconds(daw_core::ringbuf::TrackId(track_id), seconds) {
            0
        } else {
            -3
        }
    } else {
        -1
    }
}

/// Sets the source interval used by an audio region.
///
/// # Safety
/// `engine` must be null or a valid, live engine handle. Calls for one handle
/// must be serialized.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_set_track_region_seconds(
    engine: *mut DAWEngine,
    track_id: u32,
    source_start_seconds: f64,
    duration_seconds: f64,
) -> i32 {
    if !source_start_seconds.is_finite()
        || !duration_seconds.is_finite()
        || source_start_seconds < 0.0
        || duration_seconds <= 0.0
        || source_start_seconds + duration_seconds > 86_400.0
    {
        return DAW_ERROR_INVALID_ARGUMENT;
    }
    if let Some(eng) = to_core_mut(engine) {
        if eng.set_track_region_seconds(
            daw_core::ringbuf::TrackId(track_id),
            source_start_seconds,
            duration_seconds,
        ) {
            DAW_OK
        } else {
            DAW_ERROR_COMMAND_REJECTED
        }
    } else {
        DAW_ERROR_INVALID_ARGUMENT
    }
}

/// Mutes or unmutes a track.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_mute_track(
    engine: *mut DAWEngine,
    track_id: u32,
    muted: u8,
) -> i32 {
    if let Some(eng) = to_core_mut(engine) {
        if eng.mute_track(daw_core::ringbuf::TrackId(track_id), muted != 0) {
            0
        } else {
            -3
        }
    } else {
        -1
    }
}

/// Queries the number of active loaded tracks.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_get_track_count(engine: *mut DAWEngine) -> i32 {
    if let Some(eng) = to_core_ref(engine) {
        match eng.tracks() {
            Ok(tracks) => tracks.len() as i32,
            Err(()) => -2,
        }
    } else {
        -1
    }
}

#[cfg(test)]
mod ffi_contract_tests {
    use super::*;

    #[test]
    fn api_version_matches_dart_ffi_contract() {
        assert_eq!(daw_get_api_version(), 0x0000_0B00);
    }

    #[test]
    fn export_rejects_null_engine_or_path() {
        assert_eq!(
            unsafe { daw_engine_export_wav(ptr::null_mut(), ptr::null()) },
            DAW_ERROR_INVALID_ARGUMENT
        );
    }

    #[test]
    fn seek_rejects_null_handles_and_invalid_positions() {
        unsafe {
            assert_eq!(daw_engine_seek_seconds(ptr::null_mut(), 1.0), -1);
            assert_eq!(daw_engine_seek_seconds(ptr::null_mut(), -1.0), -1);
            assert_eq!(daw_engine_seek_seconds(ptr::null_mut(), f64::NAN), -1);
            assert_eq!(daw_engine_seek_seconds(ptr::null_mut(), 86_400.1), -1);
        }
    }

    #[test]
    fn sequence_region_exports_reject_null_arguments_and_zero_ids() {
        let notes = [60_i32; 16];
        unsafe {
            assert_eq!(
                daw_engine_set_sequence_region(ptr::null_mut(), 1, 0.0, notes.as_ptr()),
                DAW_ERROR_INVALID_ARGUMENT
            );
            assert_eq!(
                daw_engine_set_sequence_region(ptr::null_mut(), 1, 0.0, ptr::null()),
                DAW_ERROR_INVALID_ARGUMENT
            );
            assert_eq!(
                daw_engine_remove_sequence_region(ptr::null_mut(), 1),
                DAW_ERROR_INVALID_ARGUMENT
            );
            assert_eq!(
                daw_engine_remove_sequence_region(ptr::null_mut(), 0),
                DAW_ERROR_INVALID_ARGUMENT
            );
        }
    }

    #[test]
    fn region_rejects_null_handles_and_invalid_ranges() {
        unsafe {
            assert_eq!(
                daw_engine_set_track_region_seconds(ptr::null_mut(), 1, 0.0, 1.0),
                DAW_ERROR_INVALID_ARGUMENT
            );
            assert_eq!(
                daw_engine_set_track_region_seconds(ptr::null_mut(), 1, -0.1, 1.0),
                DAW_ERROR_INVALID_ARGUMENT
            );
            assert_eq!(
                daw_engine_set_track_region_seconds(ptr::null_mut(), 1, 0.0, 0.0),
                DAW_ERROR_INVALID_ARGUMENT
            );
            assert_eq!(
                daw_engine_set_track_region_seconds(ptr::null_mut(), 1, 86_400.0, 1.0),
                DAW_ERROR_INVALID_ARGUMENT
            );
        }
    }

    #[test]
    fn recording_exports_reject_null_arguments() {
        assert_eq!(
            unsafe { daw_engine_start_recording(ptr::null_mut(), ptr::null()) },
            DAW_ERROR_INVALID_ARGUMENT
        );
        assert_eq!(
            unsafe { daw_engine_stop_recording(ptr::null_mut(), ptr::null_mut()) },
            DAW_ERROR_INVALID_ARGUMENT
        );
        assert_eq!(std::mem::size_of::<DAWRecordingStats>(), 24);
        assert_eq!(std::mem::offset_of!(DAWRecordingStats, sample_rate), 0);
        assert_eq!(std::mem::offset_of!(DAWRecordingStats, frames_written), 8);
        assert_eq!(std::mem::offset_of!(DAWRecordingStats, frames_dropped), 16);
    }

    #[test]
    fn track_info_uses_source_rate_and_preserves_large_frame_counts() {
        let track = daw_core::TrackInfo {
            id: daw_core::ringbuf::TrackId(42),
            file_path: String::new(),
            info: daw_core::decoder::AudioFileInfo {
                total_frames: u32::MAX as u64 + 44100,
                sample_rate: 44100,
                channels: 1,
                duration_secs: 0.0,
            },
            output_frames: 48000,
            source_start_frame: 0,
            start_frame: 0,
            gain: 0.8,
            pan: 0.5,
            muted: false,
            solo: false,
        };
        let info = DAWTrackInfo::from(&track);
        assert_eq!(info.total_frames, track.info.total_frames);
        assert_eq!(info.sample_rate, 44100);
        assert_eq!(info.channels, 1);
        assert_eq!(std::mem::size_of::<DAWTrackInfo>(), 16);
        assert_eq!(std::mem::offset_of!(DAWTrackInfo, total_frames), 0);
        assert_eq!(std::mem::offset_of!(DAWTrackInfo, sample_rate), 8);
        assert_eq!(std::mem::offset_of!(DAWTrackInfo, channels), 12);
    }

    #[test]
    fn track_info_rejects_null_arguments_without_changing_output() {
        let mut info = DAWTrackInfo {
            total_frames: 99,
            sample_rate: 44100,
            channels: 2,
        };
        let before = info;
        unsafe {
            assert_eq!(daw_engine_get_track_info(ptr::null_mut(), 1, &mut info), -1);
            assert_eq!(
                daw_engine_get_track_info(ptr::null_mut(), 1, ptr::null_mut()),
                -1
            );
        }
        assert_eq!(info, before);
    }

    #[test]
    fn sample_rate_query_rejects_null_handle_or_output() {
        let mut sample_rate = 0_u32;
        unsafe {
            assert_eq!(
                daw_engine_get_sample_rate(ptr::null_mut(), &mut sample_rate),
                -1
            );
            assert_eq!(
                daw_engine_get_sample_rate(ptr::null_mut(), ptr::null_mut()),
                -1
            );
        }
    }
}
