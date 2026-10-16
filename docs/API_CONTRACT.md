# Native C ABI Contract — Aetherband

**Status snapshot:** 2026-10-17  
**Authoritative implementation:** `bindings/c_abi/src/lib.rs`  
**Required Flutter use:** Dart FFI over this C ABI. Do not call Rust internals directly.

> **Correction to older drafts:** Earlier revisions of this document described aspirational examples such as `DAWConfig`, `DAWCommand`, `daw_engine_send_command`, and `daw_enumerate_output_devices`. Those are **not** current exports in `bindings/c_abi/src/lib.rs` at this snapshot. The current source file wins over stale examples. Update this contract when the ABI source changes.

## 1. Boundary rules

- Exported functions use `extern "C"`; C-compatible structs use `#[repr(C)]`.
- The engine is represented by an opaque `DAWEngine*` handle. The UI must never inspect or allocate the Rust engine structure itself.
- Native allocations/resources are owned and released by Rust, through `daw_engine_destroy`.
- Each native call returns an integer status; the UI must map errors into clear UI state, not silently assume success.
- Native callbacks, audio data, Rust references, trait objects, and internal Rust types do not cross this boundary.
- The Rust core retains audio-device ownership, decoding, DSP, mixing and the real-time callback.

## 2. API version

`daw_get_api_version()` returns the packed version `(major << 16) | (minor << 8) | patch`. The current source returns **0.1.0**. Clients should query this during initialization and fail clearly on an unsupported incompatible version.

## 3. Current C-compatible structures

The following field layouts match the current source. Re-check `bindings/c_abi/src/lib.rs` before writing bindings or changing fields.

### 3.1 Opaque engine handle

The only supported operation on the handle is passing it back to exported functions. Treat it as an opaque native pointer; never dereference it in Dart/C#.

### 3.2 `DAWMeteringFrame`

Declared `#[repr(C)]` in the Rust source, in this field order:

| Field | Rust type | Meaning |
|---|---|---|
| `peak_left` | `f32` | Left-channel peak |
| `peak_right` | `f32` | Right-channel peak |
| `rms_left` | `f32` | Left-channel RMS |
| `rms_right` | `f32` | Right-channel RMS |
| `playhead_frame` | `i64` | Current playhead sample frame |
| `total_duration_frames` | `i64` | Total duration in sample frames, as reported by the engine |
| `is_playing` | `u8` | 0/1 playing flag |
| `device_error_flag` | `u8` | Device error flag |

Do not assume the struct is identical to earlier examples that omitted `total_duration_frames`. Native alignment and padding follow C ABI / `#[repr(C)]` rules; test the Dart representation against the compiled library.

### 3.3 `DAWDeviceInfo`

Declared `#[repr(C)]` in this field order:

| Field | Rust type | Meaning |
|---|---|---|
| `index` | `u32` | Device index |
| `name` | `[c_char; 256]` | Fixed-length, null-terminated device name buffer |
| `default_sample_rate` | `u32` | Device's reported default sample rate |
| `channels` | `u16` | Channel count reported by the engine |
| `is_default` | `u8` | 0/1 system default flag |

C `char` signedness varies by platform; Dart must allocate and decode this fixed buffer safely as UTF-8/compatible text, stop at the first NUL, and never read beyond 256 bytes.

## 4. Current exported function inventory

The following is a semantic inventory of the exports in the source at this snapshot. For exact parameter types, pointer mutability, safety preconditions and implementation, consult `bindings/c_abi/src/lib.rs`.

### 4.1 Version and lifecycle

- `daw_get_api_version() -> u32`
- `daw_engine_create(out_engine: *mut *mut DAWEngine) -> i32`
- `daw_engine_destroy(engine: *mut DAWEngine) -> i32`

Create writes the newly allocated engine handle into the output pointer. Destroy releases its Rust-owned resources. Do not destroy twice and never destroy while another call is in flight.

### 4.2 Transport and engine controls

- `daw_engine_play(engine) -> i32`
- `daw_engine_pause(engine) -> i32`
- `daw_engine_stop(engine) -> i32`
- `daw_engine_set_master_volume(engine, gain: f32) -> i32`
- `daw_engine_set_test_tone(engine, enabled: u8, freq_hz: f32) -> i32`
- `daw_engine_poll_telemetry(engine, out_frame: *mut DAWMeteringFrame) -> i32`

A successful return means the native function accepted/completed the operation according to its implementation; it is not automatically proof that the audio device has already emitted silence or that the playhead has updated. Reflect transport/meter state from telemetry and regression/runtime tests, not from a local button animation alone.

### 4.3 Device management

