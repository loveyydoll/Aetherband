# Audio and HypnoSynth implementation

Requested outcome: one PR restoring audible music creation in the existing Flutter workspace, with HypnoSynth and the essential DAW controls that currently remain presentation-only.

Working branch: `feat/hypnosynth-daw-foundations`, based on main `caa70b5`.
Checkout: this `overnight/` directory. The Desktop checkout has pre-existing merge conflicts and must not be modified.

## Acceptance plan

1. Audio: device sample formats, full callback buffers, surfaced device errors, Stop/Pause/restart, deferred resource reclamation, and decoded-file signal tests.
2. HypnoSynth: native polyphonic oscillator/filter/envelope/modulation/delay instrument, original atmospheric and tense post-punk presets, playable keyboard, panic, and persistence. Musical references are inspiration, not sampled recordings or a claim to reproduce a specific patch.
3. DAW essentials: real empty session, master gain, solo, tempo/metronome, project safety, useful MIDI/sequence creation and stereo export as coherent vertical slices. Audit remaining defaults explicitly rather than claiming commercial DAW parity.
4. Verification: Rust format/check/test/Clippy, Flutter analysis/tests, Windows build and native signal testing; CI on the single PR. Physical listening needs separate evidence. Windows is the only current target; other platforms are deferred by owner direction.

## Initial evidence

- Main opens six visual demo tracks with no native audio sources. Instrument knobs and presets are presentation-only.
- Device backend always requests f32 despite reading the device's default format.
- Callbacks over 2048 frames discard the tail while advancing the full transport duration.
- Stream restart and decoded-block replacement free heap resources in the audio callback.
- CPAL 0.15.3 could open the local WASAPI default output, but the process crashed with Windows `STATUS_INVALID_HANDLE` during stream teardown.
- Baseline Windows `cargo test --workspace --all-targets`: 33 core tests, one callback allocation test and six FFI tests passed. Existing allocation test does not exercise real stream turnover/restart.

SoundCraft reuse is authorized; only its ADSR envelope was adapted, and upstream attribution plus MIT license text are tracked in `third_party/soundcraft/`. Rust and Dart/Flutter are retained because audio DSP/CPAL has a concrete fit in Rust and the UI already uses Flutter; no extra language offered a clear advantage for this vertical slice.

## Current implementation status

- Fixed output conversion for common Windows CPAL default sample formats, callback overflow tail loss, stream-error telemetry, and callback-thread decoder/player destruction.
- Added Rust HypnoSynth with three authored presets, real note events/macros/phrase/metronome/master controls, a 13-note pointer/computer keyboard, and persisted settings.
- Replaced the initial fake arrangement with an empty session; connected mixer solo and v3 audio session persistence for imported tracks, clip positions and synth settings. Imported clips can move on a quarter-note grid while stopped at the start; v1 and v2 sessions default clip position to zero.
- Upgraded CPAL to 0.18.2 and adapted its stream/device API. On this Windows machine, a real default-device stream remained active, played a quiet HypnoSynth note with nonzero callback peaks (L 0.0058, R 0.0048; no reported device error), paused, and shut down cleanly. This verifies nonzero audio reached the active WASAPI callback; physical listening/loopback capture remains unverified.
- Preserved that hardware check as an opt-in Windows integration test: set `AETHERBAND_AUDIO_SMOKE=1` and run `cargo test -p daw_core --test windows_audio_smoke -- --nocapture`. It passed locally; default CI skips device access.
- Stereo export is now implemented as offline 16-bit PCM WAV, with imported-track mixing and an eight-bar HypnoSynth-only phrase option. It honors clip starts, track gain/pan/mute/solo, master gain, tempo and metronome without seeking or pausing live playback; it rejects unknown-duration sources and refuses to overwrite a source recording. The native worker, C ABI 0.6.0, Dart FFI and File menu are connected.
- The Windows Audio menu now lists available output devices and switches the native stream using the existing C ABI; the Dart adapter refreshes its sample rate after switching. The status bar identifies a selected device and describes this build as Windows only.
- Current local checks: Rust format, 43 core tests, one real-time allocation test, 7 ABI tests, core Clippy and Windows release C ABI build pass. Flutter analysis reports no issues; all 30 Flutter tests pass with the freshly built native DLL and local default output device enabled. That end-to-end integration test enumerated and selected the default WASAPI device, then verified track playback telemetry and stereo WAV export through Dart FFI. The Windows desktop debug executable builds. Nonzero samples reached the WASAPI callback, but physical listening/loopback capture remains unverified.
- Device-switch state restoration was added after the output-selector release: it reapplies tempo, metronome, sequence, synth preset/macros, and master gain to the new processor, and rescales clip start positions and cached metadata when the output sample rate changes. The Dart/native integration test now plays a sequence after switching to verify restored synth/transport state.
- Latest local verification: `cargo fmt --all -- --check`, `cargo test --workspace --all-targets` (43 core, 7 ABI, realtime safety), `AETHERBAND_AUDIO_SMOKE=1 cargo test -p daw_core --test windows_audio_smoke -- --nocapture`, `cargo clippy --workspace --all-targets`, release C ABI build, full Flutter suite (30 tests), and the focused native FFI integration test all passed. Clippy emits existing missing-`# Safety` documentation warnings in the C ABI; `-D warnings` therefore fails. The native integration test enumerated and selected the default WASAPI device, played the restored sequence, exercised imported audio/export, and shut down cleanly.
- Remote CI passed on output-selector head `b874f43`: Rust and Windows Flutter workflows passed, including native build, Dart analysis, widget tests and Windows desktop build. State-restoration commits `4471ee7` and `c9dfabf` are now on the same PR branch; their Rust and Flutter workflows are running. The local WASAPI integration test previously enumerated and selected the default device before playback/export, and the audio smoke test passed again in this pass. Physical listening/loopback remains unverified. Recording, editable MIDI, waveform display, split/trim/resize and undo/redo remain incomplete and must be labeled that way.
