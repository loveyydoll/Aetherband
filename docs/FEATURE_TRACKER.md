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
| P0 | Windows audio output | Native sample formats, full callback buffers, surfaced stream errors, deferred cleanup and CPAL 0.18.2 stream lifecycle are implemented. Local Windows smoke produced nonzero HypnoSynth samples in the active WASAPI callback and closed cleanly. | Verify Flutter tests/build and physical listening. | Rust signal/callback tests and opt-in `AETHERBAND_AUDIO_SMOKE=1` Windows stream test pass; speaker/loopback listening remains unverified. |
| P0 | Flutter ↔ Rust integration | ABI 0.4.0 connects HypnoSynth, transport, master gain and solo through worker isolate to the Rust-owned engine thread. | Run Flutter widget tests and Windows app packaging. | Dart analysis and Rust ABI tests pass; Flutter runner is blocked by SDK path permissions. |
| P0 | Transport and mixer | Pause/Stop, tempo, metronome, phrase playback, master and per-track solo/mute/gain/pan are implemented. | Confirm device output, long playback, and queue/error recovery on hardware. | Automated Rust mixer and transport tests; physical listening remains. |
| P1 | Real session tracks and clips | New sessions are empty. Imported audio creates duration-scaled timeline clips and connects to native tracks; generic clip editing and MIDI regions remain unavailable. | Add editable regions and preserve their positions in sessions. | Current audio imports/session save-open are implemented; timeline drag still applies only to demo clips. |
| P1 | Import and playback workflow | Visible import/loading action, duration-scaled clips, unknown-duration labels, native inventory status and truthful errors. Windows WAV import/transport/remove and UI failure/cancellation/retry tests were added. | Verify more formats; add real waveform peaks and native clip editing. | [Local verification](VERIFICATION_2026-10-18.md). Current PR has Rust decoded-signal and WASAPI callback smoke evidence; physical listening and Flutter tests remain unverified. |
| P1 | Native audio mixer | Real imported-track volume/pan/mute/solo controls connect through Dart FFI to Rust; output meters consume engine telemetry. | Verify on Windows hardware and check Flutter tests. | Rust mixer signal test and Dart analyzer pass; widget execution is pending. |
| P1 | Project save/reopen | Schema v2 stores imported tracks, mixer state and synth/performance settings; schema v1 remains loadable; staged reopen avoids replacing a working session on validation failures. | Validate corruption recovery and native reopen in Flutter tests. | Store and UI tests authored; Flutter runner unavailable in this environment. |
| P1 | HypnoSynth | Original polyphonic synth, three authored presets, keyboard, macros, phrase, panic, tempo, metronome and persistence implemented. | Listen through physical output; add editable MIDI notes as a later slice. | Synth generates bounded nonzero output at 44.1/48/96 kHz in Rust tests; Flutter widget execution pending. |
| P1 | Stereo export | Not implemented; File menu reports the unsupported action. | Render/export a simple session to stereo WAV. | Output file is valid with expected duration, sample rate, channels and mixed content. |
| P2 | Editing quality | Waveforms, precise clip editing, undo/redo and automation are future work unless verified in code. | Deliver one useful editing workflow end-to-end at a time. | Acceptance criteria and model-level tests for each operation. |
| P2 | MIDI and instruments | HypnoSynth plays live keys and a generated phrase, but there is no editable MIDI data or MIDI clip persistence. | Add a minimal editable note/step sequence tied to an instrument region. | Real note events, arrangement timing, session persistence and playback tests. |
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
