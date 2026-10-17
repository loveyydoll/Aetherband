# Aetherband Development Roadmap

> **Canonical extended backlog:** See [PRODUCT_ROADMAP.md](PRODUCT_ROADMAP.md) for the detailed, dependency-aware plan covering Flutter migration, C ABI/Dart FFI, project persistence, timeline editing, recording, MIDI, instruments, routing, effects, plugins, automation, export, testing, packaging and retirement of the transitional C# frontend.

> **Mandatory UI direction:** Flutter/Dart is the long-term desktop frontend through the Rust C ABI. C#/Avalonia is transitional and expected to be retired only after verified feature parity and owner approval.

## 1. Roadmap principles

Aetherband is being developed incrementally, with correctness and testable milestones taking priority over feature count. Implemented code is not considered complete merely because it exists: a phase is complete only when its acceptance criteria are reproducibly verified.

Priorities:

1. Preserve and verify the Rust engine's real-time correctness and the actual C ABI.
2. **Implement the Flutter/Dart desktop UI to full DAW scope through Dart FFI over the existing C ABI. This is an explicit owner decision and is mandatory, not an optional redesign.**
3. Connect Flutter to the real currently supported engine workflows, then close UI/engine feature gaps incrementally.
4. Keep C#/Avalonia buildable as a transition frontend until Flutter reaches feature parity and passes the documented migration/release gates; do not treat it as the permanent target.
5. Continue audio-engine feature work (projects, recording, MIDI, instruments, effects, automation, plugin hosting and export) with functionality exposed to Flutter through reviewed ABI additions.
6. Treat mobile as a separate future effort after the desktop product is mature.

The Flutter migration starts now and runs in parallel with engine stabilization where practical. Do not defer it until all future audio features have been implemented. Do not, however, call a mock UI production-ready or bypass test, ABI, ownership or real-time audio safeguards to accelerate the migration.

## 2. Current status

**Current focus:** Flutter desktop migration through the C ABI, alongside Rust engine correctness and verification.

PR #9 introduced the isolated Flutter workspace; PR #10 added the compact workstation menu, darker theme, responsive arrangement lanes and layout/assertion fixes. The Flutter workspace is still mock-only: the Dart FFI adapter, native-library packaging and real engine integration remain to be implemented. The current audio-connected desktop app is still the C#/Avalonia app, which is retained until parity.

Use [`FLUTTER_DESKTOP_MIGRATION.md`](FLUTTER_DESKTOP_MIGRATION.md) for the required target architecture, API limits and migration acceptance gates, and [`AI_HANDOFF.md`](AI_HANDOFF.md) for the exact work history and latest known verification.

Track status against evidence:
- **Implemented:** code exists.
- **In verification:** acceptance tests or runtime checks are still outstanding.
- **Complete:** every stated acceptance criterion has passed and the result is recorded.

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

### Phase 2 — Native Engine and C-ABI Baseline

- **Goal:** Reliably expose the Rust engine and preserve a working native-audio desktop client while the mandatory Flutter frontend is implemented.
- **Deliverables:**
  - Native C ABI and platform-specific library outputs.
  - C# P/Invoke bindings for the existing transition frontend, generated where appropriate.
  - Existing audio-connected controls for device selection, transport, master volume, meters, track loading and mixing.
  - Verified ABI function/struct contract and a separate Dart FFI adapter plan/client for Flutter.
- **Acceptance criteria:**
  - Rust native library and the existing transition desktop application build using the documented scripts/toolchain.
  - Native library loading and ABI behavior are tested on the supported target platforms.
  - Flutter has a dedicated testable Dart FFI client, using only real exports from `bindings/c_abi/src/lib.rs`; its work can progress alongside this phase.
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
  - Existing timeline and track controls in the Avalonia transition app, plus the Flutter UI migration path; Flutter must not pretend to have real audio before its native adapter is connected.
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
  - Run formatting, Rust checks/tests, transition-app restore/build/tests, Flutter analysis/widget/integration tests, and available CI workflows on the latest commit.
  - Test on Windows with real output hardware, including playback and clean shutdown.
  - Update engineering status with exact commands, outcomes, environment, and remaining known limitations.
  - Do not block Flutter UI engineering on unrelated future features, but do not declare its engine integration complete before engine/ABI correctness is verified.
- **Exit criteria:**
  - Required CI checks pass on the exact candidate commit.
  - Automated regression tests pass.
  - Manual hardware checks are recorded.
  - No unresolved P0 correctness or real-time safety issues remain.
- **Rule:** Do not start engine feature work that depends on unstable transport APIs until this gate is passed. Flutter UI/migration work may proceed in parallel using mock injection and the stable, already exported C ABI, but native integration must preserve the gate and API safeguards.

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

### Mandatory UI Milestone — Full-Scale Flutter Desktop Migration

**Owner decision (2026-10-17): mandatory target, not optional.** This milestone begins immediately and progresses in parallel with engine stabilization and Phase 4 where practical. Its position here groups frontend work in the roadmap; it does not mean the project should wait until all later audio features are finished to begin.

- **Goal:** Make Flutter/Dart the primary full-scale Windows/macOS desktop frontend using Dart FFI over the existing Rust C ABI.
- **Deliverables:**
  - Dedicated, injectable Dart engine-client/FFI adapter with ABI layout and error handling tests.
  - Platform-specific builds/packaging/loading of the native `daw_core` shared library.
  - Real engine-connected transport, device selection, audio-file loading, track removal/volume/pan/mute, master control, playhead and telemetry.
  - Production arrangement, library, instrument/effect panel, mixer, menu/shortcut, scaling, accessibility and error states.
  - Explicit integration for future engine features through reviewed ABI changes, rather than mock success.
- **Migration safety:** Keep the existing C#/Avalonia application buildable and audio-connected until Flutter reaches feature parity. Do not delete/disable Avalonia before review and acceptance.
- **Acceptance criteria:**
  - Real FFI calls use actual exports in `bindings/c_abi/src/lib.rs`; no undocumented/guessed functions.
  - Calls on one engine handle are serialized until the ABI proves safe concurrent access.
  - Mock data is injectable for widget tests but is not used as production audio.
  - Dart analysis, widget/integration tests, ABI layout/lifecycle checks, native build and Flutter Windows/macOS desktop builds pass on the candidate commit.
  - All currently supported audio workflows from Avalonia have equivalent tested Flutter workflows.
  - The owner reviews the new UI and the documented run/package path defaults to Flutter before migration is marked complete.
  - Avalonia retirement is a separate reviewed step after these criteria pass.
- **Reference:** [`FLUTTER_DESKTOP_MIGRATION.md`](FLUTTER_DESKTOP_MIGRATION.md).

---

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
