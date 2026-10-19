# Aetherband — Project State Handoff

**Updated:** 2026-10-19  
**Evidence level:** GitHub source review and creation of the first C++ foundation. The new C++ code has not yet been built or run on Windows/macOS in this migration step.

## Product identity

Aetherband is an early-stage, open-source desktop DAW. Its intended direction is an arrangement-first creative workspace with native audio processing, its own DSP architecture, and room for instruments and sound-design workflows. Windows and macOS are required targets.

## Current architecture decision

- **Target application and audio runtime:** C++20 or newer where supported.
- **Native build system:** CMake.
- **Desktop framework:** not yet finalized; JUCE is a leading candidate pending a focused cross-platform proof.
- **DSP:** Aetherband-owned processing graph and processor contracts; third-party libraries may be used when appropriate.
- **Optional integrations:** C# only if a specific use case justifies it.
- **Legacy reference:** Rust engine, versioned C ABI, Flutter/Dart frontend and existing project documentation remain available during migration. Flutter/Dart are not the target UI stack.

## New C++ foundation

Branch: `rewrite/cpp-native-foundation`  
Draft PR: [#35 — Start native C++ foundation migration](https://github.com/loveyydoll/Aetherband/pull/35)

The branch currently adds:
- CMake project configured for C++20.
- Planar float audio buffer.
- Additive mixer.
- Initial native unit tests.
- Migration plan and build notes.

This is a foundation slice only. It does not yet implement device I/O, transport, an executing DSP graph, decoding, recording, sessions, export, HypnoSynth or a DAW UI. Tests are written but still need to be run on Windows and macOS.

## Legacy implementation

The previous Rust implementation contains useful reference behavior and should be audited subsystem-by-subsystem. Earlier documentation describes CPAL output, bounded queues, Symphonia decoding, Rubato resampling, track mixing, a versioned C ABI, HypnoSynth, session handling and WAV mixdown. Treat these as claims to verify against current source and tests, not as a guarantee that each workflow is reliable on hardware.

WAV is the only format previously reported as tested. Other formats require explicit validation.

## Immediate priorities

1. Build and run the C++ foundation on Windows and macOS; fix compiler warnings and test failures.
2. Inventory the existing Rust engine, tests, session schema and instrument behavior.
3. Specify audio callback, transport, processor lifecycle, buffer/channel, sample-rate and command-queue contracts.
4. Implement a minimal audio runtime and a real executing DSP graph.
5. Establish deterministic offline rendering and hardware playback checks.
6. Build a first useful vertical slice: WAV import, multitrack playback/mixing, save/reopen and WAV export.
7. Port HypnoSynth and additional workflows only after the foundation is validated.

## Migration rules

- Do not delete the legacy implementation in a bulk cleanup.
- Port validated behavior, not Rust code mechanically.
- Never claim runtime, device or platform support based on compilation alone.
- Keep UI, project model, media, DSP and audio runtime modular.
- No blocking I/O, allocation or contended locks in the real-time callback.
- Keep the README and feature tracker aligned with actual test evidence.

See [C++ Migration Plan](CPP_MIGRATION_PLAN.md), [Feature Tracker](FEATURE_TRACKER.md), [Architecture](ARCHITECTURE.md), and [Engine Foundation Audit](ENGINE_FOUNDATION_AUDIT.md).