- `daw_engine_get_device_count(engine) -> i32`
- `daw_engine_get_device_info(engine, index: u32, out_info: *mut DAWDeviceInfo) -> i32`
- `daw_engine_select_device(engine, index: u32) -> i32`

The device count function returns a count when successful or a negative error code. Enumerate indices against the current count; handle devices disappearing or selection failure. Test switching while tracks are loaded before assuming it preserves every engine state.

### 4.4 Track management and mix controls

- `daw_engine_load_track(engine, path_utf8: *const c_char, out_track_id: *mut u32) -> i32`
- `daw_engine_remove_track(engine, track_id: u32) -> i32`
- `daw_engine_set_track_volume(engine, track_id: u32, gain: f32) -> i32`
- `daw_engine_set_track_pan(engine, track_id: u32, pan: f32) -> i32`
- `daw_engine_mute_track(engine, track_id: u32, muted: u8) -> i32`
- `daw_engine_get_track_count(engine) -> i32`

Paths are expected as valid NUL-terminated UTF-8 bytes. Keep their backing memory alive for the duration of the call and ensure there are no embedded NUL characters in paths. The engine returns a track ID; retain the mapping between that native ID and Flutter's UI track model. Never use a list index as a substitute for the returned engine track ID.

## 5. Return-code behavior currently visible in source

There is no single exported `DAWResult` enum today. Functions return `i32`, and exact conditions differ by function. The following summaries come from the implementation, and should be re-checked whenever the source changes:

| Function group | Source-level outcomes |
|---|---|
| `daw_engine_create` | `0` success; `-1` null output pointer; `-2` engine initialization failure |
| `daw_engine_destroy` | `0` success; `-1` null handle |
| Play/pause/stop/master/test-tone | `0` accepted/success; `-1` null handle; `-3` core operation reports failure |
| `daw_engine_poll_telemetry` | `0` populated a new frame; `1` no frame available; `-1` invalid output/handle |
| Device count/info/select | Device count is non-negative on success; negative codes indicate invalid handle, enumeration/selection failure, invalid output or out-of-range index (inspect each function) |
| Track load | `0` success and output ID populated; `-1` invalid pointer/UTF-8/handle; `-2` load error |
| Track remove | `0` success; `-1` invalid handle; `-4` track not found |
| Track volume/pan/mute | `0` success; `-1` invalid handle; `-3` core operation reports failure |
| Track count | Non-negative count on success; `-1` invalid handle |

Map and expose errors explicitly. Do not turn native failures into fake success or silently swap to mock telemetry in a production build.

## 6. Threading and ownership contract for UI clients

The exported Rust facade currently converts the same opaque pointer into references to `daw_core::DAWEngine`. Until the ABI is redesigned with explicit thread-safety guarantees and independently reviewed, a client must **serialize all calls for a given handle through one owner boundary**.

For Flutter:
1. Create the engine on the owner boundary/isolate.
2. Route transport, track/device controls and telemetry polling through that same boundary.
3. Prevent overlapping calls unless the binding design serializes them.
4. Stop polling, await/cancel pending work, and destroy the handle exactly once during shutdown.
5. Never let a widget own/free a raw pointer.
6. Do not block the UI isolate on long work. If work must be offloaded, use an explicit command boundary that preserves the one-owner guarantee and does not compete with the audio callback.

Telemetry polling should have a bounded cadence (for example, a UI update interval), not a busy loop. Audio callbacks must remain independent of Flutter and must never wait for UI/FFI work.

## 7. Known gaps relative to the planned DAW UI

The current export inventory does **not** include a full session/project model, clip/region editing, seek/scrub, record inputs, recording lifecycle, MIDI, virtual instruments, effects chains, automation, plugin hosting, or export/mixdown API. Some of those features are planned but are not implied by this contract. Add functions only when the Rust engine has a correct implementation and API semantics; include failure paths and tests. Keep the UI visibly honest about not-yet-implemented features.

## 8. Binding maintenance rules

- `csbindgen` currently generates C# P/Invoke code into `apps/desktop/RouletteStudio.Desktop/NativeMethods.g.cs`; don't hand-edit generated C# output.
- Dart uses a separate `dart:ffi` adapter. `csbindgen` does not create Dart bindings.
- Consider adding a canonical C header to support tooling such as FFI binding generators after a dependency/licence/maintenance review. Until then, validate Dart signatures/layouts against the current Rust ABI implementation and compiled library.
- Every API change must update this file, the Flutter migration plan, any generated/maintained binding surfaces and relevant tests in the same change set.
- Add ABI tests for structure size/alignment and function behavior where feasible. Test library loading, missing library, incompatible API version, invalid handles, native errors, repeated lifecycle calls, and shutdown.
- Keep this contract accurate to source; do not write aspirational signatures as though they were exported.
