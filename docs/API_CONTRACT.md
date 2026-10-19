# C ABI Contract — Aetherband

**Current ABI version:** `0.5.0` (`daw_get_api_version() == 0x00000500`)
**Source of truth:** `bindings/c_abi/src/lib.rs`. If this document disagrees with the Rust exports, fix the documentation or deliberately update the ABI and version together.

This contract is for the Flutter/Dart desktop app using `dart:ffi`. The former C# / Avalonia frontend and its `csbindgen` P/Invoke generation have been removed from the desktop architecture.

## Boundary rules

- Only exported `extern "C"` functions and `#[repr(C)]` structs are public ABI.
- The engine is an opaque pointer. Dart must never dereference it or retain it after destroy.
- Check API version **before** calling any other native export.
- Check every result code; do not infer success from a local UI state change.
- Serialize calls made against one engine handle. Never destroy a handle while a call or telemetry poll is active.
- Native code owns engine memory. The caller owns any buffers passed as output pointers and must keep them valid for the duration of the call.
- Strings passed into `daw_engine_load_track` must be valid NUL-terminated UTF-8 for the duration of the call.
- No file I/O, locks, allocation, waiting or UI work may be moved into the audio callback to simplify FFI.
- Do not pass audio buffers through Flutter widgets or platform channels.

## ABI version

`daw_get_api_version()` returns `(major << 16) | (minor << 8) | patch`. Version 0.5.0 adds `daw_engine_set_track_start_seconds` for scheduling imported clips in the arrangement. Version 0.4.0 adds HypnoSynth event and transport configuration calls plus per-track solo. Version 0.3.0 added `daw_engine_get_track_info`, preserves engine OS-thread ownership behind the opaque handle, and returns -3 for queue-rejected removal without deleting track metadata. Version 0.2.0 introduced the active sample-rate query. Rebuild the native library and Dart app together; the Dart adapter requires an exact version match.

Any incompatible layout/signature/ownership change requires a version change and synchronized Rust/Dart updates. Additive exports should still be documented and versioned deliberately.

## C-compatible structures

### `DAWTrackInfo`

| Field | C type | Meaning |
|---|---|---|
| `total_frames` | `uint64_t` | Source frames, or zero when duration is unavailable |
| `sample_rate` | `uint32_t` | Source rate in Hz, not the output device rate |
| `channels` | `uint32_t` | Source channel count |

Size is 16 bytes; field offsets are 0, 8 and 12. Compute seconds as `total_frames / sample_rate` only when both are positive. This is probed file metadata, not an independently measured decoded duration. The query reads existing control-side metadata without reopening the file. Failed queries leave the output buffer unchanged.

### `DAWMeteringFrame`

| Field | C type | Meaning |
|---|---|---|
| `peak_left`, `peak_right` | `float` | Linear peak amplitudes |
| `rms_left`, `rms_right` | `float` | RMS amplitudes |
| `playhead_frame` | `int64_t` | Current playhead frame |
| `total_duration_frames` | `int64_t` | Total duration in output frames |
| `is_playing` | `uint8_t` | 1 when playing, otherwise 0 |
| `device_error_flag` | `uint8_t` | 1 when the engine reports a device error |

### `DAWDeviceInfo`

| Field | C type | Meaning |
|---|---|---|
| `index` | `uint32_t` | Device index in the current enumeration |
| `name` | `char[256]` | NUL-terminated device name when available |
| `default_sample_rate` | `uint32_t` | Device's reported default rate |
| `channels` | `uint16_t` | Reported output channel count |
| `is_default` | `uint8_t` | 1 when the device is the default |

Do not substitute a different field order or widths in Dart. The Dart `Struct` definitions must match the Rust `#[repr(C)]` layout exactly.

## Exported functions

