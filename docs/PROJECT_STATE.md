# Aetherband — Project State Handoff

**Snapshot date:** 2026-10-19
**Evidence level:** Windows Rust tests, C ABI build, core Clippy and Dart analysis pass for the current branch. An opt-in WASAPI smoke test produced nonzero HypnoSynth callback samples and shut down cleanly. Flutter test execution is blocked locally by SDK lockfile access; speaker listening/loopback capture is not independently verified.

## Product identity

Aetherband is an early-alpha, open-source desktop DAW. Its long-term direction is an arrangement-first creative workspace that combines production, precise editing, mixing and future extensibility. Aether Patcher is a possible future separate visual-programming application, not the current implementation priority.

## Current architecture

- **Desktop UI:** Flutter/Dart in `apps/desktop/`.
- **Audio engine/DSP:** Rust in `core/`.
- **Interop:** versioned C ABI in `bindings/c_abi/`, consumed through Dart FFI.
- **Audio I/O/decoding:** Rust engine components using the existing audio/device and decoder stack.
- **Target desktop platform:** Windows only by current owner direction; other platforms are deferred.

Do not reintroduce C#/.NET/Avalonia as a second desktop frontend. Verify current project files before changing build scripts, APIs or dependency versions.

## Known implementation boundaries

- The launch arrangement is a real empty session rather than six visual demo tracks. Imported audio remains duration-aware and native playback is routed to the default Windows device using its native sample format.
- The real-time Rust callback now renders imported tracks and HypnoSynth, supports full oversized buffers, and defers decoder/player reclamation to the control thread. Device stream errors are surfaced through telemetry.
- HypnoSynth is an original polyphonic instrument with three original presets, live keyboard input, tempo/metronome, and a generated phrase. Its musical references do not use copied recordings or claim to recreate a specific patch.
- ABI 0.6.0, Dart FFI and session schema v3 carry synth, transport, master gain, track solo state, imported-audio clip positions, and offline stereo WAV export. Sessions stage media in a fresh engine before replacing active state; schema v1 and v2 remain readable.
- Rust callback tests confirm audible generated and decoded signals; physical speaker or loopback listening still requires a user machine with an audio output.
- Record UI controls must not imply actual recording unless a real recording path exists.
- Live meters must use actual engine telemetry, not invented animation.
- MIDI editing/recording, stereo export, effects, automation, plugin hosting, waveform rendering, split/trim/resize, undo/redo and device selection remain incomplete; imported audio clips can be moved and their start positions persist.

## Critical invariants

1. Preserve the reported Stop/rewind fix. A UI playhead reset is not proof that audio stopped; verify engine result and playback silence.
2. Never perform blocking I/O, blocking locks, sleep, logging, unbounded work or routine heap allocation/destruction in the real-time audio callback.
3. Keep Flutter responsive; long-running work and file/device operations must not block the UI isolate.
4. Keep Rust exports, C ABI declarations, Dart FFI signatures, ownership and error semantics synchronized.
5. Never silently represent an unsupported/failed native operation as success.
6. Treat session/media data as user work: avoid destructive changes and preserve recoverability.

## Current priorities

See [Feature Tracker](FEATURE_TRACKER.md) for the living backlog. Initial order:
1. Listen to HypnoSynth and imported audio through actual Windows output hardware.
2. Add real stereo export and input recording as separately tested vertical slices.
3. Add waveform/clip editing, undo/redo and MIDI data persistence.

## Known uncertainty

The current local Rust workspace tests pass (39 core, one callback safety and six ABI tests), as do Rust formatting, Windows C ABI build and core Clippy. An opt-in default-device test confirms nonzero HypnoSynth samples reach the WASAPI callback and stream shutdown succeeds. On PR head `00e99cd`, Windows CI passed Dart analysis, 27 Flutter widget tests, the Windows debug build, and Rust formatting/check/tests. One native-device Flutter integration test is skipped in CI because it requires an audio output device. Local Dart tool invocations stalled without output; physical listening remains unverified.

This document is not a runtime test report. It does not independently prove current CI status, device behaviour, audio output, persistence, export or platform packaging. Use current GitHub Actions logs and local results. Update this snapshot when evidence changes, and date it when a new status review is performed.

## Required handoff format

For each agent task, report **Implemented**, **Not implemented**, **Verified**, **Not verified**, **Known risks**, and **Next step**. Link the relevant PR/commit and checks when available.
