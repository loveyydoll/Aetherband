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
- Rust formatting, all workspace tests (39 core, 1 real-time allocation, 6 ABI), Windows C ABI release build, core Clippy and opt-in WASAPI smoke pass. Flutter test/build and the latest Dart formatter/analyzer invocations are blocked locally because the SDK stalls while accessing its installation outside the approved writable root; the single PR's Windows CI remains the fallback.
- Still outstanding: Flutter widget tests and Windows app build on an approved SDK, physical Windows output/listening, and review of CI after opening one PR. Recording, stereo export, editable MIDI, waveform display, split/trim/resize and undo/redo remain incomplete and must be labeled that way.
