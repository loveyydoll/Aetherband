# Aetherband Feature Tracker

**Last reviewed:** 2026-10-18
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
| P0 | CI and developer baseline | Formatting failures in graph/core source repaired; local Rust format/check/test/build and Flutter analysis/tests/Windows build pass. Existing Clippy findings remain. CI must be rechecked on the PR. | Establish green platform CI and address remaining lint findings separately. | [Local verification](VERIFICATION_2026-10-18.md); successful current CI run URLs still required. |
| P0 | Flutter ↔ Rust integration | ABI 0.3.0 adds source metadata. Calls run on a Dart worker; a dedicated Rust thread owns the engine through shutdown. Windows native test passes; macOS unverified. | Verify macOS library loading, import and lifecycle. | Rust ownership/layout tests, Flutter widget tests and Windows native integration test; see verification record. |
| P0 | Transport correctness | Stop/Pause callback regressions and Windows native Pause/Stop/restart telemetry tests pass. | Confirm physical output silence/restart and device behavior manually on both supported systems. | Automated evidence exists; independent audio capture/listening and macOS runtime checks remain. |
| P1 | Real session tracks and clips | Timeline includes demo presentation models. | Establish a real track/clip state path instead of demo-only arrangement state. | Track/clip actions update the actual session model and survive view rebuilds. |
| P1 | Import and playback workflow | Implemented: visible import/loading action, duration-scaled clips, unknown-duration labels, native inventory status and truthful errors. Windows native WAV import/transport/remove and UI failure/cancellation/retry tests pass. | Verify more formats and macOS; add real waveform peaks and native clip editing. | [Local verification](VERIFICATION_2026-10-18.md). Import rewinds transport; demo content remains; persistence and imported mixer editing are not implemented. |
| P1 | Native audio mixer | Proposed code connects imported track volume/pan/mute to Rust through Dart FFI and adds a visible scrolling mixer (pending CI; solo remains unavailable). | Verify native DSP response, queue failures, and real hardware on Windows/macOS; add solo and session persistence separately. | Widget tests, optional native integration and Rust muted-stream regression added; no CI/runtime results claimed yet. |
| P1 | Project save/reopen | Implemented in this PR (pending CI): v1 audio-only JSON file, real imported track sources/IDs, gain/pan/mute, and staged native reimport. Existing demo clips and future editing are not persisted. | Validate native reopening on both desktop platforms; add media relinking, bundled assets and real clip state later. | Session-store round-trip/corruption/missing-source tests and File-menu widget integration added; CI and hardware still required. |
| P1 | Stereo export | Planned; do not assume complete. | Render/export a simple session to WAV after project and playback model support it. | Output file exists, is valid, expected duration/sample rate/channels verified. |
| P2 | Editing quality | Waveforms, precise clip editing, undo/redo and automation are future work unless verified in code. | Deliver one useful editing workflow end-to-end at a time. | Acceptance criteria and model-level tests for each operation. |
| P2 | MIDI and instruments | Planned; no feature parity claim. | First define a minimal instrument/MIDI vertical slice after core session workflows are coherent. | Real MIDI data, audible output, persistence and tests. |
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
