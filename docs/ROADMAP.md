# Aetherband Development Roadmap

## 1. Roadmap principles

Aetherband is being developed incrementally, with correctness and testable milestones taking priority over feature count. Implemented code is not considered complete merely because it exists: a phase is complete only when its acceptance criteria are reproducibly verified.

Priorities:

1. Stabilize and verify the existing audio engine and desktop integration.
2. Complete the recording, project, mixer, and export foundations.
3. Refresh the UI once those core workflows and APIs are stable.
4. Add MIDI, instruments, effects, and plugin hosting on top of the stable foundation.
5. Consider mobile as a separate effort after the desktop application is mature.

The current UI is intentionally retained during stabilization so it remains a known test surface. Do not begin a broad visual redesign during the current correctness pass.

## 2. Current status

**Current focus: Stabilization and verification of Phases 1–3.**

The repository already contains Rust audio-engine code and a C#/Avalonia desktop application, but the existence of these components does not mean the phases are fully verified. The current stabilization work must establish reliable builds, automated tests, decoder/transport lifecycle correctness, audio callback safety, and device-switching behavior before these phases can be marked complete.

Track status against evidence:
- **Implemented:** code exists.
- **In verification:** acceptance tests or runtime checks are still outstanding.
- **Complete:** every stated acceptance criterion has passed and the result is recorded.

Use `scripts/verify.ps1` on Windows PowerShell or `scripts/verify.sh` in Bash-compatible environments for the repository's automated formatting, build, and test checks. Also perform the manual audio-device and playback checks described below; a successful compile alone is not sufficient.

---

## 3. Phase breakdown

### Phase 0 — Planning and Repository Setup

- **Goal:** Establish the architecture, requirements, repository layout, and developer workflow.
- **Deliverables:**
  - Architecture and engineering documentation in `docs/`.
  - Windows and cross-platform toolchain instructions.
  - Repository structure, ignore rules, and contribution/AI workflow guidance.
- **Exit criteria:**
  - Architecture and development instructions reflect the actual implementation.
  - Required toolchains and verification commands are documented.
- **Status:** Baseline established; keep documentation aligned with implementation.

### Phase 1 — Real-Time Audio Core Foundation

- **Goal:** Provide a reliable Rust audio engine and real-time-safe processing path.
- **Deliverables:**
  - Rust workspace and `cpal` audio backend.
  - Audio-device enumeration and stream initialization.
  - Allocation-free callback processing with click-free gain ramping.
  - Bounded, lock-free SPSC queues for audio/control communication and metering.
  - Headless tests for callback behavior and real-time constraints.
- **Acceptance criteria:**
  - `cargo fmt --all -- --check`, `cargo check --workspace --all-targets`, and `cargo test --workspace --all-targets` pass in CI and locally.
  - A dedicated stress test processes at least 100,000 audio blocks without callback-time allocations or deallocations.
  - Callback execution stays within the agreed budget at a 128-sample buffer; record the test environment and measured results.
  - Queue-full, command rejection, track removal, processor replacement, and shutdown paths do not cause callback-time destruction, blocking, I/O, logging, locks, or unbounded work.
  - Tests cover zero-frame/end-of-stream blocks, full and partial final blocks, and supported output channel counts.
- **Status:** Implemented work is under stabilization; do not mark complete until the criteria are verified.

### Phase 2 — Desktop MVP and Cross-Language Integration

- **Goal:** Reliably connect the Rust engine to the C# Avalonia desktop app.
- **Deliverables:**
  - Native C ABI and platform-specific library outputs.
  - C# P/Invoke bindings, generated where appropriate.
  - Existing desktop controls for device selection, transport, master volume, meters, and audio playback.
- **Acceptance criteria:**
  - Rust native library and desktop application build using the documented scripts/toolchain.
  - Native library loading and ABI behavior are tested on the supported target platforms.
  - Playback, pause, stop, rapid volume changes, and clean application shutdown work without crashes, hangs, clicks, or unexpected dropouts.
  - Device selection and stream reinitialization do not leave stale track metadata, decoder handles, or invalid processor state.
  - CI results are green for the latest commit, not just an earlier commit in the branch.
- **Status:** Implemented work is under stabilization; verify with automated and manual tests.

### Phase 3 — Multi-Track Timeline and Disk Streaming

- **Goal:** Support reliable multi-track playback from disk and timeline navigation.
- **Deliverables:**
  - Background media decoding with `symphonia`.
  - Preallocated/bounded buffering between decoder workers and the audio callback.
  - Sample-accurate track playback and transport coordination.
  - Existing timeline and track controls, preserving the current UI during stabilization.
- **Acceptance criteria:**
  - Supported WAV, FLAC, MP3, OGG, and AAC files are tested, including corrupt files, EOF, resampling, and partial final blocks.
  - Stop, seek/reset, remove-track, rapid load/remove, queue backpressure, and device-switch scenarios have regression tests and do not deadlock or hang.
  - Decoder errors are surfaced safely and worker threads terminate reliably.
  - A repeatable performance test targets 16 stereo tracks at 48 kHz with smooth UI interaction; record actual CPU, buffer, and frame-rate measurements rather than treating target figures as already achieved.
- **Status:** Implemented work is under stabilization; feature/performance claims remain subject to test evidence.

