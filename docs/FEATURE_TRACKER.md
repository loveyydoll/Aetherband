# Aetherband Feature Tracker

**Last reviewed:** 2026-10-19  
**Purpose:** Migration handoff and prioritization. Status labels describe the current C++ target, not assumed parity with the legacy implementation.

## Status vocabulary

- **Verified:** acceptance criteria have been tested and evidence is recorded for the stated platform.
- **Implemented — unverified:** code exists, but required runtime/platform behavior has not been verified.
- **Prototype:** demonstration or incomplete implementation; do not present it as a complete workflow.
- **In progress:** active work exists but the feature is incomplete.
- **Planned:** not implemented yet.
- **Blocked:** a named dependency or decision prevents progress.

A merged pull request, API declaration, successful compile, or old implementation is not proof that the target C++ feature is verified.

## Current target architecture

C++20/CMake is the target foundation. Windows and macOS are required platforms. The native desktop framework is not finalized; JUCE is a leading candidate pending a technical spike. The existing Rust/C ABI/Flutter/Dart stack is retained as a reference during migration, not as the target architecture.

## Current C++ foundation

| Feature | Status | Evidence / next action |
|---|---|---|
| CMake C++20 project | Implemented — unverified | Added in `native/CMakeLists.txt`; build on Windows and macOS |
| Planar float audio buffer | Implemented — unverified | Added implementation and unit test; run CTest |
| Additive mixer | Implemented — unverified | Added implementation and unit test; run CTest |
| Native test harness | Implemented — unverified | CTest configured; run on both target platforms |
| Audio-device lifecycle and callback | Planned | Define device abstraction, callback ownership and lifecycle; prove playback on Windows/macOS |
| Transport and scheduling | Planned | Define timing model and bounded command flow |
| Executing DSP graph | Planned | Implement processor lifecycle, graph validation and actual audio processing |
| Deterministic offline rendering | Planned | Add known-signal/golden-output tests |
| Project/session model | Planned | Versioned schema, stable IDs, save/reopen and missing-media behavior |
| WAV import and multitrack playback | Planned for C++ target | End-to-end vertical slice |
| WAV export | Planned for C++ target | Deterministic offline stereo render and output validation |
| HypnoSynth C++ port | Planned | Audit original implementation and define regression fixtures |
| Recording, MIDI, effects, automation, undo/redo | Planned | Add in small tested slices after the core runtime works |
| Native desktop UI | Planned | Evaluate JUCE and alternatives through Windows/macOS spike |
| C# integrations | Optional / not currently needed | Add only for a concrete, justified use case |

## Immediate priorities

1. Configure/build the C++ foundation and run native tests on Windows and macOS.
2. Audit legacy Rust code, tests and session behavior to create a feature-by-feature port map.
3. Define audio buffer, sample-rate, block-size, channel-layout, processor lifecycle and command-queue contracts.
4. Implement a safe audio runtime and an executing DSP graph.
5. Prove deterministic offline processing and actual hardware playback.
6. Deliver a basic end-to-end WAV import → arrange → playback/mix → save/reopen → export workflow.
7. Port HypnoSynth and expand production features only after the vertical slice is reliable.

## Evidence requirements

For every status change, record:
- the code path and tests involved;
- whether the test is unit, integration, offline audio, or manual hardware verification;
- the operating system and relevant audio device where applicable;
- known limitations and what remains unverified.

See [C++ Migration Plan](CPP_MIGRATION_PLAN.md), [Project State](PROJECT_STATE.md), and [Architecture](ARCHITECTURE.md).