| Function | Purpose | Return semantics |
|---|---|---|
| `daw_get_api_version()` | Read ABI version | Packed `u32` version |
| `daw_engine_create(out_engine)` | Create engine and open default output stream | 0 success; negative error |
| `daw_engine_destroy(engine)` | Stop and destroy engine resources | 0 success; negative error |
| `daw_engine_play(engine)` | Request playback | 0 accepted; negative error |
| `daw_engine_pause(engine)` | Request pause | 0 accepted; negative error |
| `daw_engine_stop(engine)` | Request Stop and decoder restart | 0 accepted; negative error |
| `daw_engine_poll_telemetry(engine, out_frame)` | Read telemetry | 0 frame read; 1 no new frame; negative error |
| `daw_engine_get_sample_rate(engine, out_rate)` | Get active output rate in Hz | 0 success; negative error |
| `daw_engine_set_master_volume(engine, gain)` | Set master linear gain | 0 accepted; negative error |
| `daw_engine_synth_event(engine, event, key, value)` | Send HypnoSynth note, preset, macro or panic event | 0 accepted; negative error |
| `daw_engine_configure_transport(engine, bpm, metronome, sequence)` | Configure tempo, click and original synth phrase | 0 accepted; negative error |
| `daw_engine_solo_track(engine, track_id, solo)` | Enable implicit solo for one imported track | 0 accepted; negative error |
| `daw_engine_set_track_start_seconds(engine, track_id, seconds)` | Set imported clip start position in the arrangement | 0 accepted; negative error |
| `daw_engine_set_test_tone(engine, enabled, freq_hz)` | Toggle diagnostic tone | 0 accepted; negative error |
| `daw_engine_get_device_count(engine)` | Enumerate output devices and return count | Non-negative count; negative error |
| `daw_engine_get_device_info(engine, index, out_info)` | Read device metadata | 0 success; negative error |
| `daw_engine_select_device(engine, index)` | Select output device | 0 success; negative error |
| `daw_engine_load_track(engine, path_utf8, out_track_id)` | Load a file into a new audio track | 0 success; negative error |
| `daw_engine_get_track_info(engine, track_id, out_info)` | Read loaded source metadata | 0 success; -1 null argument; -2 engine worker failure; -4 unknown track |
| `daw_engine_remove_track(engine, track_id)` | Remove track | 0 success; negative error |
| `daw_engine_set_track_volume(engine, track_id, gain)` | Set track linear gain | 0 accepted; negative error |
| `daw_engine_set_track_pan(engine, track_id, pan)` | Set track pan (0 left, 0.5 centre, 1 right) | 0 accepted; negative error |
| `daw_engine_mute_track(engine, track_id, muted)` | Mute/unmute track | 0 accepted; negative error |
| `daw_engine_get_track_count(engine)` | Get number of loaded tracks | Non-negative count; negative error |

The exact function signatures and implementation are defined in `bindings/c_abi/src/lib.rs`. Do not add fictitious `DAWConfig`, `DAWCommand`, `daw_engine_send_command`, or `daw_enumerate_output_devices` declarations: they are not the current exported API.

## Error codes and caveats

The implementation currently uses these values in different functions:

- `0`: success / command accepted.
- `1`: no new telemetry frame (only for telemetry polling).
- `-1`: invalid/null handle, pointer or UTF-8 path input.
- `-2`: engine/device initialization, enumeration or track-load failure (function-dependent).
- `-3`: engine rejected a transport or parameter command (function-dependent).
- `-4`: device index or track identifier was not found (function-dependent).

Named Rust constants for these boundaries are `DAW_OK`, `DAW_ERROR_INVALID_ARGUMENT`, `DAW_ERROR_COMMAND_REJECTED`, and `DAW_ERROR_TRACK_NOT_FOUND`. Removal returns -3 if its command cannot be accepted, keeping the track inventory and decoder intact for retry.

These are current implementation conventions, not yet a single exhaustive typed error enum. Preserve the originating function and numeric result in diagnostics. Before expanding the public API, define stable named error constants and map decoder/device errors to actionable messages rather than collapsing all failures into one code.

## Threading and lifecycle

- The opaque handle owns a dedicated Rust control thread, which creates, operates and destroys the actual engine and its non-Send CPAL stream. Only owned commands and results cross its bounded 64-job standard-library channel. Full/disconnected queues fail; accepted calls wait for a reply on the non-audio calling thread. Destroy closes the channel, drains accepted jobs and joins the owner thread. No engine pointers or audio buffers cross Dart ports.
- Flutter calls the synchronous C ABI from a separate long-lived Dart isolate, keeping file probing, decoder restarts and native destruction off the UI isolate. Its request backlog is bounded at 64; disposal is always admitted, rejects new requests and waits behind accepted work.
- Serialize control calls for a given handle; the current Rust helper returns mutable access from the opaque pointer and must not be called concurrently for that handle.
- Telemetry polling is a bounded, periodic control-side operation; it must not run from a paint/build callback.
- Stop polling and prevent new control calls before destroying the engine.
- The audio callback communicates through bounded native queues; it does not call Dart/Flutter.
- Device selection builds a replacement queue/processor, recreates decoders at the selected output rate, and re-installs existing track IDs plus stored gain/pan/mute settings before committing the new pipeline. This path still requires automated testing and real-device verification; do not call it production-safe until those pass.
- The Flutter import path rewinds transport, loads the file, queries its metadata and creates a duration-scaled clip only on success. Unknown duration is labelled; imported clips can be moved while stopped at the start and the native scheduler follows their saved position. Real waveforms are unavailable. Engine retry starts a fresh inventory and clears old native clip IDs.

## Verification checklist

- [ ] Rust exports and this contract agree.
- [ ] Dart struct layout matches Rust layout on Windows.
- [ ] Version mismatch is rejected before engine creation.
- [ ] Missing symbols fail before a native handle is created.
- [ ] Every native result is handled and surfaced.
- [ ] Engine create/destroy, polling and shutdown are exercised with a built native library.
- [ ] Real audio playback is manually listened to on Windows.