### Phase 3.5 — Stabilization and Release Gate

- **Goal:** Close correctness gaps across Phases 1–3 before expanding the feature set.
- **Required work:**
  - Fix and regression-test Stop/Seek and decoder-buffer coordination.
  - Ensure callback-owned data can be reclaimed without callback-time allocation/deallocation or other unsafe work.
  - Correctly handle device changes, output sample-rate/channel changes, and failed track/command submissions.
  - Verify final-block handling and resampling-length calculations.
  - Run formatting, Rust checks/tests, .NET restore/build/tests, and the available CI workflows on the latest commit.
  - Test on the developer's Windows machine with real output hardware, including playback and clean shutdown.
  - Update engineering status with exact commands, outcomes, environment, and remaining known limitations.
- **Exit criteria:**
  - Required CI checks pass on the exact candidate commit.
  - Automated regression tests pass.
  - Manual hardware checks are recorded.
  - No unresolved P0 correctness or real-time safety issues remain.
- **Rule:** Do not start Phase 4 implementation work that depends on unstable transport/engine APIs until this gate is passed. UI planning may happen in parallel, but the existing UI remains unchanged.

### Phase 4 — Audio Recording, Mixer, Projects, and Export

- **Goal:** Make Aetherband useful for end-to-end audio production workflows.
- **Deliverables:**
  - Low-latency audio input recording with a background disk writer.
  - Mixer controls: faders, mute, solo, and documented pan law.
  - Project save/load format with project metadata and managed media assets.
  - Autosave, crash recovery, missing-media handling, and versioned project migrations.
  - Offline stereo WAV export, including documented bit depth and sample-rate behavior.
- **Acceptance criteria:**
  - Record external input, save a project, close/reopen the app, and verify track arrangement and playback.
  - Interrupted writes and invalid/missing assets fail safely and provide actionable feedback.
  - Exported files are validated for duration, channel count, sample rate, bit depth, and expected audio.
  - A three-minute arrangement export performance target is measured and recorded; do not claim the target until tested.
- **Prerequisite:** Phase 3.5 stabilization gate passed.

### UI Milestone — Design and UI Revamp

This is a dedicated milestone, not a reason to interrupt the current stabilization work.

- **Planning can begin during Phase 3.5:** document current screens, identify usability problems from real testing, establish interaction priorities, and prepare wireframes/design tokens without replacing the current UI.
- **Begin implementation after Phase 4's core project, transport, recording, and mixer APIs are stable, and before the main Phase 5 piano-roll/instrument/plugin workflows are built.**
- **Scope:**
  - Rework layout, navigation, hierarchy, spacing, typography, and reusable components.
  - Keep existing workflows available while migrating screens incrementally.
  - Design around real editing tasks and keyboard/mouse workflows, not appearance alone.
  - Preserve or add UI tests for transport, track management, recording, project save/load, mixer, and export.
  - Avoid changing audio-engine behavior as part of purely visual work.
- **Exit criteria:**
  - Core workflows can be completed without regressions.
  - UI remains responsive during playback and timeline interaction.
  - The design supports planned MIDI, instruments, effects, and plugin panels.
  - The previous UI or a reliable test build remains available until the new UI passes regression testing.

### Phase 5 — MIDI, Instruments, DSP Effects, and Plugins

- **Goal:** Expand from audio editing into a more complete production environment.
- **Deliverables:**
  - Sample-accurate MIDI event scheduling and piano roll.
  - Built-in polyphonic synthesizer and drum sampler.
  - Parametric EQ, compressor, delay, and reverb.
  - Plugin-hosting abstraction, starting with CLAP and adding VST3 after the hosting foundation is stable.
  - Automation and plugin-state persistence planned alongside the relevant systems.
- **Acceptance criteria:**
  - Record/import MIDI, edit and quantize notes, and play them through the built-in instruments.
  - Effect/plugin processing remains stable under playback, project save/load, and repeated enable/disable.
  - Plugin crashes or invalid states are isolated as far as the host architecture permits.
  - Plugin state and project compatibility are tested.
- **Prerequisites:** Phase 4 core workflows and the UI milestone are stable.

### Phase 6 — Native Mobile Companion (Separate Effort)

- **Goal:** Explore a mobile companion that reuses the Rust engine and opens compatible projects.
- **Prerequisites:** Desktop workflow is mature, project format is stable, and core engine APIs are suitable for reuse.
- **Possible deliverables:**
  - Separate mobile repository/workspace.
  - SwiftUI frontend for iOS/iPadOS and Kotlin/Jetpack Compose for Android.
  - Touch-first editing, drum pads, and mobile audio-session handling.
- **Exit criteria:** Define a focused mobile use case and platform-specific acceptance criteria before implementation begins. Mobile development must not delay desktop stability.

---

## 4. Definition of done for every phase

A phase is complete only when:

1. Its deliverables are implemented and documented.
2. Automated tests cover the key success and failure paths.
3. Formatting, build, and test commands pass on the candidate commit.
4. Required manual checks are recorded with the environment and results.
5. Known limitations and follow-up work are documented.
6. README and roadmap status agree with the evidence.

Do not use “implemented,” “merged,” or “the app launches” as a substitute for verified acceptance criteria.
