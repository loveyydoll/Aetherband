# Aetherband — Project State Handoff

**Snapshot date:** 2026-10-19
**Evidence level:** Windows Rust workspace tests, C ABI build, core Clippy and Dart analysis pass for the current branch. An opt-in WASAPI smoke test produced nonzero HypnoSynth callback samples and shut down cleanly. Flutter analysis and all 40 tests pass locally; a separate Windows Dart FFI integration test passes against the release DLL; speaker listening/loopback capture is not independently verified.

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
- The real-time Rust callback now renders imported tracks and HypnoSynth, supports full oversized buffers, and defers decoder/player reclamation to the control thread. Device stream errors are surfaced through telemetry. Space toggles play/pause and R toggles recording through the native engine.
- HypnoSynth is an original polyphonic instrument with three original presets, live keyboard input and a persisted, editable 16-step sequence with tempo/metronome playback. Its musical references do not use copied recordings or claim to recreate a specific patch.
- ABI 0.8.0, Dart FFI and session schema v3 carry synth, transport, master gain, track solo state, imported-audio clip positions, the editable 16-step synth sequence, offline stereo WAV export and Windows input recording. Sessions stage media in a fresh engine before replacing active state; schema v1 and v2 remain readable.
- Rust callback tests confirm audible generated and decoded signals; physical speaker or loopback listening still requires a user machine with an audio output.
- Windows recording uses the default input device and a background stereo PCM16 WAV writer; stopping finalizes and imports the take at the transport position. Input hardware behavior remains unverified.
- Live meters must use actual engine telemetry, not invented animation.
- Measured PCM/IEEE-float WAV waveforms load off the UI isolate and render from decoded peaks; unsupported audio formats show an explicit unavailable state. Undo/redo covers clip moves; general editing history, MIDI editing, effects, automation, plugin hosting and split/trim/resize remain incomplete. Imported audio clips can be moved and their start positions persist.

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
2. Verify input recording with a real Windows microphone/line-in device and listen to output through speakers.
3. Add waveform/clip editing, undo/redo and MIDI data persistence.

## Current verification and uncertainty

On 2026-10-19, published commit `68f212a` passed both Windows CI workflows. Local Windows checks pass for the current working tree: Rust workspace tests (47 core, 8 ABI, callback-allocation and WASAPI smoke target), Clippy, release DLL build, Flutter analysis and 45 Flutter tests, plus the focused Dart FFI integration test against the release DLL and default output device. The WASAPI smoke produces nonzero callback samples. These results do not prove audible output through speakers or successful microphone/line-in capture. Clippy passes with existing missing-`# Safety` documentation warnings in C ABI exports.

PR #33 remains open and unmerged. New local edits must be published to the same PR and checked by remote CI; do not infer sound quality or hardware recording from callback/unit tests alone.
## Required handoff format

For each agent task, report **Implemented**, **Not implemented**, **Verified**, **Not verified**, **Known risks**, and **Next step**. Link the relevant PR/commit and checks when available.
