# Native C++/JUCE Migration Plan

**Status:** In progress · **Target platforms:** Windows and macOS · **Binding decision:** ADR-008 in DECISIONS.md

## Purpose

Replace the Rust/Flutter/Dart target architecture with a native C++/JUCE desktop application. This is a deliberate architectural migration, not permission to erase the old implementation before its behavior is understood and the replacement is proven.

## Binding rules

- New target product work uses C++20+ and JUCE, built with CMake.
- Windows and macOS are mandatory; both require independent build and runtime evidence.
- Aetherband owns DSP graph execution, processor lifecycle, routing, transport, parameter/automation semantics, and offline-rendering rules.
- JUCE provides application/audio/platform infrastructure; it is not a substitute for engine design.
- Preserve Rust/C ABI/Flutter/Dart as a reference until the new target passes acceptance criteria. Do not bulk-delete it.
- Do not mechanically translate Rust code. Audit behavior, tests, assumptions, licensing, and platform constraints first.
- C# is not part of the core migration.

## Stage 0 — Audit and migration map

Inventory legacy engine modules, UI workflows, tests, project formats, dependencies, and known defects. Distinguish source-level behavior from automated tests, offline tests, and physical-device evidence. Record migration mappings for transport, mixer, media, sessions, instruments, and export.

**Exit:** auditable behavior matrix and no unsupported parity claims.

## Stage 1 — JUCE platform proof

Integrate JUCE through a documented, reproducible CMake setup. Build and launch a minimal native window on Windows and macOS. Enumerate devices, open/close a stream, and render a known test signal. Verify repeated start/stop/close, device errors, and clean shutdown. Record JUCE version, modules, licence implications, and platform prerequisites.

**Exit:** successful builds and recorded device/runtime checks on both platforms. A compile alone is insufficient.

## Stage 2 — Core audio contracts

Define audio-buffer, sample-rate, block-size, channel-layout, parameter, transport, and processor lifecycle contracts. Establish bounded command/telemetry flow with documented overflow behavior. Implement an audio runtime whose callback performs bounded processing only. Add deterministic unit and offline audio tests.

**Exit:** known-signal offline tests pass; callback path is reviewed for allocations, blocking, I/O, and unsafe destruction; device lifecycle is verified on both OSes.

## Stage 3 — Executing DSP graph

Implement processor interfaces, graph validation, channel compatibility, and actual sample processing. Add gain/pan, summing, routing, parameter changes, and graph lifecycle. Define safe graph updates during playback and offline-render semantics.

**Exit:** offline golden-signal tests cover routing and edge cases; invalid graphs fail safely; graph updates do not destroy live callback-owned state.

## Stage 4 — First usable DAW vertical slice

Implement a versioned session model and native save/open flow. Import WAV using background media work. Arrange and play multiple tracks; mix; save and reopen; export stereo WAV. Build a functional JUCE shell with menus, arrangement, and mixer sufficient for this workflow.

**Exit:** import → arrange → playback/mix → save → reopen → export succeeds end-to-end on Windows and macOS, with failure-path tests and documented limitations.

## Stage 5 — Instruments and production features

Port HypnoSynth with regression fixtures and state tests. Add MIDI event/piano-roll foundations, recording, effects, routing, automation, undo/redo, and recovery in small slices. Test additional formats individually; WAV success does not imply FLAC/MP3 support.

**Exit:** each feature has repeatable tests and a clear support statement.

## Stage 6 — Hardening and ecosystem

Profile realistic sessions, stress test, improve accessibility and keyboard workflows, package both platforms, and audit dependencies/licenses. Evaluate plugin hosting and interchange only after the core workflow is stable.

**Exit:** reproducible builds, published platform support matrix, no known critical data-loss/audio-safety defects, and clear release documentation.

## Real-time constraints

No file/network I/O, unpredictable allocation/deallocation, blocking waits, contended mutexes, decoding, resampling, graph compilation, or complex object destruction in the audio callback. Prepare resources away from the callback and document safe handoff and retirement.

## Definition of done

A migration task must include relevant tests, commands and results, platform coverage, known limitations, and updates to FEATURE_TRACKER.md and PROJECT_STATE.md when status changes.
