# Aetherband Roadmap — Versioned Alpha

This roadmap is organized as versioned delivery milestones instead of broad development phases. A version is a target scope, not evidence that its features are already complete. Mark a milestone complete only after its acceptance gates pass on the current commit.

## Product architecture decision

- **Desktop UI:** Flutter + Dart.
- **Native audio engine:** Rust.
- **Interop:** versioned C ABI in `bindings/c_abi/`, consumed by a single Dart FFI adapter.
- **Removed target:** C#/.NET + Avalonia is not a supported target for future desktop development. Its frontend is being retired in favor of Flutter.
- **Platform targets:** Windows and macOS first. Keep OS-specific native library packaging explicit.

The migration is driven primarily by custom UI flexibility and control over timeline/rendering optimization, plus rapid design iteration, a consistent cross-platform UI, and a cleaner native-engine boundary. Flutter is not presumed faster without measurements.

## Alpha 0.1 — Flutter Engine Connection

**Goal:** Replace the mock transport with a real Flutter-to-Rust control path.

Deliverables:
- Dart FFI declarations match the actual exported C ABI, including struct layouts and integer widths.
- Native library discovery/loading for supported platforms with actionable errors.
- API-version check and native return-code handling.
- Safe engine lifecycle: create once, serialize calls, stop and destroy cleanly.
- Connect transport, test tone, telemetry/meters, device enumeration/selection, and basic track operations where supported by the current ABI.
- Remove the Avalonia/.NET desktop app, generated C# bindings, and .NET-only CI path after replacement checks are in place.
- CI runs Flutter analyze/tests and Rust format/check/test/build.

Acceptance gates:
- Windows and macOS native library loads and ABI smoke tests pass.
- FFI struct size/alignment/field layout is validated against Rust.
- No native calls race destruction; no long native work blocks the Flutter UI isolate.
- Missing library, incompatible API version, and negative return codes appear as visible errors.
- No mock telemetry or simulated recording is presented as actual audio.
- Manual playback/device tests are recorded separately from unit tests.

## Alpha 0.2 — Audio Import & Session Basics

- File picker and native audio-track loading/removal.
- Real track inventory and transport state.
- Versioned project/session schema and save/load.
- Missing-file resolution and recovery UI.

Acceptance: load/play/pause/stop/remove tests; project round-trip and malformed-project tests; no silent data loss.

## Alpha 0.3 — Arrangement & Waveforms

- Real waveform peak generation and cache invalidation.
- Arrangement zoom, scroll, clip selection and non-destructive move/split.
- Virtualized timeline rendering for large sessions.
- Keyboard/mouse interaction and accessibility.

Acceptance: timeline model tests, large-session performance profiles, Windows/macOS DPI and resizing tests.

## Alpha 0.4 — Recording & Export

- Audio input/device selection and recording state machine.
- Background recording writer and recoverable takes.
- Offline WAV mixdown/export with progress and cancellation.

Acceptance: device/interruption tests, write-error recovery, exported-audio regression tests.

## Alpha 0.5 — Mixing Workflow

- Track and master gain/pan/mute/solo.
- Real meters and a coherent mixer panel.
- Undo/redo foundation, shortcuts, preferences and device status.
- Routing/buses/sends only when supported by engine design and tests.

Acceptance: mixer correctness and stress tests at documented track counts; no UI updates at unbounded frequency.

## Alpha 0.6 — MIDI & Built-in Instruments

- MIDI event model and editing.
- Piano roll and MIDI recording/input.
- Native synth, sampler and drum-machine foundations.

Acceptance: deterministic project persistence, MIDI timing and event-editing tests.

## Alpha 0.7 — Effects & Automation

- Built-in audio effects and parameter state.
- Sample-accurate or explicitly bounded automation.
- Presets and parameter serialization.

Acceptance: DSP tests, automation timing tests, CPU-budget measurements.

## Alpha 0.8 — Plugin Hosting & Interchange

- Evaluate CLAP first; evaluate VST3 support and licensing requirements separately.
- Plugin scanning, validation, crash containment and compatibility matrix.
- Interchange formats and project portability improvements.

Acceptance: architecture and legal review; third-party plugin failures must not corrupt project state or silently compromise audio safety.

## Alpha 0.9 — Performance & Release Candidate

- Profile CPU, memory, UI frame times, loading, waveform rendering and audio callback budget.
- Accessibility, keyboard navigation, installers/signing, crash diagnostics and docs.
- Project compatibility policy and release-candidate triage.

Acceptance: reproducible stress tests on supported OS versions, release checklist, no known critical data-loss or audio-safety defects.

## 1.0 — Stable Desktop DAW

- Documented and supported production workflows.
- Stable project-format policy, installer/update process and contribution guide.
- All release gates pass on the declared Windows/macOS matrix.

## Rules for status updates

Use only these status labels:
- **Planned:** not implemented.
- **In progress:** implementation exists but acceptance criteria are incomplete.
- **Implemented, unverified:** code exists but automated/manual evidence is incomplete.
- **Verified:** stated acceptance criteria passed on the current commit, with evidence recorded.

Never mark a version complete merely because its UI mock or native function exists.
