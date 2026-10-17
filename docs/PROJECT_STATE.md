# Aetherband — Project State Handoff

**Snapshot date:** 2026-10-17  
**Evidence level:** documentation/source inspection only unless a command or CI run is explicitly linked below. Recheck the current branch, PRs and Actions before relying on this snapshot.

## Product identity

Aetherband is an early-alpha, open-source desktop DAW. Its long-term direction is an arrangement-first creative workspace that combines production, precise editing, mixing and future extensibility. Aether Patcher is a possible future separate visual-programming application, not the current implementation priority.

## Current architecture

- **Desktop UI:** Flutter/Dart in `apps/desktop/`.
- **Audio engine/DSP:** Rust in `core/`.
- **Interop:** versioned C ABI in `bindings/c_abi/`, consumed through Dart FFI.
- **Audio I/O/decoding:** Rust engine components using the existing audio/device and decoder stack.
- **Target desktop platforms:** Windows and macOS.

Do not reintroduce C#/.NET/Avalonia as a second desktop frontend. Verify current project files before changing build scripts, APIs or dependency versions.

## Known implementation boundaries

- The Flutter workspace and arrangement are still prototype-stage; demo tracks/clips are not proof of a loaded or persisted project.
- Native engine initialization, telemetry and initial transport controls are wired through an adapter/controller. Verify every specific operation before treating it as end-to-end complete.
- The native engine exposes a set of transport, telemetry, device, test-tone and track operations; inspect `bindings/c_abi/src/lib.rs` as the source of truth before adding or assuming APIs.
- Record UI controls must not imply actual recording unless a real recording path exists.
- Live meters must use actual engine telemetry, not invented animation.
- Project save/load, MIDI editing, instruments, effects, automation, plugin hosting, spatial rendering and final export must not be claimed complete unless current code and tests prove it.

## Critical invariants

1. Preserve the reported Stop/rewind fix. A UI playhead reset is not proof that audio stopped; verify engine result and playback silence.
2. Never perform blocking I/O, blocking locks, sleep, logging, unbounded work or routine heap allocation/destruction in the real-time audio callback.
3. Keep Flutter responsive; long-running work and file/device operations must not block the UI isolate.
4. Keep Rust exports, C ABI declarations, Dart FFI signatures, ownership and error semantics synchronized.
5. Never silently represent an unsupported/failed native operation as success.
6. Treat session/media data as user work: avoid destructive changes and preserve recoverability.

## Current priorities

See [Feature Tracker](FEATURE_TRACKER.md) for the living backlog. Initial order:
1. Recheck and repair CI on the latest mainline.
2. Verify the Flutter ↔ Rust integration and transport behaviour on Windows/macOS.
3. Complete a coherent import → arrange → playback workflow.
4. Define and implement project save/reopen.
5. Add a basic stereo export path.
6. Grow editing, MIDI/instruments and effects through tested vertical slices.
7. Revisit spatial audio and advanced creative-engine experiments when core workflows are coherent.

## Known uncertainty

This document is not a runtime test report. It does not independently prove current CI status, device behaviour, audio output, persistence, export or platform packaging. Use current GitHub Actions logs and local results. Update this snapshot when evidence changes, and date it when a new status review is performed.

## Required handoff format

For each agent task, report **Implemented**, **Not implemented**, **Verified**, **Not verified**, **Known risks**, and **Next step**. Link the relevant PR/commit and checks when available.
