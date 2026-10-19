# Aetherband — Project State Handoff

**Snapshot date:** 2026-10-19
**Latest local verification:** PR #33 includes the Windows audio repair, HypnoSynth, and DAW editing foundations. Rust workspace tests, callback-allocation, opt-in WASAPI output, Clippy, the release C ABI DLL, full Dart analysis, all 64 desktop Flutter tests and the Windows Release build pass locally. The opt-in native integration test also passes against the default Windows output device and reports nonzero arranged-pattern telemetry. Latest-head CI is running. Speaker/headphone audibility and microphone/line-in capture remain unverified.

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
- ABI 0.12.0 and Dart FFI carry transport seek, BPM and configurable 2–7/4 time signatures, synth, master gain, track solo state, imported-audio clip positions and source-bounded split/join/trim regions, editable 16-step HypnoSynth patterns scheduled as arrangement regions, HypnoSynth track gain/pan/mute/solo, offline stereo WAV export and Windows input recording. Session schema v6 saves pattern IDs, note/rest data and positions alongside one HypnoSynth track; schema v1 through v5 remain readable. Pattern clips support copy/cut/paste/duplicate and undo/redo for insertion, removal, movement and step-note edits. Sessions stage media in a fresh engine before replacing active state.
- Rust callback tests confirm audible generated and decoded signals; physical speaker or loopback listening still requires a user machine with an audio output.
- Windows recording uses the default input device and a background stereo PCM16 WAV writer; stopping finalizes and imports the take at the transport position. Input hardware behavior remains unverified.
- Live meters must use actual engine telemetry, not invented animation.
- Measured PCM/IEEE-float WAV waveforms load off the UI isolate and render from decoded peaks; unsupported audio formats show an explicit unavailable state. The Region menu splits, joins contiguous regions, and trims region starts/ends to the stopped playhead. These operations update native playback and persisted source ranges; audio clips also have drag handles for source-bounded edge trimming, with preview, native playback, session persistence and chronological undo/redo. One HypnoSynth instrument track can be added, renamed, deleted and persisted, with working mixer gain/pan/mute/solo. It has no independent MIDI regions or track-specific sequencer. MIDI regions, time stretching, Bounce in Place, effects, automation and plugin hosting remain incomplete. Imported audio clips can be moved and their start positions persist.

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
3. Add editable MIDI regions and MIDI data persistence; extend waveform editing and undo/redo.

## Current verification and uncertainty

On 2026-10-19, local verification passed for Rust audio/core/FFI and the complete desktop Flutter suite (64 passed) and Windows Release desktop build. The opt-in native integration test passed against the default Windows output device and observed nonzero arranged-pattern telemetry; the release DLL also emitted nonzero stereo pattern-region samples to the WASAPI callback through direct Dart FFI. CI is running for the current PR head. These results do not prove speaker/headphone audibility or successful microphone/line-in capture.

PR #33 remains open, mergeable and unmerged. New local edits must be published to the same PR and checked by remote CI; do not infer sound quality or hardware recording from callback/unit tests alone.
## Required handoff format

For each agent task, report **Implemented**, **Not implemented**, **Verified**, **Not verified**, **Known risks**, and **Next step**. Link the relevant PR/commit and checks when available.
