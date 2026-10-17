# Aetherband Feature Tracker

**Last reviewed:** 2026-10-17  
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
| P0 | CI and developer baseline | Recent status must be rechecked against current GitHub Actions. | Get Rust formatting/check/test and Flutter analysis/test/build checks green on the current mainline. | Exact successful run URLs and logs; no skipped required checks hidden. |
| P0 | Flutter ↔ Rust integration | FFI adapter/controller exists; integration is described as in progress. | Verify engine initialization, error display, transport state and clean disposal on supported desktop targets. | Widget/unit coverage plus manual Windows/macOS runtime notes. |
| P0 | Transport correctness | Stop/rewind regression fix is reported; preserve it. | Confirm Play/Pause/Stop and restart behaviour remain correct through UI and engine. | Regression tests and manual confirmation that Stop silences audio and resets/restarts correctly. |
| P1 | Real session tracks and clips | Timeline includes demo presentation models. | Establish a real track/clip state path instead of demo-only arrangement state. | Track/clip actions update the actual session model and survive view rebuilds. |
| P1 | Import and playback workflow | Engine has decoder/track-loading foundations; complete UI workflow needs verification. | Load an audio file, add it to a track, play it, remove it, and report failures clearly. | End-to-end manual test and regression tests for invalid media / failure paths. |
| P1 | Project save/reopen | Planned; do not assume complete. | Define the smallest useful session format and persist track/clip state safely. | Save, close, reopen and compare state; malformed/missing media handled safely. |
| P1 | Stereo export | Planned; do not assume complete. | Render/export a simple session to WAV after project and playback model support it. | Output file exists, is valid, expected duration/sample rate/channels verified. |
| P2 | Editing quality | Waveforms, precise clip editing, undo/redo and automation are future work unless verified in code. | Deliver one useful editing workflow end-to-end at a time. | Acceptance criteria and model-level tests for each operation. |
| P2 | MIDI and instruments | Planned; no feature parity claim. | First define a minimal instrument/MIDI vertical slice after core session workflows are coherent. | Real MIDI data, audible output, persistence and tests. |
| P2 | Effects and routing | Planned; no feature parity claim. | Add a small native effect/routing slice with clear CPU and signal-flow behaviour. | Signal-path tests, UI integration and documented limitations. |
| P3 | Spatial audio and advanced creative engine | Vision/experiment; not part of current critical path. | Revisit after core workflows and agent documentation are stable. | Separate scoped proposal, tests, performance constraints and user-facing acceptance criteria. |
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
