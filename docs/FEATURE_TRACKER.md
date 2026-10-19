# Aetherband Feature Tracker

**Last reviewed:** 2026-10-19
**Purpose:** Agent handoff and prioritization. This is not proof of runtime correctness; verify source and CI before changing a status.

## Status vocabulary

- **Verified:** implementation exists and the stated acceptance criteria have been tested with recorded evidence.
- **Implemented — unverified:** relevant code exists, but end-to-end behaviour or required platforms have not been verified.
- **Prototype:** visual or interaction demonstration; may use sample data and must not be represented as real engine functionality.
- **In progress:** active work exists but the feature is incomplete.
- **Planned:** not yet implemented.
- **Blocked:** cannot proceed until a named dependency or decision is resolved.

Do not promote a feature to Verified based only on a README claim, code presence, a merged PR, or a workflow definition.

## Current product priorities

The project is early alpha. Favor visible, end-to-end progress over speculative subsystems. Keep real-time audio safety, project data integrity and truthful UI behaviour as hard constraints.

| Priority | Area | Current understanding | Next useful outcome | Acceptance evidence |
|---|---|---|---|---|
| P0 | Windows audio output | Native sample formats, full callback buffers, surfaced stream errors, deferred cleanup and CPAL 0.18.2 stream lifecycle are implemented. Device switching restores synth/transport/mixer settings and rescales clip positions for the selected output rate; it stops playback and returns transport to the start. | Verify physical listening and device/error recovery on alternate hardware. | Latest local Rust workspace test suite passed, including callback-allocation and opt-in WASAPI smoke targets; nonzero samples reach the callback and an arranged pattern. Physical listening remains unverified. |
| P0 | Flutter ↔ Rust integration | ABI 0.11.0 connects HypnoSynth and independently scheduled 16-step arrangement patterns, transport seek, mixer, clip positioning and source-bounded split/join/trim regions, output-device selection, Windows input recording and stereo mixdown through the worker isolate to the Rust-owned engine thread. | Verify speaker output and device/error recovery on hardware. | Full local desktop Flutter suite passes (63 passed, 1 hardware integration test skipped); latest-head Windows CI is pending. Physical listening is unverified. |
| P0 | Transport and mixer | Space-bar play/pause and R record shortcuts, Home/Go to Start outside recording, Stop, bar and timeline seeking, tempo, metronome, phrase playback, master and per-track solo/mute/gain/pan are implemented. | Confirm device output, long playback, and queue/error recovery on hardware. | Generated-WAV decoder seek test, in-playback FFI seek test, automated Rust mixer/transport tests and Windows navigation widget test; physical listening remains. |
| P1 | Real session tracks and clips | New sessions are empty. Imported audio creates duration-scaled timeline clips, snaps to quarter-note beats by default with a free-placement toggle, supports native-backed rename/duplication, copy/cut/paste and Delete-key removal while preserving mixer state, persists names and source-bounded regions, and has a working Zoom to Fit action. Split tracks retain their regions through copy/paste and duplication. One HypnoSynth arrangement track supports independently scheduled, movable, deletable, copyable, pasteable and duplicatable 16-step pattern regions with persisted notes and positions in schema v6, plus track gain/pan/mute/solo. | Add independent MIDI tracks, stretch resizing and standard MIDI interchange. | Rust real-time/offline pattern scheduling and the C ABI pass locally; full local Flutter suite passes. Latest-head Windows CI is pending. |
| P1 | Import and playback workflow | Visible import/loading action, duration-scaled clips, measured PCM/IEEE-float WAV peak rendering, a loading state and explicit unavailable state for unsupported waveform formats, native inventory status and truthful errors. Imported clips can move when stopped at the start and audio tracks can be renamed or copied/cut/pasted/duplicated/deleted with rollback on setup failure; selected clips split, join adjacent source-contiguous regions and trim to the stopped playhead; Zoom to Fit uses arrangement content. Pattern clips now support copy/cut/paste/duplicate shortcuts as well. | Verify more waveform formats; implement editable MIDI regions and stretch resizing. | Earlier CI passed region split/join/trim and persistence tests; latest pattern edit widget test and current-head Windows CI remain pending. Physical listening remains unverified. |
| P1 | Native audio mixer | Real imported-track volume/pan/mute/solo controls connect through Dart FFI to Rust; output meters consume engine telemetry. | Verify on Windows hardware. | Rust mixer signal tests, Windows Dart analysis and Flutter widget tests pass locally; physical listening remains separate. |
| P1 | Project save/reopen | Schema v6 stores imported tracks, mixer state, synth/performance settings, each audio clip's timeline/source range, the HypnoSynth track identity/mixer state, and pattern notes/positions; schemas v1 through v5 remain loadable; staged reopen avoids replacing a working session on validation failures. | Add MIDI region serialization and validate audio playback on physical output. | Existing Windows Flutter CI passed earlier schema/migration tests; latest schema-v6 and pattern widget checks are pending current-head CI. |
| P1 | HypnoSynth | Original polyphonic synth, three authored presets, keyboard, macros, editable 16-step sequence, panic, tempo, metronome and persistence implemented. It now has a named session track with gain/pan/mute/solo and arrangement patterns with copy/cut/paste/duplicate, including offline mixdown and schema-v6 state. | Listen through physical output; add independent MIDI tracks and standard MIDI interchange. | Rust signal and scheduler tests pass; latest pattern edit widget checks and current-head Windows CI are pending. Human listening remains unverified. |
| P1 | Windows input recording | Implemented — unverified: captures the default input into a new stereo PCM16 WAV on a background writer; Stop finalizes the file and adds it as an arrangement track at the transport position. | Verify default input stream and sustained capture on Windows hardware; inspect queue drops. | Synthetic writer/WAV-header unit test, Rust build, ABI layout/null checks and Flutter widget checks; real input capture not run. |
| P1 | Stereo export | Implemented offline stereo PCM16 WAV render from imported tracks and current performance settings, or an eight-bar phrase-only arrangement. Rejects unknown-duration tracks and source-overwrite destinations. | Verify on varied audio files and Windows devices. | Core tests check header, sample rate, stereo format, mixed audio, sequence-only rendering and overwrite protection; File-menu widget test and real Windows Dart FFI export pass. |
| P2 | Editing quality | Measured WAV waveforms and clip movement are implemented. The Region menu splits, joins contiguous regions and trims start/end to the playhead through native source ranges. Undo/redo is chronological across these actions and clip moves. HypnoSynth patterns now support copy/cut/paste/duplicate; edits are reflected in the native scheduler and session dirty state. | Add pattern clipboard undo and stretch resize. | Rust source-range decoding, local split/join/trim history UI checks, and local pattern copy/paste/duplicate/cut tests pass; latest-head CI is pending. |
| P2 | MIDI and instruments | HypnoSynth now plays live keys and a persisted editable 16-step note sequence. Full MIDI regions, MIDI file import/export and MIDI clip editing are not implemented. | Add MIDI regions and standard MIDI file import/export; the current sequencer is instrument performance data. | Real note events, arrangement timing, session persistence and playback tests. |
| P2 | Effects and routing | Planned; no feature parity claim. | Add a small native effect/routing slice with clear CPU and signal-flow behaviour. | Signal-path tests, UI integration and documented limitations. |
| P2 | Typed graph foundation | Control-thread graph model added on the engine-foundation branch; not yet connected to DSP callback or compiled runtime. | Add immutable validated graph snapshots and off-thread compilation after playback is verified. | Unit tests for port compatibility, cycle detection and processing order; later runtime signal-path tests. |
| P3 | Aether Patcher | Future separate visual-programming application; not current DAW priority. | Keep as a future product direction; don't create an unrelated subsystem or repository without explicit direction. | Separate scope decision when the DAW foundation is ready. |

## How to take a task

Before starting, create or select a task with:
- **User outcome:** what a musician can do after the change.
- **Scope:** exact modules/files likely to change and explicit exclusions.
- **Dependencies:** existing APIs or prior work required.
- **Acceptance criteria:** observable, testable statements.
- **Verification plan:** commands, tests, platforms and manual checks.
- **Risk:** especially audio callback, FFI ownership, transport, session data or UI state.
- **Status and evidence:** link to PR/commit and successful checks when available.

Agents should select the highest-priority unblocked task that fits the current request. Do not start several overlapping large features in parallel. Ask the owner only when a product decision genuinely blocks progress.

## Completion update

After each meaningful task, update the relevant status with:
- exact implementation location;
- current status using the vocabulary above;
- tests/checks run and result;
- missing verification and known risks;
- next logical task.

Keep this tracker concise. Detailed architecture belongs in the architecture/API docs; durable rationale belongs in decisions; release history belongs in the changelog.
