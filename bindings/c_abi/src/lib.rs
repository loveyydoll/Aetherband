//! RouletteStudio C-ABI Foreign Function Interface
//!
//! Exposes a flat, C99-compatible interface for consumption by C# (.NET 10) P/Invoke.

use daw_core::ringbuf::TelemetryFrame;
use std::ffi::CString;
use std::os::raw::c_char;
use std::ptr;

/// Opaque handle representing a DAW engine instance.
#[repr(C)]
pub struct DAWEngine {
    _unused: [u8; 0],
}

unsafe fn to_core_mut<'a>(engine: *mut DAWEngine) -> Option<&'a mut daw_core::DAWEngine> {
    if engine.is_null() {
        None
    } else {
        Some(&mut *(engine as *mut daw_core::DAWEngine))
    }
}

unsafe fn to_core_ref<'a>(engine: *mut DAWEngine) -> Option<&'a daw_core::DAWEngine> {
    if engine.is_null() {
        None
    } else {
        Some(&*(engine as *mut daw_core::DAWEngine))
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
    (0 << 16) | (1 << 8) | 0
}

/// Creates a new DAW engine instance and initializes the default audio stream.
///
/// Returns 0 on success, negative error code on failure.
#[no_mangle]
pub unsafe extern "C" fn daw_engine_create(out_engine: *mut *mut DAWEngine) -> i32 {
    if out_engine.is_null() {
        return -1;
    }

    match daw_core::DAWEngine::new() {
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

    drop(Box::from_raw(engine as *mut daw_core::DAWEngine));
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
        if let Some(frame) = eng.poll_telemetry() {
            *out_frame = frame.into();
            0
        } else {
            1 // Queue empty, keep previous frame
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
        if eng.remove_track(daw_core::ringbuf::TrackId(track_id)) {
            0
        } else {
            -4 // Track not found
        }
    } else {
        -1
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
        eng.tracks().len() as i32
    } else {
        -1
    }
}
